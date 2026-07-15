# p3_ila_capture_build75_1hart_l15_pc_diag.tcl -- Arm the Build 75 ILA on a
# store request that has remained unacknowledged for at least 256 core cycles.

set hw_server_url "100.93.77.36"
set hw_server_port "3121"
set xvc_host "202.197.4.99"
set xvc_port "2540"
set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set project_dir [file normalize \
    "${repo_dir}/huaprop3_build75_1hart_l15_pc_diag"]
set ltx_file \
    "${project_dir}/debug_build/p3_top_build75_1hart_l15_pc_diag.ltx"
set output_dir "${project_dir}/debug_build"
set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]

if {![file exists $ltx_file]} {
    puts "ERROR: Build 75 LTX not found: $ltx_file"
    exit 1
}

open_hw_manager
connect_hw_server -url "${hw_server_url}:${hw_server_port}" -allow_non_jtag
open_hw_target -xvc_url "${xvc_host}:${xvc_port}"

set versal_dev ""
foreach dev [get_hw_devices -quiet] {
    set part [get_property PART $dev]
    puts "Device: ${dev} part=${part}"
    if {[string match "*xcvp*" [string tolower $part]]} {
        set versal_dev $dev
    }
}
if {$versal_dev eq ""} {
    puts "ERROR: no VP1902 device found"
    exit 1
}

current_hw_device $versal_dev
set_property PROBES.FILE $ltx_file [current_hw_device]
refresh_hw_device [current_hw_device]

set build75_ila ""
foreach ila [get_hw_ilas -quiet] {
    set cell_name [get_property CELL_NAME $ila]
    puts "ILA: ${ila} cell=${cell_name}"
    if {[string match "*u_ila_build75*" $cell_name]} {
        set build75_ila $ila
    }
}
if {$build75_ila eq ""} {
    puts "ERROR: u_ila_build75 was not enumerated"
    exit 1
}

set trigger_probe ""
foreach probe [get_hw_probes -quiet -of_objects $build75_ila] {
    set probe_name [get_property NAME $probe]
    puts "  probe=${probe_name}"
    if {[string match "*p3_build75_noack_trigger*" $probe_name]} {
        set trigger_probe $probe
    }
}
if {$trigger_probe eq ""} {
    puts "ERROR: Build 75 no-ack trigger probe not found"
    exit 1
}

set_property CONTROL.DATA_DEPTH 8192 $build75_ila
set_property CONTROL.TRIGGER_POSITION 4096 $build75_ila
set_property TRIGGER_COMPARE_VALUE eq1'b1 $trigger_probe
puts "Arming Build 75 trigger: ${trigger_probe} == 1"
run_hw_ila $build75_ila
wait_on_hw_ila $build75_ila
set build75_data [upload_hw_ila_data $build75_ila]
set build75_csv \
    "${output_dir}/ila_capture_build75_${timestamp}_u_ila_build75.csv"
write_hw_ila_data -force -csv_file $build75_csv $build75_data
puts "Build 75 triggered CSV: ${build75_csv}"

# Preserve the existing compact layer evidence after the causal capture.
set compact_index 0
foreach ila [get_hw_ilas -quiet] {
    if {$ila eq $build75_ila} {
        continue
    }
    incr compact_index
    catch {set_property CONTROL.DATA_DEPTH 1024 $ila}
    catch {set_property CONTROL.TRIGGER_POSITION 512 $ila}
    run_hw_ila $ila -trigger_now
    wait_on_hw_ila $ila
    set data [upload_hw_ila_data $ila]
    set cell_name [string map {/ _} [get_property CELL_NAME $ila]]
    set csv "${output_dir}/ila_capture_build75_${timestamp}_${compact_index}_${cell_name}.csv"
    write_hw_ila_data -force -csv_file $csv $data
    puts "Compact ILA CSV: ${csv}"
}

close_hw_target
disconnect_hw_server
close_hw_manager
puts "SUCCESS: Build 75 causal ILA capture complete"
