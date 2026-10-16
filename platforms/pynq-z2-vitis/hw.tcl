# PYNQ-Z2 Vitis hardware platform: an extensible XSA that v++ links kernels into.
# vivado -mode batch -source hw.tcl -tclargs <out dir> <fclk MHz>
#
# PS7 (same PL-facing settings as ../pynq-z2/shell.tcl), FCLK_CLK0 with its reset, an AXI
# interrupt controller on IRQ_F2P for kernel interrupts, and the PFM properties that tell v++
# which clock, AXI ports and interrupt lines it may use:
#   clock      FCLK_CLK0 (id 0, default)
#   control    M_AXI_GP0 (kernels' s_axi_control, through an interconnect v++ adds)
#   memory     S_AXI_HP0..HP3 (kernel masters, sp=<kernel>.<port>:HP0 ...)

set out  [lindex $::argv 0]
set fclk [lindex $::argv 1]
if {$fclk eq ""} { set fclk 100 }
set part xc7z020clg400-1

file mkdir $out
create_project -force pynq_z2_vitis $out/hw -part $part
create_bd_design system

set ps7_def [lindex [lsort [get_ipdefs -all xilinx.com:ip:processing_system7:*]] end]
set ps [create_bd_cell -type ip -vlnv $ps7_def ps7]
set_property -dict [list \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $fclk \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP1 {1} \
    CONFIG.PCW_USE_S_AXI_HP2 {1} \
    CONFIG.PCW_USE_S_AXI_HP3 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
] $ps
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} $ps

set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_fclk0]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins rst_fclk0/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_fclk0/ext_reset_in]
foreach p {M_AXI_GP0_ACLK S_AXI_HP0_ACLK S_AXI_HP1_ACLK S_AXI_HP2_ACLK S_AXI_HP3_ACLK} {
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/$p]
}

# kernel interrupts: v++ wires them into this controller
set intc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc axi_intc_0]
set_property -dict [list CONFIG.C_IRQ_CONNECTION {1} CONFIG.C_KIND_OF_INTR {0xFFFFFFFF}] $intc
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
    Clk_master /ps7/FCLK_CLK0 Clk_slave /ps7/FCLK_CLK0 Clk_xbar /ps7/FCLK_CLK0 \
    Master /ps7/M_AXI_GP0 Slave /axi_intc_0/s_axi intc_ip {New AXI Interconnect} master_apm {0}] \
    [get_bd_intf_pins axi_intc_0/s_axi]
connect_bd_net [get_bd_pins axi_intc_0/irq] [get_bd_pins ps7/IRQ_F2P]
set concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat irq_concat]
connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins axi_intc_0/intr]

# what v++ may use
set_property PFM_NAME {caelum.dev:pynq:pynq_z2:1.0} [get_files system.bd]
set_property PFM.CLOCK {FCLK_CLK0 {id "0" is_default "true" proc_sys_reset "/rst_fclk0" status "fixed"}} $ps
# the interconnect automation made for the intc has free master ports for kernel control
set ic [get_bd_cells -filter {VLNV =~ "*axi_interconnect*"}]
set mi {}
set n [get_property CONFIG.NUM_MI $ic]
for {set i $n} {$i < 16} {incr i} {
    append mi [format "M%02d_AXI {memport \"M_AXI_GP\"} " $i]
}
set_property PFM.AXI_PORT $mi $ic
set_property PFM.AXI_PORT {S_AXI_HP0 {memport "S_AXI_HP" sptag "HP0" memory "ps7 HP0_DDR_LOWOCM"} \
                           S_AXI_HP1 {memport "S_AXI_HP" sptag "HP1" memory "ps7 HP1_DDR_LOWOCM"} \
                           S_AXI_HP2 {memport "S_AXI_HP" sptag "HP2" memory "ps7 HP2_DDR_LOWOCM"} \
                           S_AXI_HP3 {memport "S_AXI_HP" sptag "HP3" memory "ps7 HP3_DDR_LOWOCM"}} $ps
set irqs {}
for {set i 0} {$i < 32} {incr i} { append irqs "In$i {id $i} " }
set_property CONFIG.NUM_PORTS 32 $concat
set_property PFM.IRQ $irqs $concat

assign_bd_address
validate_bd_design
save_bd_design
set bd_file [get_files system.bd]
generate_target all $bd_file
make_wrapper -files $bd_file -top
add_files -norecurse [glob $out/hw/pynq_z2_vitis.gen/sources_1/bd/system/hdl/system_wrapper.v]
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

set_property platform.board_id pynq-z2 [current_project]
set_property platform.name pynq_z2 [current_project]
set_property platform.vendor caelum.dev [current_project]
set_property platform.version 1.0 [current_project]
set_property platform.design_intent.embedded true [current_project]
set_property platform.design_intent.server_managed false [current_project]
set_property platform.design_intent.external_host false [current_project]
set_property platform.design_intent.datacenter false [current_project]
set_property platform.default_output_type sd_card [current_project]
set_property platform.extensible true [current_project]
write_hw_platform -force -hw $out/pynq_z2.xsa
puts "wrote $out/pynq_z2.xsa"
