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

create_bd_cell -type module -reference ws281x_controller_core ws281x_controller_core_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins ws281x_controller_core_0/aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins ws281x_controller_core_0/aresetn]

create_bd_cell -type module -reference axil_frame_ram axil_frame_ram_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axil_frame_ram_0/aclk]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins axil_frame_ram_0/aresetn]

create_bd_port -dir O -from 3 -to 0 ws281x_data
connect_bd_net [get_bd_pins ws281x_controller_core_0/ws281x_data] [get_bd_ports ws281x_data]

connect_bd_net [get_bd_pins ws281x_controller_core_0/m_frame_araddr] [get_bd_pins axil_frame_ram_0/rd_araddr]
connect_bd_net [get_bd_pins ws281x_controller_core_0/m_frame_arvalid] [get_bd_pins axil_frame_ram_0/rd_arvalid]
connect_bd_net [get_bd_pins ws281x_controller_core_0/m_frame_arready] [get_bd_pins axil_frame_ram_0/rd_arready]
connect_bd_net [get_bd_pins ws281x_controller_core_0/m_frame_rdata] [get_bd_pins axil_frame_ram_0/rd_rdata]
connect_bd_net [get_bd_pins ws281x_controller_core_0/m_frame_rresp] [get_bd_pins axil_frame_ram_0/rd_rresp]
connect_bd_net [get_bd_pins ws281x_controller_core_0/m_frame_rvalid] [get_bd_pins axil_frame_ram_0/rd_rvalid]
connect_bd_net [get_bd_pins ws281x_controller_core_0/m_frame_rready] [get_bd_pins axil_frame_ram_0/rd_rready]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
  -config {Master "/processing_system7_0/M_AXI_GP0" Slave "/ws281x_controller_core_0/S_AXI" Clk "/processing_system7_0/FCLK_CLK0"} \
  [get_bd_intf_pins ws281x_controller_core_0/S_AXI]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
  -config {Master "/processing_system7_0/M_AXI_GP0" Slave "/axil_frame_ram_0/S_AXI" Clk "/processing_system7_0/FCLK_CLK0"} \
  [get_bd_intf_pins axil_frame_ram_0/S_AXI]

assign_bd_address

set control_addr_seg [get_bd_addr_segs -quiet {processing_system7_0/Data/*ws281x_controller_core_0*}]
if {[llength $control_addr_seg] == 0} {
  error "Could not find assigned address segment for ws281x_controller_core_0"
}
set_property range 4K $control_addr_seg
set_property offset 0x43C00000 $control_addr_seg

set frame_addr_seg [get_bd_addr_segs -quiet {processing_system7_0/Data/*axil_frame_ram_0*}]
if {[llength $frame_addr_seg] == 0} {
  error "Could not find assigned address segment for axil_frame_ram_0"
}
set_property range 32K $frame_addr_seg
set_property offset 0x43C10000 $frame_addr_seg

validate_bd_design
save_bd_design
