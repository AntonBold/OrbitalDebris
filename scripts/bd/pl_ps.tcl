# =============================================================================
# pl_ps.tcl  --  build the pl_ps block design from scratch
#
# Sourced by scripts/create_project.tcl after src/hdl is in sources_1. This
# script, not a .bd file, is the source of truth for the block design.
#
#   button -> sync_debouncer -> pattern_gen -> cca_top -> BRAM port B
#   PS M_AXI_HPM0_FPD -> SmartConnect -> AXI BRAM ctrl (BRAM port A) @ 0xA000_0000
#                                     -> axi_intc                    @ 0xA001_0000
#   cca_top.o_interrupt -> axi_intc (rising edge) -> pl_ps_irq0 -> GIC
#
# cca_top, pattern_gen and sync_debouncer are module references: each build
# synthesizes the current src/hdl files directly, so there is no packaged
# copy to go stale.
# =============================================================================

proc create_pl_ps {repo_root cca_num_labels} {

    create_bd_design pl_ps

    # ---- Zynq PS ------------------------------------------------------------
    set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0]
    source $repo_root/scripts/bd/pl_ps_zynq.tcl
    set_property -dict $pl_ps_zynq_config $ps

    # ---- Xilinx IP ----------------------------------------------------------
    set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc]
    set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2] $smc

    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps8_0_100M

    set bram_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0]
    set_property CONFIG.SINGLE_PORT_BRAM 1 $bram_ctrl

    # Port A: AXI BRAM controller (PS reads). Port B: cca_top (PL writes).
    set bram [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 axi_bram_ctrl_0_bram]
    set_property CONFIG.Memory_Type True_Dual_Port_RAM $bram

    # Level output to the GIC; edge-sensitive input, because o_interrupt is
    # a 1-cycle pulse (docs/pl-ps_interface_spec.md). The input kind is
    # normally auto-propagated from the source pin, and a module-reference
    # pin propagates as level, so set it explicitly. Checked after validation.
    set intc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 axi_intc_0]
    set_property -dict [list \
        CONFIG.C_IRQ_CONNECTION 1 \
        CONFIG.C_IRQ_IS_LEVEL   1 \
        CONFIG.C_KIND_OF_INTR.VALUE_SRC USER \
        CONFIG.C_KIND_OF_INTR   0xFFFFFFFF \
        CONFIG.C_KIND_OF_EDGE.VALUE_SRC USER \
        CONFIG.C_KIND_OF_EDGE   0xFFFFFFFF] $intc

    # ---- RTL module references ----------------------------------------------
    set cca [create_bd_cell -type module -reference cca_top cca_top_0]
    set_property CONFIG.NUM_LABELS $cca_num_labels $cca
    create_bd_cell -type module -reference pattern_gen    pattern_gen_0
    create_bd_cell -type module -reference sync_debouncer sync_debouncer_0

    # Vivado infers clock/reset/interrupt pins on module references from
    # their names; make the attributes match the RTL where it inferred them.
    foreach pin {cca_top_0/rst pattern_gen_0/i_rst} {
        catch {set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_pins $pin]}
    }
    catch {set_property CONFIG.SENSITIVITY EDGE_RISING [get_bd_pins cca_top_0/o_interrupt]}

    # ---- external port ------------------------------------------------------
    create_bd_port -dir I button

    # ---- AXI ----------------------------------------------------------------
    connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins axi_smc/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins axi_bram_ctrl_0/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M01_AXI] [get_bd_intf_pins axi_intc_0/s_axi]
    connect_bd_intf_net [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTA] [get_bd_intf_pins axi_bram_ctrl_0_bram/BRAM_PORTA]

    # ---- clock and resets ---------------------------------------------------
    connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
        [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
        [get_bd_pins axi_smc/aclk] \
        [get_bd_pins axi_bram_ctrl_0/s_axi_aclk] \
        [get_bd_pins axi_intc_0/s_axi_aclk] \
        [get_bd_pins rst_ps8_0_100M/slowest_sync_clk] \
        [get_bd_pins sync_debouncer_0/sys_clk] \
        [get_bd_pins pattern_gen_0/i_clk] \
        [get_bd_pins cca_top_0/clk]
    connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins rst_ps8_0_100M/ext_reset_in]
    connect_bd_net [get_bd_pins rst_ps8_0_100M/peripheral_aresetn] \
        [get_bd_pins axi_smc/aresetn] \
        [get_bd_pins axi_bram_ctrl_0/s_axi_aresetn] \
        [get_bd_pins axi_intc_0/s_axi_aresetn]
    connect_bd_net [get_bd_pins rst_ps8_0_100M/peripheral_reset] \
        [get_bd_pins pattern_gen_0/i_rst] \
        [get_bd_pins cca_top_0/rst]

    # ---- data path ----------------------------------------------------------
    connect_bd_net [get_bd_ports button] [get_bd_pins sync_debouncer_0/button]
    connect_bd_net [get_bd_pins sync_debouncer_0/sync_deb_signal] [get_bd_pins pattern_gen_0/i_enable]
    foreach sig {tdata tvalid tuser tlast} {
        connect_bd_net [get_bd_pins pattern_gen_0/m_axis_$sig] [get_bd_pins cca_top_0/i_$sig]
    }

    # cca_top drives BRAM port B pin by pin (byte addresses, 32-bit words)
    foreach {src dst} {o_bram_clk clkb  o_bram_en enb  o_bram_we web
                       o_bram_addr addrb  o_bram_wdata dinb} {
        connect_bd_net [get_bd_pins cca_top_0/$src] [get_bd_pins axi_bram_ctrl_0_bram/$dst]
    }

    # ---- interrupt ----------------------------------------------------------
    connect_bd_net [get_bd_pins cca_top_0/o_interrupt] [get_bd_pins axi_intc_0/intr]
    connect_bd_net [get_bd_pins axi_intc_0/irq] [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]

    # ---- address map (docs/pl-ps_interface_spec.md, src/sw) -------------------
    set data [get_bd_addr_spaces zynq_ultra_ps_e_0/Data]
    assign_bd_address -target_address_space $data -offset 0xA0000000 -range 64K \
        [get_bd_addr_segs axi_bram_ctrl_0/S_AXI/Mem0] -force
    assign_bd_address -target_address_space $data -offset 0xA0010000 -range 64K \
        [get_bd_addr_segs axi_intc_0/S_AXI/Reg] -force

    validate_bd_design

    # The interrupt input must be rising-edge (bit 0 of C_KIND_OF_INTR = 1):
    # docs/pl-ps_interface_spec.md and src/sw/interrupt.c assume it.
    set kind [get_property CONFIG.C_KIND_OF_INTR $intc]
    if {([expr {$kind}] & 1) == 0} {
        error "axi_intc_0 input 0 is level-sensitive (C_KIND_OF_INTR = $kind),\
expected edge. Set it in the axi_intc GUI (Interrupts type: Manual, Edge)\
and update the C_KIND_OF_INTR lines in scripts/bd/pl_ps.tcl."
    }
    puts "axi_intc_0 C_KIND_OF_INTR = $kind (input 0 edge-sensitive)"

    save_bd_design
}
