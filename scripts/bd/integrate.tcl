# =============================================================================
# integrate.tcl  --  integrated top-level block design (PS, clock, reset, glue)
#
# Sourced by scripts/create_project.tcl after src/hdl is in sources_1. This
# script, not a .bd file, is the source of truth for the block design.
#
# create_integrate <repo_root> <cca_num_labels> <variant> <clk_mhz>
#
# Builds a design named pl_ps (wrapper pl_ps_wrapper) so generate_bitstream.tcl
# and run_board.tcl work unchanged. scripts/bd/pl_ps.tcl is the original
# pre-integration design and is left as is.
#
#   variant hdmi:     hdmi_in (scripts/bd/hdmi_hier.tcl) + centroiding
#   variant pattern:  pattern_gen + centroiding (fallback / pre-HDMI build)
#
# Both variants:
#   one PL clock, pl_clk0 = <clk_mhz>, and one proc_sys_reset for the whole PL
#   PS M_AXI_HPM0_FPD -> centroiding  (BRAM @ 0xA000_0000, axi_intc @ 0xA001_0000)
#   pl_ps_irq0[2] = centroiding irq  (GIC ID 123)
# hdmi only:
#   PS M_AXI_HPM0_LPD -> hdmi_in      (RX SS @ 0x8000_0000, video PHY @ 0x8001_0000,
#                                      axi_iic_0 @ 0x8002_0000 -> mux_scl/sda_io)
#   pl_ps_irq0[0] = video PHY, [1] = HDMI RX
# pattern only:
#   button / axi_gpio (0xA002_0000) -> pattern_gen -> centroiding
#
# The hdmi_in -> centroiding pixel stream is not connected yet: it needs
# Anthony's threshold and 2:1 converter (see hdmi_hier.tcl). Until then
# centroiding's s_axis inputs are tied off.
# =============================================================================

source [file join [file dirname [info script]] centroid_hier.tcl]
source [file join [file dirname [info script]] hdmi_hier.tcl]

proc create_integrate {repo_root cca_num_labels variant clk_mhz} {
    if {$variant ni {hdmi pattern}} { error "variant must be hdmi or pattern, got '$variant'" }

    create_bd_design pl_ps

    # ---- Zynq PS ------------------------------------------------------------
    set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0]
    source $repo_root/scripts/bd/pl_ps_zynq.tcl
    # Drop values Vivado derives (clock actuals, protection maps) so the
    # changes below aren't fought by stale copies.
    set base [dict remove $pl_ps_zynq_config \
        CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ \
        CONFIG.PSU__PROTECTION__SLAVES \
        CONFIG.PSU__PROTECTION__MASTERS]
    set_property -dict $base $ps
    set_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $clk_mhz $ps

    if {$variant eq "hdmi"} {
        # From Anthony's design: HPM0_LPD for HDMI control, UART1 and GPIO on EMIO
        set_property -dict [list \
            CONFIG.PSU__USE__M_AXI_GP2 {1} \
            CONFIG.PSU__MAXIGP2__DATA_WIDTH {32} \
            CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} \
            CONFIG.PSU__UART1__PERIPHERAL__IO {EMIO} \
            CONFIG.PSU__UART1__BAUD_RATE {115200} \
            CONFIG.PSU__GPIO_EMIO__PERIPHERAL__ENABLE {1} \
            CONFIG.PSU__GPIO_EMIO__PERIPHERAL__IO {3}] $ps
    }

    # The Digilent board preset describes the DDR4 wrong (4 Gb x8 parts); the
    # board has 8 Gb x16 and the A53 hangs on first DDR access otherwise
    # (commit 79e0893). Set last and checked after validation.
    set ddr_config {
        CONFIG.PSU__DDRC__DEVICE_CAPACITY      {8192 MBits}
        CONFIG.PSU__DDRC__DRAM_WIDTH           {16 Bits}
        CONFIG.PSU__DDRC__ROW_ADDR_COUNT       {16}
        CONFIG.PSU__DDRC__BG_ADDR_COUNT        {1}
        CONFIG.PSU__CRF_APB__DDR_CTRL__FREQMHZ {1065}
    }
    set_property -dict $ddr_config $ps

    # ---- clock, reset, interrupts ---------------------------------------------
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_pl
    connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins rst_pl/ext_reset_in]

    set irqs [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 irq_concat]
    set_property CONFIG.NUM_PORTS {8} $irqs
    set zero [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 irq_zero]
    set_property CONFIG.CONST_VAL {0} $zero
    connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]

    set clk_pins  [list [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] [get_bd_pins rst_pl/slowest_sync_clk]]
    set rstn_pins [list]
    set unused_irqs {3 4 5 6 7}

    # ---- centroiding (both variants) ----------------------------------------
    create_centroid_hier / centroiding $cca_num_labels
    connect_bd_net [get_bd_pins rst_pl/peripheral_reset] [get_bd_pins centroiding/peripheral_reset]
    lappend clk_pins  [get_bd_pins centroiding/clk]
    lappend rstn_pins [get_bd_pins centroiding/peripheral_aresetn]
    connect_bd_net [get_bd_pins centroiding/irq] [get_bd_pins irq_concat/In2]

    if {$variant eq "hdmi"} {
        build_hdmi_variant $clk_mhz
        lappend clk_pins  [get_bd_pins hdmi_in/clk] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_lpd_aclk]
        lappend rstn_pins [get_bd_pins hdmi_in/peripheral_aresetn]
    } else {
        build_pattern_variant
        lappend clk_pins  [get_bd_pins sync_debouncer_0/sys_clk] [get_bd_pins pattern_gen_0/i_clk] \
                          [get_bd_pins axi_smc/aclk] [get_bd_pins axi_gpio_0/s_axi_aclk]
        lappend rstn_pins [get_bd_pins axi_smc/aresetn] [get_bd_pins axi_gpio_0/s_axi_aresetn]
        set unused_irqs {0 1 3 4 5 6 7}
    }

    connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] {*}$clk_pins
    connect_bd_net [get_bd_pins rst_pl/peripheral_aresetn] {*}$rstn_pins
    connect_bd_net [get_bd_pins irq_zero/dout] {*}[lmap i $unused_irqs {get_bd_pins irq_concat/In$i}]

    # ---- addresses (docs/pl-ps_interface_spec.md, src/sw) ---------------------
    assign_centroid_addresses centroiding
    if {$variant eq "hdmi"} {
        assign_hdmi_addresses hdmi_in
    } else {
        assign_bd_address -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
            -offset 0xA0020000 -range 64K [get_bd_addr_segs axi_gpio_0/S_AXI/Reg] -force
    }

    validate_bd_design

    # ---- checks -------------------------------------------------------------
    check_centroid_hier centroiding
    if {$variant eq "hdmi"} { check_hdmi_hier hdmi_in $clk_mhz }
    foreach {param want} $ddr_config {
        set got [get_property $param $ps]
        if {$got ne $want} { error "zynq_ultra_ps_e_0 $param = '$got', expected '$want' (DDR4 on the Genesys ZU)" }
    }
    set act [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ $ps]
    # Below 74.25 MHz the CCL falls behind 1080p30 (docs/PLAN.md)
    if {$act < 74.25} { error "pl_clk0 actual = $act MHz, must be >= 74.25 (asked for $clk_mhz)" }
    puts "pl_ps ($variant): pl_clk0 actual $act MHz; DDR 8192 MBits x16; centroiding irq on pl_ps_irq0\[2\] (GIC 123)"

    save_bd_design
}

# hdmi_in hierarchy plus its board ports (names match src/xdc/Genesys_ZU_revC.xdc)
proc build_hdmi_variant {clk_mhz} {
    connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins centroiding/S_AXI]
    create_hdmi_hier / hdmi_in $clk_mhz
    connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_LPD] [get_bd_intf_pins hdmi_in/S_AXI]

    foreach {port pin dir type} {
        phy_rxn_in_0          phy_rxn_in          I {}
        phy_rxp_in_0          phy_rxp_in          I {}
        mgtrefclk0_pad_n_in_0 mgtrefclk0_pad_n_in I clk
        mgtrefclk0_pad_p_in_0 mgtrefclk0_pad_p_in I clk
        mgtrefclk1_pad_n_in_0 mgtrefclk1_pad_n_in I clk
        mgtrefclk1_pad_p_in_0 mgtrefclk1_pad_p_in I clk
        hdmi_rec_clk_n        rx_tmds_clk_n       O clk
        hdmi_rec_clk_p        rx_tmds_clk_p       O clk
        hdmi_rx_5v_detn       cable_detect        I {}
        hdmi_rx_hpd           hpd                 O {}
    } {
        set args [list -dir $dir]
        if {$type ne ""} { lappend args -type $type }
        if {[string match phy_rx* $port]} { lappend args -from 2 -to 0 }
        create_bd_port {*}$args $port
        connect_bd_net [get_bd_ports $port] [get_bd_pins hdmi_in/$pin]
    }
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 hdmi_rx_ddc
    connect_bd_intf_net [get_bd_intf_ports hdmi_rx_ddc] [get_bd_intf_pins hdmi_in/DDC]
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 mux
    connect_bd_intf_net [get_bd_intf_ports mux] [get_bd_intf_pins hdmi_in/MUX_IIC]

    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 UART_CTL
    connect_bd_intf_net [get_bd_intf_ports UART_CTL] [get_bd_intf_pins zynq_ultra_ps_e_0/UART_1]
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 gpio_emio
    connect_bd_intf_net [get_bd_intf_ports gpio_emio] [get_bd_intf_pins zynq_ultra_ps_e_0/GPIO_0]

    connect_bd_net [get_bd_pins hdmi_in/vphy_irq] [get_bd_pins irq_concat/In0]
    connect_bd_net [get_bd_pins hdmi_in/rx_irq]   [get_bd_pins irq_concat/In1]

    # No pixel stream yet (threshold/converter pending): centroiding sees an
    # idle stream (tvalid = 0).
    set z [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 pix_idle]
    set_property CONFIG.CONST_VAL {0} $z
    connect_bd_net [get_bd_pins pix_idle/dout] \
        [get_bd_pins centroiding/s_axis_tvalid] \
        [get_bd_pins centroiding/s_axis_tuser] \
        [get_bd_pins centroiding/s_axis_tlast]
}

# pattern_gen fallback: button OR axi_gpio bit 0 -> pattern_gen -> centroiding
proc build_pattern_variant {} {
    set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc]
    set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2] $smc
    # PS HPM0_FPD shared by centroiding and axi_gpio
    connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins axi_smc/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins centroiding/S_AXI]

    set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0]
    set_property -dict [list CONFIG.C_GPIO_WIDTH 1 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_DOUT_DEFAULT 0x00000000] $gpio
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M01_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]

    # util_vector_logic is being replaced by inline-HDL ilvector_logic
    set or_vlnv [lindex [get_ipdefs -all -filter {NAME == ilvector_logic}] end]
    if {$or_vlnv eq ""} { set or_vlnv [lindex [get_ipdefs -all -filter {NAME == util_vector_logic}] end] }
    if {$or_vlnv eq ""} { error "neither ilvector_logic nor util_vector_logic IP found" }
    set or_type [expr {[lindex [split $or_vlnv :] 1] eq "inline_hdl" ? "inline_hdl" : "ip"}]
    set enable_or [create_bd_cell -type $or_type -vlnv $or_vlnv enable_or]
    set_property -dict [list CONFIG.C_OPERATION or CONFIG.C_SIZE 1] $enable_or

    # 3x3 square moving +4 px/frame against static shapes
    set pg [create_bd_cell -type module -reference pattern_gen_bd pattern_gen_0]
    set_property CONFIG.MOVE_ENABLE 1 $pg
    catch {set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_pins pattern_gen_0/i_rst]}
    create_bd_cell -type module -reference sync_debouncer sync_debouncer_0

    create_bd_port -dir I button
    connect_bd_net [get_bd_ports button] [get_bd_pins sync_debouncer_0/button]
    connect_bd_net [get_bd_pins sync_debouncer_0/sync_deb_signal] [get_bd_pins enable_or/Op1]
    connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o] [get_bd_pins enable_or/Op2]
    connect_bd_net [get_bd_pins enable_or/Res] [get_bd_pins pattern_gen_0/i_enable]
    connect_bd_net [get_bd_pins rst_pl/peripheral_reset] [get_bd_pins pattern_gen_0/i_rst]
    foreach sig {tdata tvalid tuser tlast} {
        connect_bd_net [get_bd_pins pattern_gen_0/m_axis_$sig] [get_bd_pins centroiding/s_axis_$sig]
    }
}
