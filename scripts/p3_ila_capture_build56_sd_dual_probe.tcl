# p3_ila_capture_build56_sd_dual_probe.tcl -- Capture Build 56 SD probe auto-run result.
# Usage:
#   vivado -mode batch -source scripts/p3_ila_capture_build56_sd_dual_probe.tcl

set hw_server_url "100.93.77.36"
set hw_server_port "3121"
set xvc_host "202.197.4.99"
set xvc_port "2540"
set project_dir [file normalize "[file dirname [info script]]/../huaprop3_build56_sd_dual_probe"]
set ltx_file "${project_dir}/debug_build/p3_top_build56_sd_dual_probe.ltx"
set output_dir "${project_dir}/debug_build"

proc p3_sanitize_filename {name} {
    regsub -all {[^A-Za-z0-9_.-]} $name "_" clean
    return $clean
}

proc p3_capture_ila {ila output_dir} {
    set cell_name [get_property CELL_NAME $ila]
    set clean_name [p3_sanitize_filename $cell_name]
    set csv_file "${output_dir}/ila_capture_build56_auto_${clean_name}.csv"
    run_hw_ila $ila -trigger_now
    wait_on_hw_ila $ila
    set ila_data [upload_hw_ila_data $ila]
    write_hw_ila_data -force -csv_file $csv_file $ila_data
    puts "  CSV written to: $csv_file"
}

puts "=========================================="
puts " P3 Build 56 SD dual probe capture"
puts " hw_server: ${hw_server_url}:${hw_server_port}"
puts " XVC target: ${xvc_host}:${xvc_port}"
puts " LTX: ${ltx_file}"
puts "=========================================="

if {![file exists $ltx_file]} {
    puts "ERROR: LTX file not found: $ltx_file"
    exit 1
}

open_hw_manager
connect_hw_server -url "${hw_server_url}:${hw_server_port}" -allow_non_jtag
open_hw_target -xvc_url "${xvc_host}:${xvc_port}"

set devices [get_hw_devices -quiet]
if {[llength $devices] == 0} {
    puts "ERROR: No devices found on XVC target"
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
}

current_hw_device $versal_dev
set_property PROBES.FILE $ltx_file [current_hw_device]
refresh_hw_device [current_hw_device]

set ilas [get_hw_ilas -quiet]
puts "ILAs: $ilas"
if {[llength $ilas] != 1} {
    puts "ERROR: expected exactly one ILA core, found [llength $ilas]"
    exit 1
}

set ila [lindex $ilas 0]

foreach prop {NAME CORE_UUID CELL_NAME CONTROL.DATA_DEPTH CONTROL.TRIGGER_POSITION} {
    if {![catch {get_property $prop $ila} v]} {
        puts "  ILA $prop=$v"
    }
}
foreach p [get_hw_probes -of_objects $ila -quiet] {
    set name [get_property NAME $p]
    set width ""
    catch {set width [get_property WIDTH $p]}
    puts "  ILA Probe: ${name} width=${width}"
}

catch {set_property CONTROL.DATA_DEPTH 4096 $ila}
catch {set_property CONTROL.TRIGGER_POSITION 2048 $ila}

puts "Waiting for Build 56 RTL auto-run sequence to complete..."
after 16000
p3_capture_ila $ila $output_dir

close_hw_target
disconnect_hw_server
close_hw_manager

puts "=========================================="
puts " P3 Build 56 SD dual probe capture complete"
puts "=========================================="
