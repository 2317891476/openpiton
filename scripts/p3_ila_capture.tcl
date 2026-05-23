# p3_ila_capture.tcl — Immediate ILA capture (trigger_now)
# Usage: vivado -mode batch -source scripts/p3_ila_capture.tcl

set hw_server_url "100.93.77.36"
set hw_server_port "3121"
set xvc_host "202.197.4.99"
set xvc_port "2540"

set project_dir [file normalize "[file dirname [info script]]/../huaprop3_openpiton"]
set ltx_file "${project_dir}/debug_build/p3_top_debug.ltx"
set output_dir "${project_dir}/debug_build"

puts "=========================================="
puts " P3 ILA Immediate Capture"
puts "=========================================="

# Connect
open_hw_manager
connect_hw_server -url "${hw_server_url}:${hw_server_port}" -allow_non_jtag
open_hw_target -xvc_url "${xvc_host}:${xvc_port}"

# Select Versal device
set devices [get_hw_devices -quiet]
set versal_dev ""
foreach dev $devices {
    set part [get_property PART $dev]
    if {[string match "*xcvp*" [string tolower $part]]} {
        set versal_dev $dev
    }
}
if {$versal_dev eq ""} {
    set versal_dev [lindex $devices 0]
}
current_hw_device $versal_dev
puts "Device: $versal_dev"

# Load ILA probes
set_property PROBES.FILE $ltx_file [current_hw_device]
refresh_hw_device [current_hw_device]

# Get ILA core
set ila [lindex [get_hw_ilas -quiet] 0]
if {$ila eq ""} {
    puts "ERROR: No ILA core found!"
    close_hw_target
    disconnect_hw_server
    close_hw_manager
    exit 1
}
puts "ILA core: $ila"

# Configure for immediate capture (trigger at end of window)
set_property CONTROL.TRIGGER_POSITION 4095 $ila
set_property CONTROL.DATA_DEPTH 4096 $ila

# Immediate trigger — capture current state
puts "Triggering ILA (immediate)..."
run_hw_ila $ila -trigger_now
wait_on_hw_ila $ila
set ila_data [upload_hw_ila_data $ila]
puts "Capture complete."

# Write waveform to file
write_hw_ila_data -force -csv_file "${output_dir}/ila_capture.csv" $ila_data
puts "CSV written to: ${output_dir}/ila_capture.csv"

# Print probe values from last sample
puts ""
puts "=========================================="
puts " Probe Summary (last sample values):"
puts "=========================================="
puts ""

set probes [get_hw_probes -of_objects $ila]
foreach p $probes {
    set name [get_property NAME $p]
    set val [get_property SAMPLE $p]
    puts "  $name = $val"
}

puts ""
puts "=========================================="
puts " Capture complete. Check ${output_dir}/ila_capture.csv"
puts "=========================================="

close_hw_target
disconnect_hw_server
close_hw_manager
