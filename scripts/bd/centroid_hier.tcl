# =============================================================================
# centroid_hier.tcl  --  the centroiding hierarchy (owner: Adam)
#
# create_centroid_hier <parent> <name> <cca_num_labels> <with_conv>
#
#   with_conv 1 (hdmi):    s_axis_* (16 bit, 2 px/beat) -> pix_2to1 -> cca_top -> BRAM port B
#   with_conv 0 (pattern): s_axis_* (8 bit, 1 px/clk)              -> cca_top -> BRAM port B
#   S_AXI -> SmartConnect -> AXI BRAM ctrl (BRAM port A)
#                         -> axi_intc
#   cca_top.o_interrupt -> axi_intc (rising edge) -> irq
#
# Pins: clk, peripheral_reset (active high, cca_top), peripheral_aresetn
# (active low, AXI), S_AXI, s_axis_{tdata,tvalid,tuser,tlast,tready}, irq.
# Addresses are assigned by the caller (scripts/bd/pl_ps.tcl).
# Call check_centroid_hier after validate_bd_design.
# =============================================================================

proc create_centroid_hier {parent name cca_num_labels with_conv} {
    set old [current_bd_instance .]
    current_bd_instance $parent
    set hier [create_bd_cell -type hier $name]
    current_bd_instance $hier

    # ---- hierarchy pins -----------------------------------------------------
    create_bd_pin -dir I -type clk clk
    create_bd_pin -dir I -type rst peripheral_reset
    create_bd_pin -dir I -type rst peripheral_aresetn
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI
    create_bd_pin -dir I -from [expr {$with_conv ? 15 : 7}] -to 0 s_axis_tdata
    create_bd_pin -dir I s_axis_tvalid
    create_bd_pin -dir I s_axis_tuser
    create_bd_pin -dir I s_axis_tlast
    create_bd_pin -dir O s_axis_tready
    create_bd_pin -dir O -type intr irq

    # ---- cells --------------------------------------------------------------
    set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc]
    set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2] $smc

    set bram_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0]
    set_property CONFIG.SINGLE_PORT_BRAM 1 $bram_ctrl

    # Port A: AXI BRAM controller (PS reads). Port B: cca_top (PL writes).
    set bram [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 axi_bram_ctrl_0_bram]
    set_property CONFIG.Memory_Type True_Dual_Port_RAM $bram

    # Edge-sensitive input: o_interrupt is a 1-cycle pulse. A module-reference
    # pin propagates as level, so set it explicitly (checked after validation).
    set intc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 axi_intc_0]
    set_property -dict [list \
        CONFIG.C_IRQ_CONNECTION 1 \
        CONFIG.C_IRQ_IS_LEVEL   1 \
        CONFIG.C_KIND_OF_INTR.VALUE_SRC USER \
        CONFIG.C_KIND_OF_INTR   0xFFFFFFFF \
        CONFIG.C_KIND_OF_EDGE.VALUE_SRC USER \
        CONFIG.C_KIND_OF_EDGE   0xFFFFFFFF] $intc

    # A module reference's top file can't be SystemVerilog: Verilog shell.
    set cca [create_bd_cell -type module -reference cca_top_bd cca_top_0]
    set_property CONFIG.NUM_LABELS $cca_num_labels $cca
    catch {set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_pins cca_top_0/rst]}
    catch {set_property CONFIG.SENSITIVITY EDGE_RISING [get_bd_pins cca_top_0/o_interrupt]}

    if {$with_conv} {
        create_bd_cell -type module -reference pix_2to1_bd pix_2to1_0
    }

    # ---- AXI ----------------------------------------------------------------
    connect_bd_intf_net [get_bd_intf_pins S_AXI] [get_bd_intf_pins axi_smc/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins axi_bram_ctrl_0/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M01_AXI] [get_bd_intf_pins axi_intc_0/s_axi]
    connect_bd_intf_net [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTA] [get_bd_intf_pins axi_bram_ctrl_0_bram/BRAM_PORTA]

    # ---- clock and resets ---------------------------------------------------
    set clk_pins [list \
        [get_bd_pins axi_smc/aclk] \
        [get_bd_pins axi_bram_ctrl_0/s_axi_aclk] \
        [get_bd_pins axi_intc_0/s_axi_aclk] \
        [get_bd_pins cca_top_0/clk]]
    set rstn_pins [list \
        [get_bd_pins axi_smc/aresetn] \
        [get_bd_pins axi_bram_ctrl_0/s_axi_aresetn] \
        [get_bd_pins axi_intc_0/s_axi_aresetn]]
    if {$with_conv} {
        lappend clk_pins  [get_bd_pins pix_2to1_0/aclk]
        lappend rstn_pins [get_bd_pins pix_2to1_0/aresetn]
    }
    connect_bd_net [get_bd_pins clk] {*}$clk_pins
    connect_bd_net [get_bd_pins peripheral_aresetn] {*}$rstn_pins
    connect_bd_net [get_bd_pins peripheral_reset] [get_bd_pins cca_top_0/rst]

    # ---- pixel stream in ----------------------------------------------------
    if {$with_conv} {
        # hierarchy -> pix_2to1 -> cca_top
        foreach sig {tdata tvalid tuser tlast} {
            connect_bd_net [get_bd_pins s_axis_$sig] [get_bd_pins pix_2to1_0/s_axis_$sig]
        }
        connect_bd_net [get_bd_pins pix_2to1_0/s_axis_tready] [get_bd_pins s_axis_tready]

        foreach sig {tdata tvalid tuser tlast} {
            connect_bd_net [get_bd_pins pix_2to1_0/m_axis_$sig] [get_bd_pins cca_top_0/i_$sig]
        }
        connect_bd_net [get_bd_pins cca_top_0/o_trdy] [get_bd_pins pix_2to1_0/m_axis_tready]
    } else {
        # hierarchy -> cca_top
        foreach sig {tdata tvalid tuser tlast} {
            connect_bd_net [get_bd_pins s_axis_$sig] [get_bd_pins cca_top_0/i_$sig]
        }
        connect_bd_net [get_bd_pins cca_top_0/o_trdy] [get_bd_pins s_axis_tready]
    }


    # cca_top drives BRAM port B pin by pin (byte addresses, 32-bit words)
    foreach {src dst} {o_bram_clk clkb  o_bram_en enb  o_bram_we web
                       o_bram_addr addrb  o_bram_wdata dinb} {
        connect_bd_net [get_bd_pins cca_top_0/$src] [get_bd_pins axi_bram_ctrl_0_bram/$dst]
    }

    # ---- interrupt ----------------------------------------------------------
    connect_bd_net [get_bd_pins cca_top_0/o_interrupt] [get_bd_pins axi_intc_0/intr]
    connect_bd_net [get_bd_pins axi_intc_0/irq] [get_bd_pins irq]

    current_bd_instance $old
    return $hier
}

# Map BRAM and axi_intc at the addresses src/sw expects.
proc assign_centroid_addresses {hier_name} {
    set data [get_bd_addr_spaces zynq_ultra_ps_e_0/Data]
    assign_bd_address -target_address_space $data -offset 0xA0000000 -range 64K \
        [get_bd_addr_segs $hier_name/axi_bram_ctrl_0/S_AXI/Mem0] -force
    assign_bd_address -target_address_space $data -offset 0xA0010000 -range 64K \
        [get_bd_addr_segs $hier_name/axi_intc_0/S_AXI/Reg] -force
}

# The interrupt input must be rising-edge (bit 0 of C_KIND_OF_INTR = 1):
# docs/pl-ps_interface_spec.md and src/sw/interrupt.c assume it.
proc check_centroid_hier {hier_name} {
    set kind [get_property CONFIG.C_KIND_OF_INTR [get_bd_cells $hier_name/axi_intc_0]]
    if {([expr {$kind}] & 1) == 0} {
        error "$hier_name/axi_intc_0 input 0 is level-sensitive (C_KIND_OF_INTR = $kind), expected edge"
    }
    puts "$hier_name/axi_intc_0 C_KIND_OF_INTR = $kind (input 0 edge-sensitive)"
}
