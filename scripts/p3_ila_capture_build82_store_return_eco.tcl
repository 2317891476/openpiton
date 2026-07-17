# p3_ila_capture_build82_store_return_eco.tcl -- Arm all four ILAs on the
# common tx_stat_q[1].vld rising edge while the bootrom is still copying SD.

set hw_server_url "100.93.77.36"
set hw_server_port "3121"
set xvc_host "202.197.4.99"
set xvc_port "2540"
set default_ltx {D:/p3b82_store_return_eco/p3_top_build82_store_return_eco.ltx}
set default_output_dir {D:/p3b82_store_return_eco/captures}

if {[llength $argv] > 2} {
    error "expected optional Build 82 LTX and output directory"
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
    error "Build 82 LTX is missing or empty: $ltx_file"
}
file mkdir $output_dir
set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]

proc p3_require_one {kind objects name} {
    if {[llength $objects] != 1} {
        error "required exact $kind matched [llength $objects] objects: $name"
    }
    return [lindex $objects 0]
}

proc p3_probe_with_token {ila token} {
    set matches [list]
    foreach probe [get_hw_probes -quiet -of_objects $ila] {
        if {[string first $token [get_property NAME $probe]] >= 0} {
            lappend matches $probe
        }
    }
    return [p3_require_one hw_probe $matches $token]
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

set expected_cells [list \
    {u_bd/openpiton_top_i/axis_ila_0} \
    {u_bd/openpiton_top_i/axis_ila_1} \
    {u_bd/openpiton_top_i/axis_ila_2} \
    {u_bd/openpiton_top_i/axis_ila_3}]
set ila_by_cell [dict create]
foreach ila [get_hw_ilas -quiet] {
    dict set ila_by_cell [get_property CELL_NAME $ila] $ila
}

set trigger_tokens [dict create \
    {u_bd/openpiton_top_i/axis_ila_0} {p3_build81_control_25_1} \
    {u_bd/openpiton_top_i/axis_ila_1} {p3_build81_control_25_2} \
    {u_bd/openpiton_top_i/axis_ila_2} {p3_build81_control_25_6} \
    {u_bd/openpiton_top_i/axis_ila_3} {p3_build81_control_25_10}]
set armed [list]
foreach cell_name $expected_cells {
    if {![dict exists $ila_by_cell $cell_name]} {
        error "expected Build 82 ILA was not enumerated: $cell_name"
    }
    set ila [dict get $ila_by_cell $cell_name]
    set trigger [p3_probe_with_token $ila [dict get $trigger_tokens $cell_name]]
    set_property CONTROL.DATA_DEPTH 1024 $ila
    set_property CONTROL.TRIGGER_POSITION 128 $ila
    set_property TRIGGER_COMPARE_VALUE eq1'bR $trigger
    puts "Build 82 trigger: cell=$cell_name probe=[get_property NAME $trigger]"
    lappend armed $ila
}

run_hw_ila $armed
foreach ila $armed {
    wait_on_hw_ila $ila
}
foreach cell_name $expected_cells {
    set ila [dict get $ila_by_cell $cell_name]
    set data [upload_hw_ila_data $ila]
    set safe_cell [string map {/ _} $cell_name]
    set csv_file \
        "${output_dir}/ila_capture_build82_${timestamp}_${safe_cell}.csv"
    write_hw_ila_data -force -csv_file $csv_file $data
    if {![file exists $csv_file] || [file size $csv_file] == 0} {
        error "Build 82 CSV is missing or empty: $csv_file"
    }
    puts "Build 82 synchronized CSV: $csv_file"
}

close_hw_target
disconnect_hw_server
close_hw_manager
puts "SUCCESS: Build 82 synchronized store-return capture complete"
