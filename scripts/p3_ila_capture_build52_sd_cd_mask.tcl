# p3_ila_capture_build52_sd_cd_mask.tcl -- Capture Build 52 SD card-detect mask debug ILAs.

set hw_server_url "100.93.77.36"
set hw_server_port "3121"
set xvc_host "202.197.4.99"
set xvc_port "2540"
if {[info exists env(P3_CAPTURE_PROJECT_NAME)] && $env(P3_CAPTURE_PROJECT_NAME) ne ""} {
    set project_name $env(P3_CAPTURE_PROJECT_NAME)
} else {
    set project_name "huaprop3_build52_sd_cd_mask"
}
if {[info exists env(P3_CAPTURE_PDI_BASENAME)] && $env(P3_CAPTURE_PDI_BASENAME) ne ""} {
    set pdi_basename $env(P3_CAPTURE_PDI_BASENAME)
} else {
    set pdi_basename "p3_top_build52_sd_cd_mask"
}
if {[info exists env(P3_CAPTURE_TAG)] && $env(P3_CAPTURE_TAG) ne ""} {
    set capture_tag $env(P3_CAPTURE_TAG)
} else {
    set capture_tag "build52"
}
set project_dir [file normalize "[file dirname [info script]]/../${project_name}"]
set ltx_file "${project_dir}/debug_build/${pdi_basename}.ltx"
set output_dir "${project_dir}/debug_build"

proc p3_sanitize_filename {name} {
    regsub -all {[^A-Za-z0-9_.-]} $name "_" clean
    return $clean
}

puts "=========================================="
puts " P3 Build 52 no-stack AXI16550 SD card-detect mask ILA Capture"
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
if {[llength $ilas] == 0} {
    puts "ERROR: No ILA core found"
    exit 1
}

set idx 0
foreach ila $ilas {
    incr idx
    set cell_name [get_property CELL_NAME $ila]
    set clean_name [p3_sanitize_filename $cell_name]
    set csv_file "${output_dir}/ila_capture_${capture_tag}_${idx}_${clean_name}.csv"

    puts "------------------------------------------"
    puts "Capturing ILA ${idx}: $ila"
    foreach prop {NAME CORE_UUID CELL_NAME CONTROL.DATA_DEPTH CONTROL.TRIGGER_POSITION} {
        if {![catch {get_property $prop $ila} v]} {
            puts "  $prop=$v"
        }
    }

    catch {set_property CONTROL.DATA_DEPTH 1024 $ila}
    catch {set_property CONTROL.TRIGGER_POSITION 512 $ila}

    puts "Triggering ILA ${idx} immediately..."
    run_hw_ila $ila -trigger_now
    wait_on_hw_ila $ila
    set ila_data [upload_hw_ila_data $ila]

    write_hw_ila_data -force -csv_file $csv_file $ila_data
    puts "CSV written to: $csv_file"

    puts "Probe list:"
    foreach p [get_hw_probes -of_objects $ila -quiet] {
        set name [get_property NAME $p]
        set width ""
        set sample ""
        catch {set width [get_property WIDTH $p]}
        catch {set sample [get_property SAMPLE $p]}
        puts "  $name width=$width sample=$sample"
    }
}

close_hw_target
disconnect_hw_server
close_hw_manager

puts "=========================================="
puts " Build 52 AXI16550 SD card-detect mask debug ILA capture complete"
puts "=========================================="
