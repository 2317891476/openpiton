# p3_ila_snapshot_build94_noc.tcl -- Snapshot all Build 94 ILAs at stall.
set hw_server_url "100.93.77.36"
set hw_server_port "3121"
set xvc_host "202.197.4.99"
set xvc_port "2540"
set default_ltx {D:/p3b94_noc_boundary/p3_top_build94_noc_boundary.ltx}
set default_output_dir {D:/p3b94_noc_boundary/noc_snapshot}
if {[llength $argv] > 2} { error "expected optional LTX and output dir" }
set ltx_file $default_ltx
set output_dir $default_output_dir
if {[llength $argv] >= 1} { set ltx_file [file normalize [lindex $argv 0]] }
if {[llength $argv] == 2} { set output_dir [file normalize [lindex $argv 1]] }
if {![file exists $ltx_file] || [file size $ltx_file] == 0} { error "LTX missing: $ltx_file" }
file mkdir $output_dir
open_hw_manager
connect_hw_server -url "${hw_server_url}:${hw_server_port}" -allow_non_jtag
open_hw_target -xvc_url "${xvc_host}:${xvc_port}"
set versal_dev ""
foreach dev [get_hw_devices -quiet] {
    if {[string match "*xcvp*" [string tolower [get_property PART $dev]]]} { set versal_dev $dev }
}
if {$versal_dev eq ""} { error "no VP1902 device found" }
current_hw_device $versal_dev
set_property PROBES.FILE $ltx_file [current_hw_device]
refresh_hw_device [current_hw_device]
set ila_by_cell [dict create]
foreach ila [get_hw_ilas -quiet] { dict set ila_by_cell [get_property CELL_NAME $ila] $ila }
set cells [list u_ila_build90 u_bd/openpiton_top_i/axis_ila_1 u_bd/openpiton_top_i/axis_ila_2 u_bd/openpiton_top_i/axis_ila_3]
set armed [list]
foreach cell $cells {
    if {![dict exists $ila_by_cell $cell]} { error "ILA not enumerated: $cell" }
    set ila [dict get $ila_by_cell $cell]
    set_property CONTROL.DATA_DEPTH 1024 $ila
    set_property CONTROL.TRIGGER_POSITION 512 $ila
    lappend armed $ila
}
run_hw_ila $armed -trigger_now
foreach ila $armed { wait_on_hw_ila $ila }
set ts [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
foreach ila $armed {
    set cell [get_property CELL_NAME $ila]
    set data [upload_hw_ila_data $ila]
    set safe [string map {/ _} $cell]
    set csv "${output_dir}/ila_snapshot_build94_${ts}_${safe}.csv"
    write_hw_ila_data -force -csv_file $csv $data
    if {![file exists $csv] || [file size $csv] == 0} { error "CSV missing: $csv" }
    puts "Build 94 NoC CSV: $csv"
}
close_hw_target
disconnect_hw_server
close_hw_manager
puts "SUCCESS: Build 94 NoC snapshot complete"
