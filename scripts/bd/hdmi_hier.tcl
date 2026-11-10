# =============================================================================
# hdmi_hier.tcl  --  the HDMI input hierarchy (owner: Anthony)
#
# create_hdmi_hier <parent> <name> <clk_mhz>
#
# Built from Anthony's design (scripts/hdmi_rx_export.tcl), with every
# PS-supplied clock on the one PL clock (<clk_mhz>, D5 in docs/PLAN.md):
#
#   GTH lanes -> vid_phy_controller -> v_hdmi_rx_ss -> VIDEO_OUT (2 px/clk, 48 bit)
#             -> axis_register_slice -> system_ila
#   S_AXI -> SmartConnect -> v_hdmi_rx_ss (AXI-Lite), vid_phy_controller (AXI-Lite),
#                            axi_iic_0 -> MUX_IIC (board I2C mux 0x70 -> Si5342 jitter
#                            cleaner, which feeds the recovered TMDS clock back to the GTH)
#
# rx_video_clk and link_clk stay recovered from the HDMI input, inside this
# hierarchy. TODO (Anthony): threshold -> 2:1 converter after the register
# slice, then expose M_AXIS_PIX (1 bit/px, docs/hdmi-cca_interface.md).
#
# Pins: clk, peripheral_aresetn, S_AXI, DDC, MUX_IIC, HDMI/GTH pads, vphy_irq, rx_irq.
# axi_iic_0 settings are copied from Digilent's Genesys ZU HDMI demo; its
# Si5342 LOL GPIO is TX-only (vphy tx_refclk_rdy) and is left out.
# =============================================================================

proc create_hdmi_hier {parent name clk_mhz} {
    set old [current_bd_instance .]
    current_bd_instance $parent
    set hier [create_bd_cell -type hier $name]
    current_bd_instance $hier

    # ---- hierarchy pins -----------------------------------------------------
    create_bd_pin -dir I -type clk clk
    create_bd_pin -dir I -type rst peripheral_aresetn
    create_bd_intf_pin -mode Slave  -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI
    create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0   DDC
    create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0   MUX_IIC
    create_bd_pin -dir I -from 2 -to 0 phy_rxn_in
    create_bd_pin -dir I -from 2 -to 0 phy_rxp_in
    create_bd_pin -dir I -type clk mgtrefclk0_pad_n_in
    create_bd_pin -dir I -type clk mgtrefclk0_pad_p_in
    create_bd_pin -dir I -type clk mgtrefclk1_pad_n_in
    create_bd_pin -dir I -type clk mgtrefclk1_pad_p_in
    create_bd_pin -dir O -type clk rx_tmds_clk_n
    create_bd_pin -dir O -type clk rx_tmds_clk_p
    create_bd_pin -dir I cable_detect
    create_bd_pin -dir O hpd
    create_bd_pin -dir O -type intr vphy_irq
    create_bd_pin -dir O -type intr rx_irq

    # ---- cells (settings copied from scripts/hdmi_rx_export.tcl) -------------
    set rx [create_bd_cell -type ip -vlnv xilinx.com:ip:v_hdmi_rx_ss:3.2 v_hdmi_rx_ss_0]
    set_property -dict [list CONFIG.C_CD_INVERT {true} CONFIG.C_EXDES_TOPOLOGY {2}] $rx

    set vphy [create_bd_cell -type ip -vlnv xilinx.com:ip:vid_phy_controller:2.2 vid_phy_controller_0]
    set_property -dict [list \
        CONFIG.C_INPUT_PIXELS_PER_CLOCK {2} \
        CONFIG.C_NIDRU {false} \
        CONFIG.C_RX_REFCLK_SEL {1} \
        CONFIG.C_Rx_Protocol {HDMI} \
        CONFIG.C_TX_REFCLK_SEL {0} \
        CONFIG.C_Tx_Protocol {HDMI}] $vphy
    set_vphy_drpclk $vphy $clk_mhz

    set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc]
    set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 3] $smc

    # Polled by software (XIic_Send), so its interrupt is left unconnected
    set iic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 axi_iic_0]
    set_property -dict [list CONFIG.IIC_FREQ_KHZ {100}] $iic

    set rs [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_register_slice:1.1 axis_register_slice_0]
    set_property -dict [list \
        CONFIG.HAS_TKEEP {0} CONFIG.HAS_TLAST {1} CONFIG.HAS_TREADY {1} \
        CONFIG.HAS_TSTRB {0} CONFIG.TDATA_NUM_BYTES {6}] $rs

    set ila [create_bd_cell -type ip -vlnv xilinx.com:ip:system_ila:1.1 system_ila_0]
    set_property -dict [list \
        CONFIG.C_MON_TYPE {INTERFACE} \
        CONFIG.C_NUM_MONITOR_SLOTS {1} \
        CONFIG.C_SLOT_0_APC_EN {0} \
        CONFIG.C_SLOT_0_AXI_DATA_SEL {1} \
        CONFIG.C_SLOT_0_AXI_TRIG_SEL {1} \
        CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0}] $ila

    # Constants: register slice always ready (until the threshold exists),
    # audio unused, vphy AXI4-Stream resets held released.
    create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 tready_one
    set c [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 audio_aclk_zero]
    set_property CONFIG.CONST_VAL {0} $c
    set c [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 audio_aresetn_one]
    set_property CONFIG.CONST_VAL {1} $c
    create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 vphy_aresetn_one

    # ---- interfaces ---------------------------------------------------------
    connect_bd_intf_net [get_bd_intf_pins S_AXI] [get_bd_intf_pins axi_smc/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins v_hdmi_rx_ss_0/S_AXI_CPU_IN]
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M01_AXI] [get_bd_intf_pins vid_phy_controller_0/vid_phy_axi4lite]
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M02_AXI] [get_bd_intf_pins axi_iic_0/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins DDC] [get_bd_intf_pins v_hdmi_rx_ss_0/DDC_OUT]
    connect_bd_intf_net [get_bd_intf_pins MUX_IIC] [get_bd_intf_pins axi_iic_0/IIC]
    foreach ch {0 1 2} {
        connect_bd_intf_net [get_bd_intf_pins vid_phy_controller_0/vid_phy_rx_axi4s_ch$ch] \
                            [get_bd_intf_pins v_hdmi_rx_ss_0/LINK_DATA${ch}_IN]
    }
    connect_bd_intf_net [get_bd_intf_pins vid_phy_controller_0/vid_phy_status_sb_rx] \
                        [get_bd_intf_pins v_hdmi_rx_ss_0/SB_STATUS_IN]
    connect_bd_intf_net [get_bd_intf_pins v_hdmi_rx_ss_0/VIDEO_OUT] [get_bd_intf_pins axis_register_slice_0/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins axis_register_slice_0/M_AXIS] [get_bd_intf_pins system_ila_0/SLOT_0_AXIS]

    # ---- PS-supplied clock and reset: all on the one PL clock -----------------
    connect_bd_net [get_bd_pins clk] \
        [get_bd_pins axi_smc/aclk] \
        [get_bd_pins axi_iic_0/s_axi_aclk] \
        [get_bd_pins v_hdmi_rx_ss_0/s_axi_cpu_aclk] \
        [get_bd_pins v_hdmi_rx_ss_0/s_axis_video_aclk] \
        [get_bd_pins vid_phy_controller_0/drpclk] \
        [get_bd_pins vid_phy_controller_0/vid_phy_axi4lite_aclk] \
        [get_bd_pins vid_phy_controller_0/vid_phy_sb_aclk] \
        [get_bd_pins vid_phy_controller_0/vid_phy_tx_axi4s_aclk] \
        [get_bd_pins axis_register_slice_0/aclk] \
        [get_bd_pins system_ila_0/clk]
    connect_bd_net [get_bd_pins peripheral_aresetn] \
        [get_bd_pins axi_smc/aresetn] \
        [get_bd_pins axi_iic_0/s_axi_aresetn] \
        [get_bd_pins v_hdmi_rx_ss_0/s_axi_cpu_aresetn] \
        [get_bd_pins v_hdmi_rx_ss_0/s_axis_video_aresetn] \
        [get_bd_pins vid_phy_controller_0/vid_phy_axi4lite_aresetn] \
        [get_bd_pins vid_phy_controller_0/vid_phy_sb_aresetn] \
        [get_bd_pins axis_register_slice_0/aresetn] \
        [get_bd_pins system_ila_0/resetn]

    # ---- recovered clocks (from the HDMI input, not the PS) -------------------
    connect_bd_net [get_bd_pins vid_phy_controller_0/rx_video_clk] [get_bd_pins v_hdmi_rx_ss_0/video_clk]
    connect_bd_net [get_bd_pins vid_phy_controller_0/rxoutclk] \
        [get_bd_pins v_hdmi_rx_ss_0/link_clk] \
        [get_bd_pins vid_phy_controller_0/vid_phy_rx_axi4s_aclk]

    # ---- pads ---------------------------------------------------------------
    foreach p {phy_rxn_in phy_rxp_in mgtrefclk0_pad_n_in mgtrefclk0_pad_p_in
               mgtrefclk1_pad_n_in mgtrefclk1_pad_p_in} {
        connect_bd_net [get_bd_pins $p] [get_bd_pins vid_phy_controller_0/$p]
    }
    connect_bd_net [get_bd_pins vid_phy_controller_0/rx_tmds_clk_n] [get_bd_pins rx_tmds_clk_n]
    connect_bd_net [get_bd_pins vid_phy_controller_0/rx_tmds_clk_p] [get_bd_pins rx_tmds_clk_p]
    connect_bd_net [get_bd_pins cable_detect] [get_bd_pins v_hdmi_rx_ss_0/cable_detect]
    connect_bd_net [get_bd_pins v_hdmi_rx_ss_0/hpd] [get_bd_pins hpd]

    # ---- constants and interrupts -------------------------------------------
    connect_bd_net [get_bd_pins tready_one/dout] [get_bd_pins axis_register_slice_0/m_axis_tready]
    connect_bd_net [get_bd_pins audio_aclk_zero/dout] [get_bd_pins v_hdmi_rx_ss_0/s_axis_audio_aclk]
    connect_bd_net [get_bd_pins audio_aresetn_one/dout] [get_bd_pins v_hdmi_rx_ss_0/s_axis_audio_aresetn]
    connect_bd_net [get_bd_pins vphy_aresetn_one/dout] \
        [get_bd_pins vid_phy_controller_0/vid_phy_rx_axi4s_aresetn] \
        [get_bd_pins vid_phy_controller_0/vid_phy_tx_axi4s_aresetn]
    connect_bd_net [get_bd_pins vid_phy_controller_0/irq] [get_bd_pins vphy_irq]
    connect_bd_net [get_bd_pins v_hdmi_rx_ss_0/irq] [get_bd_pins rx_irq]

    current_bd_instance $old
    return $hier
}

# The video PHY's DRP clock frequency is a manual IP setting (it isn't
# propagated from the clock pin) and must match the real drpclk. The
# parameter name isn't pinned down here, so find it and print what was set.
proc set_vphy_drpclk {vphy clk_mhz} {
    set props [lsearch -all -inline -nocase [list_property $vphy] *DRPCLK*FREQ*]
    if {[llength $props] == 0} {
        puts "WARNING: no DRPCLK frequency parameter on [get_property NAME $vphy];\
set the DRP clock to $clk_mhz MHz in the vid_phy_controller GUI and copy the CONFIG line here"
        return
    }
    foreach p $props {
        set was [get_property $p $vphy]
        # Hz or MHz, depending on how the IP stores it
        set want [expr {$was > 1000000 ? int($clk_mhz * 1000000) : $clk_mhz}]
        set_property $p $want $vphy
        puts "[get_property NAME $vphy] $p: $was -> [get_property $p $vphy]"
    }
}

proc assign_hdmi_addresses {hier_name} {
    set data [get_bd_addr_spaces zynq_ultra_ps_e_0/Data]
    assign_bd_address -target_address_space $data -offset 0x80000000 -range 64K \
        [get_bd_addr_segs $hier_name/v_hdmi_rx_ss_0/S_AXI_CPU_IN/Reg] -force
    assign_bd_address -target_address_space $data -offset 0x80010000 -range 64K \
        [get_bd_addr_segs $hier_name/vid_phy_controller_0/vid_phy_axi4lite/Reg] -force
    assign_bd_address -target_address_space $data -offset 0x80020000 -range 64K \
        [get_bd_addr_segs $hier_name/axi_iic_0/S_AXI/Reg] -force
}
