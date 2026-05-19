set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../..]]
set build_dir [file join $repo_root build vivado]

file mkdir $build_dir

create_project donder_controller $build_dir -part xc7z020clg400-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set pynq_z2_board_part "tul.com.tw:pynq-z2:part0:1.0"
if {[llength [get_board_parts -quiet $pynq_z2_board_part]] > 0} {
  set_property board_part $pynq_z2_board_part [current_project]
  puts "Using board part $pynq_z2_board_part"
} else {
  error "Required board part $pynq_z2_board_part not found. Install the PYNQ-Z2 board files before building."
}

add_files -fileset sources_1 [file join $repo_root hw rtl eth_frame_core.v]
add_files -fileset constrs_1 [file join $repo_root hw constraints pynq_z2.xdc]
update_compile_order -fileset sources_1

source [file join $script_dir ps_bd.tcl]

generate_target all [get_files donder_system.bd]
make_wrapper -files [get_files donder_system.bd] -top
add_files -norecurse [file join $build_dir donder_controller.gen sources_1 bd donder_system hdl donder_system_wrapper.v]
set_property top donder_system_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  error "synth_1 failed"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  error "impl_1 failed"
}

open_run impl_1
write_hw_platform -fixed -include_bit -force [file join $build_dir donder_controller.xsa]

puts "Bitstream and XSA created at $build_dir"
