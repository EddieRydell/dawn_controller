set hw_server_url "TCP:localhost:3121"
set pl_control_base 0x43C00000
set pl_frame_base 0x43C80000

proc mrd32 {addr} {
    set value [mrd -force -value $addr 1]
    return [expr {[lindex $value 0]}]
}

proc print_reg {base offset name} {
    set value [mrd32 [expr {$base + $offset}]]
    puts [format "%s=0x%08x" $name $value]
    return $value
}

proc select_or_error {filter} {
    targets -set -filter $filter
}

puts "CONNECT $hw_server_url"
connect -url $hw_server_url
select_or_error {name =~ "APU"}
configparams force-mem-accesses 1

puts "PL_SNAPSHOT"
print_reg $pl_control_base 0x000 CORE_ID
print_reg $pl_control_base 0x004 VERSION
print_reg $pl_control_base 0x00c STATUS
print_reg $pl_control_base 0x024 FRAME_COUNT
print_reg $pl_control_base 0x028 COMMITTED_WORDS
print_reg $pl_control_base 0x034 ERROR_COUNT
print_reg $pl_control_base 0x038 FRAME_BANK_WORDS
print_reg $pl_control_base 0x03c ACTIVE_BANK
print_reg $pl_control_base 0x040 WRITE_BANK
print_reg $pl_control_base 0x044 FRAME_SEQUENCE
print_reg $pl_control_base 0x04c CONSUMER_STATUS
print_reg $pl_control_base 0x050 CONSUMER_SEQUENCE
print_reg $pl_control_base 0x054 CONSUMER_FRAME_COUNT
print_reg $pl_control_base 0x058 CONSUMER_ERROR_COUNT
print_reg $pl_control_base 0x060 WS281X_OUTPUT_COUNT
print_reg $pl_control_base 0x064 WS281X_PIXELS_PER_OUTPUT
print_reg $pl_control_base 0x06c WRITE_BANK_VALID
print_reg $pl_control_base 0x070 BUSY_BANK
print_reg $pl_control_base 0x074 FRAME_DROPPED
print_reg $pl_control_base 0x078 FRAME_REJECTED
print_reg $pl_control_base 0x080 ACTIVE_OUTPUT_COUNT
print_reg $pl_control_base 0x084 STRAND_PIXEL_COUNT0
print_reg $pl_control_base 0x088 STRAND_PIXEL_COUNT1
print_reg $pl_control_base 0x08c STRAND_PIXEL_COUNT2
print_reg $pl_control_base 0x090 STRAND_PIXEL_COUNT3
print_reg $pl_control_base 0x0fc CONFIG_STATUS
print_reg $pl_control_base 0x100 STRAND_LENGTH_CLAMPED0
print_reg $pl_control_base 0x104 OUTPUT_INVERT_MASK0

disconnect
