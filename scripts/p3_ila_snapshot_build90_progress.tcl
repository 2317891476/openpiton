# p3_ila_snapshot_build90_progress.tcl -- Take repeated immediate snapshots of
# the clean-RTL Build 90 commit/CSR diagnostic ILA.

set hw_server_url "100.93.77.36"
set hw_server_port "3121"
set xvc_host "202.197.4.99"
set xvc_port "2540"
set default_ltx \
    {Z:/home/illya/openpiton/huaprop3_build90_time_csr_rtl/debug_build/p3_top_build90_time_csr_rtl.ltx}
set default_output_dir \
    {Z:/home/illya/openpiton/huaprop3_build90_time_csr_rtl/progress_snapshots}

if {[llength $argv] > 2} {
    error "expected optional Build 90 LTX and output directory"
}
set ltx_file $default_ltx
set output_dir $default_output_dir
if {[llength $argv] >= 1} {
    set ltx_file [file normalize [lindex $argv 0]]
}
if {[llength $argv] == 2} {
    set output_dir [file normalize [lindex $argv 1]]
}
if {![file exists $ltx_file] || [file size $ltx_file] == 0} {
    error "Build 90 LTX is missing or empty: $ltx_file"
}
file mkdir $output_dir

proc p3_require_one {kind objects name} {
    if {[llength $objects] != 1} {
        error "required exact $kind matched [llength $objects] objects: $name"
    }
    return [lindex $objects 0]
}

open_hw_manager
connect_hw_server -url "${hw_server_url}:${hw_server_port}" -allow_non_jtag
open_hw_target -xvc_url "${xvc_host}:${xvc_port}"
set versal_dev ""
foreach dev [get_hw_devices -quiet] {
    if {[string match "*xcvp*" [string tolower [get_property PART $dev]]]} {
        set versal_dev $dev
    }
}
if {$versal_dev eq ""} {
    error "no VP1902 device found"
}
current_hw_device $versal_dev
set_property PROBES.FILE $ltx_file [current_hw_device]
refresh_hw_device [current_hw_device]

set ila [p3_require_one hw_ila [get_hw_ilas -quiet -filter \
    {CELL_NAME == u_ila_build90}] u_ila_build90]
set_property CONTROL.DATA_DEPTH 4096 $ila
set_property CONTROL.TRIGGER_POSITION 2048 $ila

for {set snapshot 0} {$snapshot < 3} {incr snapshot} {
    if {$snapshot > 0} {
        after 15000
    }
    run_hw_ila $ila -trigger_now
    wait_on_hw_ila $ila
    set data [upload_hw_ila_data $ila]
    set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set csv_file \
        "${output_dir}/ila_snapshot_build90_${timestamp}_${snapshot}.csv"
    write_hw_ila_data -force -csv_file $csv_file $data
    if {![file exists $csv_file] || [file size $csv_file] == 0} {
        error "Build 90 progress CSV is missing or empty: $csv_file"
    }
    puts "Build 90 progress snapshot: $csv_file"
}

close_hw_target
disconnect_hw_server
close_hw_manager
puts "SUCCESS: Build 90 repeated progress snapshots complete"
