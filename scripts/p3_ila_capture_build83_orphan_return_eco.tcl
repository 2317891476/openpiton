# p3_ila_capture_build83_orphan_return_eco.tcl -- Synchronously capture the
# first return-ID FIFO entry whose selected transaction slot is invalid.

set hw_server_url "100.93.77.36"
set hw_server_port "3121"
set xvc_host "202.197.4.99"
set xvc_port "2540"
set default_ltx {D:/p3b83_orphan_return_eco/p3_top_build83_orphan_return_eco.ltx}
set default_output_dir {D:/p3b83_orphan_return_eco/captures}

if {[llength $argv] > 3} {
    error "expected optional Build 83 LTX, output directory, and orphan case"
}
set ltx_file $default_ltx
set output_dir $default_output_dir
set orphan_case rp0_tid0
if {[llength $argv] >= 1} {
    set ltx_file [file normalize [lindex $argv 0]]
}
if {[llength $argv] >= 2} {
    set output_dir [file normalize [lindex $argv 1]]
}
if {[llength $argv] == 3} {
    set orphan_case [lindex $argv 2]
}
if {![file exists $ltx_file] || [file size $ltx_file] == 0} {
    error "Build 83 LTX is missing or empty: $ltx_file"
}
if {$orphan_case ni {rp0_tid0 rp0_tid1 rp1_tid0 rp1_tid1}} {
    error "unsupported orphan case: $orphan_case"
}
file mkdir $output_dir
set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]

proc p3_require_one {kind objects name} {
    if {[llength $objects] != 1} {
        error "required exact $kind matched [llength $objects] objects: $name"
    }
    return [lindex $objects 0]
}

proc p3_probe_exact {ila name} {
    return [p3_require_one hw_probe \
        [get_hw_probes -quiet -of_objects $ila [list $name]] $name]
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

# These exact names are asserted by the hash-matched Build 83 LTX.  Each row
# is status[0], status[1], read pointer, mem0 TID, mem1 TID, tx-valid0, and
# tx-valid1 for one ILA.
set common_names [dict create \
    {u_bd/openpiton_top_i/axis_ila_0} [list \
        {u_bd/openpiton_top_i/p3_build82_adapter_31_1} \
        {u_bd/openpiton_top_i/p3_build82_adapter_32_1} \
        {u_bd/openpiton_top_i/p3_build82_adapter_33_1} \
        {u_bd/openpiton_top_i/p3_build82_adapter_35_1} \
        {u_bd/openpiton_top_i/p3_build82_adapter_36_1} \
        {u_bd/openpiton_top_i/p3_build78_diag_23_1} \
        {u_bd/openpiton_top_i/p3_build81_control_25_1}] \
    {u_bd/openpiton_top_i/axis_ila_1} [list \
        {u_bd/openpiton_top_i/p3_build82_adapter_31_2} \
        {u_bd/openpiton_top_i/p3_build82_adapter_32_2} \
        {u_bd/openpiton_top_i/p3_build82_adapter_33_2} \
        {u_bd/openpiton_top_i/p3_build82_adapter_35_2} \
        {u_bd/openpiton_top_i/p3_build82_adapter_36_2} \
        {u_bd/openpiton_top_i/p3_build78_diag_23_2} \
        {u_bd/openpiton_top_i/p3_build81_control_25_2}] \
    {u_bd/openpiton_top_i/axis_ila_2} [list \
        {u_bd/openpiton_top_i/p3_build82_adapter_31_4} \
        {u_bd/openpiton_top_i/p3_build82_adapter_32_4} \
        {u_bd/openpiton_top_i/p3_build82_adapter_33_4} \
        {u_bd/openpiton_top_i/p3_build82_adapter_35_4} \
        {u_bd/openpiton_top_i/p3_build82_adapter_36_4} \
        {u_bd/openpiton_top_i/p3_build78_diag_23_3} \
        {u_bd/openpiton_top_i/p3_build81_control_25_3}] \
    {u_bd/openpiton_top_i/axis_ila_3} [list \
        {u_bd/openpiton_top_i/p3_build82_adapter_31_6} \
        {u_bd/openpiton_top_i/p3_build82_adapter_32_6} \
        {u_bd/openpiton_top_i/p3_build82_adapter_33_6} \
        {u_bd/openpiton_top_i/p3_build82_adapter_35_6} \
        {u_bd/openpiton_top_i/p3_build82_adapter_36_6} \
        {u_bd/openpiton_top_i/p3_build78_diag_23} \
        {u_bd/openpiton_top_i/p3_build81_control_25}]]

set case_fields [split $orphan_case _]
scan [lindex $case_fields 0] {rp%d} read_pointer
scan [lindex $case_fields 1] {tid%d} return_tid
set selected_mem_bit [expr {3 + $read_pointer}]
set selected_tx_bit [expr {5 + $return_tid}]

set armed [list]
foreach cell_name $expected_cells {
    if {![dict exists $ila_by_cell $cell_name]} {
        error "expected Build 83 ILA was not enumerated: $cell_name"
    }
    set ila [dict get $ila_by_cell $cell_name]
    set names [dict get $common_names $cell_name]
    set match_values [dict create \
        0 1 \
        1 0 \
        2 $read_pointer \
        $selected_mem_bit $return_tid \
        $selected_tx_bit 0]
    dict for {bit value} $match_values {
        set probe [p3_probe_exact $ila [lindex $names $bit]]
        set_property TRIGGER_COMPARE_VALUE "eq1'b${value}" $probe
    }
    set_property CONTROL.DATA_DEPTH 1024 $ila
    set_property CONTROL.TRIGGER_POSITION 896 $ila
    puts "Build 83 trigger $orphan_case: cell=$cell_name readptr=$read_pointer tid=$return_tid invalid_tx=$return_tid"
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
        "${output_dir}/ila_capture_build83_${orphan_case}_${timestamp}_${safe_cell}.csv"
    write_hw_ila_data -force -csv_file $csv_file $data
    if {![file exists $csv_file] || [file size $csv_file] == 0} {
        error "Build 83 CSV is missing or empty: $csv_file"
    }
    puts "Build 83 synchronized CSV: $csv_file"
}

close_hw_target
disconnect_hw_server
close_hw_manager
puts "SUCCESS: Build 83 orphan return-ID capture complete: $orphan_case"
