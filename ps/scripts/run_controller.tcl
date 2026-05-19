set repo_root [file normalize [file join [file dirname [info script]] .. ..]]
set hw_server_url "TCP:localhost:3121"
set bit_file [file join $repo_root build vivado donder_controller.runs impl_1 donder_system_wrapper.bit]
set vitis_workspace [file join $repo_root build vitis]
set pl_control_base 0x43C00000
set pl_frame_base 0x43C10000

set slcr_unlock 0xF8000008
set slcr_lock 0xF8000004
set slcr_unlock_key 0x0000DF0D
set slcr_lock_key 0x0000767B
set fpga_rst_ctrl 0xF8000240
set lvl_shftr_en 0xF8000900

proc newest {pattern} {
    set candidates [glob -nocomplain $pattern]
    if {[llength $candidates] == 0} {
        error "No file found: $pattern"
    }
    set pairs {}
    foreach path $candidates {
        lappend pairs [list [file mtime $path] $path]
    }
    set sorted [lsort -integer -decreasing -index 0 $pairs]
    return [lindex [lindex $sorted 0] 1]
}

proc mrd32 {addr} {
    set value [mrd -force -value $addr 1]
    return [expr {[lindex $value 0]}]
}

proc mwr32 {addr value} {
    mwr -force $addr $value
}

proc mask_write32 {addr mask value} {
    set current [mrd32 $addr]
    set updated [expr {($current & ~$mask) | ($value & $mask)}]
    mwr32 $addr $updated
}

proc print_reg {base offset name} {
    set value [mrd32 [expr {$base + $offset}]]
    puts [format "%s=0x%08x" $name $value]
    return $value
}

proc print_frame_word {base bank_words bank word name} {
    set byte_offset [expr {(($bank * $bank_words) + $word) * 4}]
    set value [mrd32 [expr {$base + $byte_offset}]]
    puts [format "%s=0x%08x" $name $value]
    return $value
}

proc select_or_error {filter} {
    targets -set -filter $filter
}

proc post_config_pl {} {
    global slcr_unlock slcr_lock slcr_unlock_key slcr_lock_key fpga_rst_ctrl lvl_shftr_en
    mwr32 $slcr_unlock $slcr_unlock_key
    mask_write32 $lvl_shftr_en 0x0000000F 0x0000000F
    mwr32 $fpga_rst_ctrl 0x00000000
    mwr32 $slcr_lock $slcr_lock_key
}

if {![file exists $bit_file]} {
    error "Missing bitstream: $bit_file"
}

set app [newest [file join $vitis_workspace * donder_controller build donder_controller.elf]]
set fsbl [newest [file join $vitis_workspace * donder_platform zynq_fsbl build fsbl.elf]]

puts "CONNECT $hw_server_url"
connect -url $hw_server_url

puts "TARGETS_START"
puts [targets]

select_or_error {name =~ "*Cortex-A9*#0*"}
catch {stop}
puts "RESET_PROCESSOR"
rst -processor
catch {stop}

puts "DOWNLOAD_FSBL $fsbl"
dow -force $fsbl
con
after 8000
catch {stop}

puts "PROGRAM_FPGA $bit_file"
select_or_error {name =~ "xc7z020"}
fpga -file $bit_file

puts "POST_CONFIG_PL"
select_or_error {name =~ "APU"}
configparams force-mem-accesses 1
post_config_pl

puts "PL_PROBE"
set core_id [print_reg $pl_control_base 0x000 CORE_ID]
print_reg $pl_control_base 0x004 VERSION
print_reg $pl_control_base 0x00c STATUS
print_reg $pl_control_base 0x010 PIN_OUT
print_reg $pl_control_base 0x018 FRAME_CAPACITY
print_reg $pl_control_base 0x038 FRAME_BANK_WORDS
print_reg $pl_control_base 0x03c ACTIVE_BANK
print_reg $pl_control_base 0x040 WRITE_BANK
print_reg $pl_frame_base 0x000 FRAME_WORD0
if {$core_id != 0x4546504c} {
    error [format "Unexpected PL core ID: 0x%08x" $core_id]
}

puts "DOWNLOAD_APP $app"
select_or_error {name =~ "*Cortex-A9*#0*"}
catch {stop}
dow -force $app
con

after 5000
catch {stop}
puts "PL_AFTER_APP"
print_reg $pl_control_base 0x010 PIN_OUT
print_reg $pl_control_base 0x024 FRAME_COUNT
print_reg $pl_control_base 0x028 COMMITTED_WORDS
print_reg $pl_control_base 0x02c FIRST_FRAME_WORD
print_reg $pl_control_base 0x030 LAST_FRAME_WORD
print_reg $pl_control_base 0x034 ERROR_COUNT
set bank_words [print_reg $pl_control_base 0x038 FRAME_BANK_WORDS]
set active_bank [print_reg $pl_control_base 0x03c ACTIVE_BANK]
print_reg $pl_control_base 0x040 WRITE_BANK
print_reg $pl_control_base 0x044 FRAME_SEQUENCE
print_reg $pl_control_base 0x00c STATUS
print_frame_word $pl_frame_base $bank_words $active_bank 0 ACTIVE_FRAME_WORD0

disconnect
