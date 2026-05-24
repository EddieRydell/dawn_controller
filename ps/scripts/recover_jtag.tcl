set hw_server_url "TCP:localhost:3121"

proc try_targets {filter} {
    if {[catch {targets -set -filter $filter} err]} {
        puts "TARGET_SELECT_FAILED $filter $err"
        return 0
    }
    return 1
}

puts "CONNECT $hw_server_url"
connect -url $hw_server_url
puts "TARGETS_BEFORE"
puts [targets]

if {[try_targets {name =~ "APU"}]} {
    catch {rst -system}
    after 2000
}

if {[try_targets {name =~ "*Cortex-A9*#0*"}]} {
    catch {stop}
    catch {rst -processor}
    after 2000
}

if {[try_targets {name =~ "DAP*"}]} {
    catch {rst -system}
    after 2000
}

puts "TARGETS_AFTER"
puts [targets]
disconnect
