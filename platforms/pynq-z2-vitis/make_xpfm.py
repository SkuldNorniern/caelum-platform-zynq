# PYNQ-Z2 Vitis platform (.xpfm) from the extensible XSA hw.tcl writes.
# vitis -s make_xpfm.py <xsa> <out dir>
# One Linux domain on the A9s, no boot files: v++ only needs the hardware side to link kernels,
# the PYNQ image on the SD card is the software side.
import sys

import vitis

xsa, out = sys.argv[1], sys.argv[2]
client = vitis.create_client()
client.set_workspace(path=out)
platform = client.create_platform_component(
    name="pynq_z2",
    hw_design=xsa,
    os="linux",
    cpu="ps7_cortexa9",
    no_boot_bsp=True,
)
platform.build()
print("xpfm:", platform.generate_xpfm() if hasattr(platform, "generate_xpfm") else out)
vitis.dispose()
