create_bd_design "donder_system"

create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 processing_system7_0

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
  [get_bd_cells processing_system7_0]

set_property -dict [list \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.0} \
  CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
  CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
] [get_bd_cells processing_system7_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset proc_sys_reset_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins proc_sys_reset_0/ext_reset_in]

create_bd_cell -type module -reference eth_frame_core eth_frame_core_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins eth_frame_core_0/aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins eth_frame_core_0/aresetn]

create_bd_port -dir O -from 3 -to 0 pl_data
connect_bd_net [get_bd_pins eth_frame_core_0/pl_data] [get_bd_ports pl_data]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
  -config {Master "/processing_system7_0/M_AXI_GP0" Slave "/eth_frame_core_0/S_AXI" Clk "/processing_system7_0/FCLK_CLK0"} \
  [get_bd_intf_pins eth_frame_core_0/S_AXI]

assign_bd_address
set pl_addr_seg [get_bd_addr_segs -quiet {processing_system7_0/Data/*eth_frame_core_0*}]
if {[llength $pl_addr_seg] == 0} {
  error "Could not find assigned address segment for eth_frame_core_0"
}
set_property range 4K $pl_addr_seg
set_property offset 0x43C00000 $pl_addr_seg

validate_bd_design
save_bd_design
