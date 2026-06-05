# p3_program_pdi.tcl
# Program HuaPro P3 (Versal VP1902) with a caller-specified PDI.
# Usage:
#   vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs <file.pdi>
#   vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs <file.pdi> <file.ltx>

set hw_server_url "100.93.77.36"
set hw_server_port "3121"
set xvc_host "202.197.4.99"
set xvc_port "2540"

if {[llength $argv] < 1 || [llength $argv] > 2} {
    puts "ERROR: expected a PDI path and optional LTX path"
    puts "Usage: vivado -mode batch -source scripts/p3_program_pdi.tcl -tclargs <file.pdi> ?<file.ltx>?"
    exit 1
}

set pdi_file [file normalize [lindex $argv 0]]
set ltx_file ""
if {[llength $argv] == 2} {
    set ltx_file [file normalize [lindex $argv 1]]
}

puts "=========================================="
puts " P3 Program FPGA"
puts " hw_server: ${hw_server_url}:${hw_server_port}"
puts " XVC target: ${xvc_host}:${xvc_port}"
puts " PDI: ${pdi_file}"
if {$ltx_file ne ""} {
    puts " LTX: ${ltx_file}"
}
puts "=========================================="

if {![file exists $pdi_file]} {
    puts "ERROR: PDI file not found: ${pdi_file}"
    exit 1
}
if {$ltx_file ne "" && ![file exists $ltx_file]} {
    puts "ERROR: LTX file not found: ${ltx_file}"
    exit 1
}

open_hw_manager
connect_hw_server -url "${hw_server_url}:${hw_server_port}" -allow_non_jtag

puts "Adding XVC target: ${xvc_host}:${xvc_port}..."
set xvc_target [open_hw_target -xvc_url "${xvc_host}:${xvc_port}"]
puts "XVC target opened: ${xvc_target}"

set devices [get_hw_devices -quiet]
puts "Devices found: ${devices}"
if {[llength $devices] == 0} {
    puts "ERROR: No devices found on XVC target"
    close_hw_target
    disconnect_hw_server
    close_hw_manager
    exit 1
}

set versal_dev ""
foreach dev $devices {
    set part [get_property PART $dev]
    puts "  Device: ${dev}  Part: ${part}"
    if {[string match "*xcvp*" [string tolower $part]] || [string match "*versal*" [string tolower $part]]} {
        set versal_dev $dev
    }
}
if {$versal_dev eq ""} {
    set versal_dev [lindex $devices 0]
    puts "WARNING: No explicit Versal device found, using first device: ${versal_dev}"
}

current_hw_device $versal_dev
set_property PROGRAM.FILE $pdi_file [current_hw_device]
if {$ltx_file ne ""} {
    set_property PROBES.FILE $ltx_file [current_hw_device]
}

puts "Programming device: ${versal_dev}"
program_hw_devices [current_hw_device]

set done_bit ""
catch {set done_bit [get_property REGISTER.IR_STATUS.DONE [current_hw_device]]}
if {$done_bit ne ""} {
    puts "DONE bit: ${done_bit}"
}

if {$ltx_file ne ""} {
    puts "Refreshing debug probes..."
    refresh_hw_device [current_hw_device]
    set ilas [get_hw_ilas -quiet]
    puts "ILAs: ${ilas}"
    if {[llength $ilas] == 0} {
        puts "ERROR: No ILA core found after loading LTX"
        close_hw_target
        disconnect_hw_server
        close_hw_manager
        exit 1
    }
}

puts "=========================================="
puts " SUCCESS: Device programmed"
puts "=========================================="

close_hw_target
disconnect_hw_server
close_hw_manager
