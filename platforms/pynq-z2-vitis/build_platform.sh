#!/bin/sh
# build_platform.sh <cache dir>: the PYNQ-Z2 Vitis platform, built once and reused.
# Prints the .xpfm path on the last line. caelum-target-vitis runs this when the platform has no
# installed shell (VITIS_PLATFORM unset): extensible XSA from hw.tcl (vivado), then the .xpfm (vitis).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
cache=$1
fclk=${CAELUM_OPT_FCLK_MHZ:-${ZYNQ_FCLK_MHZ:-100}}
dir=$cache/pynq_z2_${fclk}mhz
xpfm=$dir/ws/pynq_z2/export/pynq_z2/pynq_z2.xpfm
# rebuild when the recipe changed
stamp=$(cat "$here/hw.tcl" "$here/make_xpfm.py" | cksum | cut -d' ' -f1)
if [ -f "$xpfm" ] && [ "$(cat "$dir/stamp" 2>/dev/null)" = "$stamp" ]; then
  echo "$xpfm"
  exit 0
fi
rm -rf "$dir"
mkdir -p "$dir"
echo "pynq-z2: building the Vitis platform ($fclk MHz) in $dir" >&2
( cd "$dir" && vivado -mode batch -nojournal -log hw.log -source "$here/hw.tcl" -tclargs "$dir" "$fclk" >&2 ) \
  || { echo "pynq-z2: platform XSA failed, log: $dir/hw.log" >&2; exit 1; }
( cd "$dir" && vitis -s "$here/make_xpfm.py" "$dir/pynq_z2.xsa" "$dir/ws" >&2 ) \
  || { echo "pynq-z2: xpfm failed" >&2; exit 1; }
[ -f "$xpfm" ] || { echo "pynq-z2: no $xpfm after the build" >&2; exit 1; }
echo "$stamp" > "$dir/stamp"
echo "$xpfm"
