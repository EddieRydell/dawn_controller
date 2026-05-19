create_bd_design "donder_system"

create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 processing_system7_0

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
  [get_bd_cells processing_system7_0]

set_property -dict [list \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_USE_S_AXI_HP0 {1} \
  CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
  CONFIG.PCW_IRQ_F2P_INTR {1} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.0} \
  CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
  CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
] [get_bd_cells processing_system7_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset proc_sys_reset_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins proc_sys_reset_0/ext_reset_in]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]

create_bd_cell -type module -reference controller_core_bd controller_core_0
set_property -dict [list CONFIG.MAX_OUTPUTS {4}] [get_bd_cells controller_core_0]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins controller_core_0/aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins controller_core_0/aresetn]
connect_bd_net [get_bd_pins controller_core_0/irq] [get_bd_pins processing_system7_0/IRQ_F2P]

create_bd_port -dir O -from 3 -to 0 ws2811_data
connect_bd_net [get_bd_pins controller_core_0/ws2811_data] [get_bd_ports ws2811_data]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
  -config {Master "/processing_system7_0/M_AXI_GP0" Slave "/controller_core_0/S_AXI" Clk "/processing_system7_0/FCLK_CLK0"} \
  [get_bd_intf_pins controller_core_0/S_AXI]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_protocol_converter axi_protocol_converter_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_protocol_converter_0/aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins axi_protocol_converter_0/aresetn]
connect_bd_intf_net [get_bd_intf_pins controller_core_0/M_AXI] [get_bd_intf_pins axi_protocol_converter_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_protocol_converter_0/M_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

assign_bd_address
set pl_addr_seg [get_bd_addr_segs -quiet {processing_system7_0/Data/*controller_core_0*}]
if {[llength $pl_addr_seg] == 0} {
  error "Could not find assigned address segment for controller_core_0"
}
set_property range 4K $pl_addr_seg
set_property offset 0x43C00000 $pl_addr_seg

validate_bd_design
save_bd_design
