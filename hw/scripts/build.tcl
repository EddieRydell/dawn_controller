set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../..]]
set build_dir [file join $repo_root build vivado]

file mkdir $build_dir

proc fail_on_hand_rtl_warnings {repo_root} {
  set rtl_root [string tolower [string map {\\ /} [file normalize [file join $repo_root hw rtl]]]]

  set failures {}
  foreach run [get_runs -quiet *synth*] {
    set run_dir [get_property DIRECTORY $run]
    set log_path [file join $run_dir runme.log]
    if {![file exists $log_path]} {
      continue
    }

    set fh [open $log_path r]
    set line_number 0
    while {[gets $fh line] >= 0} {
      incr line_number
      set normalized_line [string tolower [string map {\\ /} $line]]
      if {[string first "warning:" $normalized_line] < 0
          || [string first $rtl_root $normalized_line] < 0} {
        continue
      }

      lappend failures "$run:$line_number:$line"
    }
    close $fh
  }

  if {[llength $failures] > 0} {
    puts "Hand-authored RTL warnings are treated as build errors:"
    foreach failure $failures {
      puts "  $failure"
    }
    error "Vivado emitted warnings for hand-authored RTL"
  }
}

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

set rtl_files [concat \
  [glob -nocomplain [file join $repo_root hw rtl *.sv]] \
  [glob -nocomplain [file join $repo_root hw rtl *.v]] \
]
if {[llength $rtl_files] > 0} {
  add_files -fileset sources_1 $rtl_files
}

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
fail_on_hand_rtl_warnings $repo_root

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  error "impl_1 failed"
}

open_run impl_1
write_hw_platform -fixed -include_bit -force [file join $build_dir donder_controller.xsa]

puts "Project, bitstream, and XSA created at $build_dir"
