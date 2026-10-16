# caelum-platform-zynq

AMD Zynq-7000 boards as Caelum platforms, for [caelum-target-vitis](https://github.com/SkuldNorniern/caelum-target-vitis) and [caelum-target-vivado](https://github.com/SkuldNorniern/caelum-target-vivado).

| id | board | part | PS memory |
|----|-------|------|-----------|
| `zynq::pynq-z2-vitis` | TUL PYNQ-Z2, Vitis (v++ link) | xc7z020clg400-1 | 512 MB DDR3 |
| `zynq::pynq-z2` | TUL PYNQ-Z2, plain Vivado block design | xc7z020clg400-1 | 512 MB DDR3 |

## vitis (main)

```toml
[target-dependencies]
vitis = { git = "https://github.com/SkuldNorniern/caelum-target-vitis" }
zynq = { git = "https://github.com/SkuldNorniern/caelum-platform-zynq" }

[target.pynq-z2]
provider = "vitis"
platform = "zynq::pynq-z2-vitis"
kernel-xml = "kernel.xml"        # as for Alveo
config = "pynq-z2.cfg"           # nk=Top:1:Top_1, sp=Top_1.gmem:HP0
host = "host/run.py"
board = "xilinx@192.168.2.99"
```

Vitis 2025.2 ships no Zynq-7000 platform, so this one builds its own: `build_platform.sh` runs `hw.tcl` (Vivado: PS7, FCLK0 + reset, AXI INTC on IRQ_F2P, PFM clock / AXI port / IRQ properties, extensible XSA) and `make_xpfm.py` (`vitis -s`: the .xpfm). caelum-target-vitis calls it when `VITIS_PLATFORM` isn't set and caches the result in `build/.platforms/` until the recipe changes. Mode `hw` only (no hw_emu: that needs a sysroot and QEMU images).

v++ gives `kernel.xclbin`; the build also copies `<top>.bit` and `<top>.hwh` out of the link, which is what a PYNQ image loads (`pynq.Overlay`, the kernel is `Gemm_1` style `<top>_1`). Memory ports: `sp=<kernel>.<port>:HP0` .. `HP3`. The kernel's master address is 32 bits.

## vivado

```toml
[target-dependencies]
vivado = { git = "https://github.com/SkuldNorniern/caelum-target-vivado" }
zynq = { git = "https://github.com/SkuldNorniern/caelum-platform-zynq" }

[target.pynq-z2]
provider = "vivado"
platform = "zynq::pynq-z2"
mode = "bitstream"
host = "host/run.py"              # runs on the board with `caelum run`
board = "xilinx@192.168.2.99"     # ssh destination, this is the default
# fclk-mhz = 100                  # FCLK_CLK0, the kernel clock
```

```bash
caelum build --target pynq-z2     # <top>.bit, <top>.hwh, <top>.xsa in build/pynq-z2/bitstream/
caelum run --target pynq-z2       # copy bit + hwh + the host folder to the board, run the host there
```

## the shell

A platform here is a block design, the way an Alveo platform is a Vitis shell. `shell.tcl` puts the Caelum top in it, wired like an HLS IP so PYNQ drives it with `Overlay` / `DefaultIP`:

| kernel port | goes to |
|-------------|---------|
| `ap_clk` | FCLK_CLK0 (100 MHz) |
| `ap_rst_n` | proc_sys_reset |
| `s_axi_control_*` (AXI4-Lite) | M_AXI_GP0, at 0x4000_0000 |
| every AXI4 master (`gmem_*` ...) | S_AXI_HP0, PS DDR, 32-bit addresses |
| `interrupt` | IRQ_F2P |

So the top needs the Vitis RTL kernel names (`ap_clk`, `ap_rst_n`, `s_axi_control_*`, masters like `gmem_araddr`) and a 32-bit master address. caelum-target-vivado packages the top as an IP, calls `caelum_shell <vlnv>` from `shell.tcl`, and builds the wrapper (project flow, block designs need a project). The block design instance is `kernel`, so in Python it is `Overlay("Top.bit").kernel`.

The PS7 settings are only the ones that matter to the PL and to PYNQ (50 MHz PS_CLK, DDR3 x16, FCLK0, GP0, HP0, IRQ). The PYNQ image's boot files set the PS up, the bitstream never does, so the `.xsa` is not meant for building an FSBL.

## host programs

Both platforms have a `[host]` table: Rust hosts (`host = "host/main.rs"`) are built by caelum as static `armv7-unknown-linux-musleabihf` binaries (linked with `rust-lld`, nothing to install on the board or the PC besides `rustup target add armv7-unknown-linux-musleabihf`) and use the `zynq` backend of `caelum::host`. `run.sh` copies the binary, `<top>.bit`, `<top>.hwh`, the target's `kernel-xml` and a `design.toml` naming them, then runs it; with a `host = "....py"` it copies the host folder and runs it with PYNQ's Python instead.

```rust
let mut dev = caelum::host::open()?;   // design.toml next to the binary
let mut k = dev.kernel("Gemm")?;
```

target options for `run.sh`: `board` (ssh destination, default `xilinx@192.168.2.99`), `ssh-key`, `sudo-password` (the PYNQ image's is `xilinx`; unset, sudo asks), `args`.

The PYNQ image's boot files run the IO PLL at 1000 MHz, the `.hwh` dividers are for Vivado's 1600 MHz: loading a design through PYNQ alone gives 62.5 MHz for a 100 MHz FCLK0. `caelum::host` (and `host/accelerator.py` style code: `Clocks.fclk0_mhz = 100`) sets the clock for the PLL that is running.

## hw_emu

not yet. Vitis can co-simulate a Zynq-7000 (QEMU for the A9s, XSim for the PL, `launch_emulator`), but the platform needs an emulation XSA (PS7 TLM model) besides the hardware one, and QEMU needs a Linux with zocl: AMD's Zynq common image, or the board's own kernel (`image.ub`) and `zocl.ko` with an initramfs that runs the host. Until then: `caelum test` for the kernel, the board for the system.

## board side

`run.sh` needs a PYNQ image booted (SD boot jumper) and ssh to it. Over a direct cable the board is at 192.168.2.99, give the PC 192.168.2.1/24.
