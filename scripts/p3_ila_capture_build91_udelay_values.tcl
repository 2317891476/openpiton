# p3_ila_capture_build91_udelay_values.tcl -- Synchronously capture the clean
# Build 90 control ILA plus Build 91 a3/a4/a5 udelay value probes.

set hw_server_url "100.93.77.36"
set hw_server_port "3121"
set xvc_host "202.197.4.99"
set xvc_port "2540"
set default_ltx {D:/p3b91_udelay_values/p3_top_build91_udelay_values.ltx}
set default_output_dir {D:/p3b91_udelay_values/captures}
set capture_id {build91}
if {[info exists env(P3_UDELAY_CAPTURE_ID)]} {
    set capture_id $env(P3_UDELAY_CAPTURE_ID)
}
set trigger_pc_hex "ffffffff807d8aa4"
set trigger_pc_low24 0x7d8aa4
set commit_pc_name \
    {u_openpiton/system_inst/chip/tile0/g_ariane_core.core/ariane/i_cva6/issue_stage_i/i_scoreboard/commit_instr_id_commit[0][pc]}

if {[llength $argv] > 2} {
    error "expected optional Build 91 LTX and output directory"
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
    error "Build 91 LTX is missing or empty: $ltx_file"
}
file mkdir $output_dir

proc p3_b91_require_one {kind objects label} {
    if {[llength $objects] != 1} {
        error "Build 91 expected one $kind for $label, found [llength $objects]"
    }
    return [lindex $objects 0]
}

proc p3_b91_pc_probe_name {ila_index bit} {
    set base "u_bd/openpiton_top_i/p3_build91_ila1_${bit}"
    switch $ila_index {
        1 { return "${base}_1" }
        2 { return "${base}_2" }
        3 { return $base }
        default { error "invalid Build 91 ILA index: $ila_index" }
    }
}

proc p3_b91_safe_name {cell_name} {
    return [string map {/ _} $cell_name]
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

set ila_by_cell [dict create]
foreach ila [get_hw_ilas -quiet] {
    dict set ila_by_cell [get_property CELL_NAME $ila] $ila
}

set control_cell {u_ila_build90}
if {![dict exists $ila_by_cell $control_cell]} {
    error "Build 91 control ILA was not enumerated: $control_cell"
}
set control_ila [dict get $ila_by_cell $control_cell]
set control_pc [p3_b91_require_one hw_probe \
    [get_hw_probes -quiet -of_objects $control_ila [list $commit_pc_name]] \
    $commit_pc_name]
set_property TRIGGER_COMPARE_VALUE "eq64'h${trigger_pc_hex}" $control_pc
set_property CONTROL.DATA_DEPTH 4096 $control_ila
set_property CONTROL.TRIGGER_POSITION 512 $control_ila
set armed [list $control_ila]

for {set ila_index 1} {$ila_index <= 3} {incr ila_index} {
    set cell_name "u_bd/openpiton_top_i/axis_ila_${ila_index}"
    if {![dict exists $ila_by_cell $cell_name]} {
        error "Build 91 value ILA was not enumerated: $cell_name"
    }
    set ila [dict get $ila_by_cell $cell_name]
    for {set bit 0} {$bit < 24} {incr bit} {
        set probe_name [p3_b91_pc_probe_name $ila_index $bit]
        set probe [p3_b91_require_one hw_probe \
            [get_hw_probes -quiet -of_objects $ila [list $probe_name]] \
            $probe_name]
        set value [expr {($trigger_pc_low24 >> $bit) & 1}]
        set_property TRIGGER_COMPARE_VALUE "eq1'b${value}" $probe
    }
    set_property CONTROL.DATA_DEPTH 1024 $ila
    set_property CONTROL.TRIGGER_POSITION 512 $ila
    lappend armed $ila
}

puts "Build 91 synchronized trigger: full PC 0x${trigger_pc_hex}"
run_hw_ila $armed
foreach ila $armed {
    wait_on_hw_ila $ila
}

set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
foreach ila $armed {
    set cell_name [get_property CELL_NAME $ila]
    set data [upload_hw_ila_data $ila]
    set safe_cell [p3_b91_safe_name $cell_name]
    set csv_file \
        "${output_dir}/ila_capture_${capture_id}_${timestamp}_${safe_cell}.csv"
    write_hw_ila_data -force -csv_file $csv_file $data
    if {![file exists $csv_file] || [file size $csv_file] == 0} {
        error "Build 91 CSV is missing or empty: $csv_file"
    }
    puts "Build 91 synchronized CSV: $csv_file"
}

close_hw_target
disconnect_hw_server
close_hw_manager
puts "SUCCESS: Build 91 udelay value capture complete"
