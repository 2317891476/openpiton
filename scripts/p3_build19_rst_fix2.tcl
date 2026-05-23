# p3_build19_rst_fix2.tcl — Correct reset fix + ILA
# Fix: peripheral_aresetn passed directly (no inverter)
# PITON_FPGA_RST_ACT_HIGH removed for HUAPROP3 in piton_system.vh
# Both system.v and chipset.v no longer invert — correct double-cancellation

set project_dir [file normalize "/home/illya/openpiton/huaprop3_openpiton"]
set project_name "huaprop3_openpiton"
set xdc_file "Z:/tmp/huaprop3_constraints.xdc"
set output_dir "${project_dir}/debug_build"

puts "=========================================="
puts " Build 19: Correct reset fix (no inverter)"
puts "=========================================="

open_project "${project_dir}/${project_name}.xpr"

# Swap XDC
set old_xdc [get_files -quiet *constraints.xdc]
if {$old_xdc ne ""} { remove_files $old_xdc }
set stale_ila [get_files -quiet *debug* -of_objects [current_fileset -constrset]]
if {$stale_ila ne ""} { remove_files $stale_ila }
add_files -fileset constrs_1 -norecurse $xdc_file

# Swap p3_top.v (peripheral_aresetn direct, no inverter)
set old_top [get_files -quiet *p3_top.v]
if {$old_top ne ""} { remove_files $old_top }
add_files -fileset sources_1 -norecurse "Z:/tmp/p3_top.v"
set_property file_type "Verilog" [get_files "Z:/tmp/p3_top.v"]

# Force-replace piton_system.vh (HUAPROP3 removed from PITON_FPGA_RST_ACT_HIGH)
set old_vh [get_files -quiet *piton_system.vh]
if {$old_vh ne ""} { remove_files $old_vh }
add_files -fileset sources_1 -norecurse "Z:/tmp/piton_system.vh"
set_property file_type "Verilog Header" [get_files "Z:/tmp/piton_system.vh"]
set_property is_global_include true [get_files "Z:/tmp/piton_system.vh"]

update_compile_order -fileset sources_1

# Synthesis
puts "Launching synthesis..."
catch {reset_run impl_1}
catch {reset_run synth_1}
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis Status: $synth_status"
if {[string match "*fail*" [string tolower $synth_status]]} {
    puts "ERROR: Synthesis failed!"
    close_project
    exit 1
}

# Insert ILA (9 probes, all flat net names)
puts "Opening synthesized design..."
open_run synth_1 -name synth_1
puts "Creating ILA debug core..."
create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_0]

puts "Connecting ILA clock..."
connect_debug_port u_ila_0/clk [get_nets {chipset_clk}]

puts "Adding probes..."
proc connect_probe {ila port width label netlist} {
    create_debug_port $ila probe
    set_property port_width $width [get_debug_ports $ila/$port]
    puts "  $port: $label"
    catch {connect_debug_port $ila/$port [get_nets $netlist]}
}

set_property port_width 1 [get_debug_ports u_ila_0/probe0]
puts "  probe0: chipset_clk"
connect_debug_port u_ila_0/probe0 [get_nets {chipset_clk}]

connect_probe u_ila_0 probe1  1  "uart_tx"        {uart_tx_OBUF}
connect_probe u_ila_0 probe2  1  "uart_rx"        {uart_rx_IBUF}
connect_probe u_ila_0 probe3  1  "reset_IBUF"     {reset_IBUF}
connect_probe u_ila_0 probe4  2  "leds[1:0]"      {leds_OBUF[0] leds_OBUF[1]}
connect_probe u_ila_0 probe5  1  "m_axi_awvalid"  {m_axi_awvalid}
connect_probe u_ila_0 probe6  1  "m_axi_arvalid"  {m_axi_arvalid}
connect_probe u_ila_0 probe7  1  "m_axi_rvalid"   {m_axi_rvalid}
connect_probe u_ila_0 probe8  1  "m_axi_bvalid"   {m_axi_bvalid}

puts "Saving debug constraints..."
catch {write_debug_probes -force ${output_dir}/p3_top_debug.ltx}
save_constraints -force
close_design

# Implementation
puts "Launching implementation with ILA..."
catch {reset_run impl_1}
launch_runs impl_1 -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
puts "Implementation Status: $impl_status"
puts "Implementation Progress: $impl_progress"
if {$impl_progress != "100%"} {
    puts "ERROR: Implementation did not complete!"
    close_project
    exit 1
}

# PDI
puts "Generating PDI..."
launch_runs impl_1 -to_step write_device_image -jobs 8
wait_on_run impl_1
set pdi_status [get_property STATUS [get_runs impl_1]]
puts "PDI Status: $pdi_status"

set impl_dir "${project_dir}/${project_name}.runs/impl_1"
if {[file exists "${impl_dir}/p3_top.pdi"]} {
    file copy -force "${impl_dir}/p3_top.pdi" "${output_dir}/p3_top_debug.pdi"
    puts "PDI: ${output_dir}/p3_top_debug.pdi"
}
if {[file exists "${impl_dir}/p3_top.ltx"]} {
    file copy -force "${impl_dir}/p3_top.ltx" "${output_dir}/p3_top_debug.ltx"
    puts "LTX: ${output_dir}/p3_top_debug.ltx"
}

close_project
puts "=========================================="
puts " Build 19 complete"
puts "=========================================="
