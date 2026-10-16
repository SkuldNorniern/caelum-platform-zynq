#!/bin/sh
# caelum run --target <t>: copy <top>.bit + <top>.hwh and the host to a PYNQ board and run it there
# as root (it maps /dev/mem and loads the PL).
#   Rust host (host = "host/main.rs"): the binary caelum built (CAELUM_HOST_BIN), a design.toml for
#                                      caelum::host::open() and the kernel.xml
#   Python host (host = "host/run.py"): the host folder, run with PYNQ's Python
#
# from caelum:    CAELUM_OUT_DIR CAELUM_TOP CAELUM_HOST CAELUM_HOST_BIN CAELUM_HOST_BACKEND
# target options: board          ssh destination, default xilinx@192.168.2.99 (PYNQ over a direct cable)
#                 ssh-key        identity file, default ssh's own
#                 sudo-password  for sudo on the board (the PYNQ image's is "xilinx"); unset, sudo asks
#                 kernel-xml     the kernel's arguments, for a Rust host
#                 args           extra arguments for the host
set -eu

die() { echo "pynq: $*" >&2; exit 1; }
out=$CAELUM_OUT_DIR
top=$CAELUM_TOP
board=${CAELUM_OPT_BOARD:-xilinx@192.168.2.99}
[ -f "$out/$top.bit" ] || die "no $top.bit in $out, run caelum build --target first"
[ -f "$out/$top.hwh" ] || die "no $top.hwh in $out"
[ -n "${CAELUM_HOST:-}" ] || die "set host = \"<script>.py\" in the [target] table"

ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
if [ -n "${CAELUM_OPT_SSH_KEY:-}" ]; then
  case $CAELUM_OPT_SSH_KEY in
    "~/"*) key="$HOME/${CAELUM_OPT_SSH_KEY#\~/}" ;;
    *) key=$CAELUM_OPT_SSH_KEY ;;
  esac
  ssh_opts="$ssh_opts -i $key"
fi

dest=caelum/$top
echo "pynq: $top.bit -> $board:~/$dest"
# shellcheck disable=SC2086
ssh $ssh_opts "$board" "mkdir -p $dest" || die "can't reach $board (cable, board IP, PC on 192.168.2.x?)"

if [ -n "${CAELUM_HOST_BIN:-}" ]; then
  # Rust host: the binary, the design files and the design.toml that says how to load them
  [ -n "${CAELUM_OPT_KERNEL_XML:-}" ] || die "a Rust host needs kernel-xml = \"...\" in the [target] table"
  design=$out/design.toml
  cat > "$design" <<TOML
# written by caelum-platform-zynq run.sh: what caelum::host::open() loads
backend = "${CAELUM_HOST_BACKEND:-zynq}"
bitstream = "$top.bit"
hw = "$top.hwh"
kernels = ["kernel.xml"]
TOML
  # shellcheck disable=SC2086
  scp $ssh_opts -q "$out/$top.bit" "$out/$top.hwh" "$design" "$board:$dest/"
  # shellcheck disable=SC2086
  scp $ssh_opts -q "$CAELUM_ROOT/$CAELUM_OPT_KERNEL_XML" "$board:$dest/kernel.xml"
  # shellcheck disable=SC2086
  scp $ssh_opts -q "$CAELUM_HOST_BIN" "$board:$dest/host"
  run="cd \$HOME/$dest && ./host ${CAELUM_OPT_ARGS:-}"
else
  # shellcheck disable=SC2086
  scp $ssh_opts -q "$out/$top.bit" "$out/$top.hwh" $(find "$(dirname "$CAELUM_HOST")" -maxdepth 1 -type f ! -name '*.pyc') "$board:$dest/"
  run=". /etc/profile.d/pynq_venv.sh && . /etc/profile.d/xrt_setup.sh; cd \$HOME/$dest && python3 $(basename "$CAELUM_HOST") $top.bit ${CAELUM_OPT_ARGS:-}"
fi

# shellcheck disable=SC2086
if [ -n "${CAELUM_OPT_SUDO_PASSWORD:-}" ]; then
  printf '%s\n' "$CAELUM_OPT_SUDO_PASSWORD" | ssh $ssh_opts "$board" "sudo -S -p '' HOME=\$HOME bash -c '$run'"
else
  exec ssh -t $ssh_opts "$board" "sudo HOME=\$HOME bash -c '$run'"
fi
