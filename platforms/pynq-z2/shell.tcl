# PYNQ-Z2 shell: Zynq PS7 and one Caelum kernel in a block design named `system`.
# caelum-target-vivado sources this inside its project and calls
#   caelum_shell <kernel ip vlnv>
#
# The kernel is wired like an HLS IP so PYNQ drives it the same way:
#   s_axi_control  <- M_AXI_GP0 (AXI4-Lite registers, 0x4000_0000)
#   every m_axi    -> S_AXI_HP0 (PS DDR, 32-bit addresses)
#   ap_clk         <- FCLK_CLK0 (ZYNQ_FCLK_MHZ, target option fclk-mhz)
#   ap_rst_n       <- proc_sys_reset peripheral_aresetn
#   interrupt      -> IRQ_F2P
#
# PS settings are the PYNQ-Z2 ones that matter to the PL and to PYNQ (it reads the clocks from the
# .hwh): 50 MHz PS_CLK, DDR3 MT41K256M16 x16. The PYNQ image's own boot files bring the PS up, the
# bitstream doesn't carry any PS setup, so MIO peripherals are left at their defaults.

proc caelum_shell_fclk {} {
    if {[info exists ::env(CAELUM_OPT_FCLK_MHZ)]} { return $::env(CAELUM_OPT_FCLK_MHZ) }
    if {[info exists ::env(ZYNQ_FCLK_MHZ)]} { return $::env(ZYNQ_FCLK_MHZ) }
    return 100
}

proc caelum_shell {vlnv} {
    set fclk [caelum_shell_fclk]
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
        CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
        CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
        CONFIG.PCW_IRQ_F2P_INTR {1} \
    ] $ps
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} $ps

    set k [create_bd_cell -type ip -vlnv $vlnv kernel]
    set clk /ps7/FCLK_CLK0

    # control registers on GP0
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
        Clk_master $clk Clk_slave $clk Clk_xbar $clk \
        Master {/ps7/M_AXI_GP0} Slave {/kernel/s_axi_control} \
        intc_ip {New AXI Interconnect} master_apm {0}] [get_bd_intf_pins kernel/s_axi_control]

    # kernel memory masters into DDR through HP0
    set masters [get_bd_intf_pins -of_objects $k -filter {MODE == Master}]
    if {[llength $masters] == 0} {
        puts "ERROR: kernel has no AXI master (expected m_axi ports like gmem_araddr ...)"
        exit 1
    }
    foreach m $masters {
        apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
            Clk_master $clk Clk_slave $clk Clk_xbar $clk \
            Master $m Slave {/ps7/S_AXI_HP0} \
            intc_ip {Auto} master_apm {0}] [get_bd_intf_pins ps7/S_AXI_HP0]
    }

    # clock and reset when the automation left them open
    set rst [get_bd_pins -quiet -hierarchical -filter {NAME == peripheral_aresetn}]
    foreach {pin src} [list kernel/ap_clk $clk kernel/ap_rst_n [lindex $rst 0]] {
        if {[llength [get_bd_nets -quiet -of_objects [get_bd_pins $pin]]] == 0} {
            connect_bd_net [get_bd_pins $src] [get_bd_pins $pin]
        }
    }
    if {[llength [get_bd_pins -quiet kernel/interrupt]] > 0} {
        connect_bd_net [get_bd_pins kernel/interrupt] [get_bd_pins ps7/IRQ_F2P]
    }

    assign_bd_address
    validate_bd_design
    save_bd_design
    return system
}
