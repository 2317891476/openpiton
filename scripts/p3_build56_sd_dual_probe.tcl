# p3_build56_sd_dual_probe.tcl -- Standalone P3 SD pin/protocol probe.
# Usage:
#   vivado -mode batch -source scripts/p3_build56_sd_dual_probe.tcl -tclargs -jobs 8

set script_dir [file dirname [info script]]
set repo_dir [file normalize "${script_dir}/.."]
set project_name "p3_build56_sd_dual_probe"
set output_project_dir [file normalize "${repo_dir}/huaprop3_build56_sd_dual_probe"]
set output_dir "${output_project_dir}/debug_build"
set src_dir "${repo_dir}/piton/design/xilinx/huaprop3"
set part "xcvp1902-vsva6865-1MP-e-S"
set bd_name "p3_sd_probe_bd"
set jobs 8

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        -jobs {
            incr i
            if {$i >= [llength $argv]} {
                puts "ERROR: -jobs requires a value"
                exit 1
            }
            set jobs [lindex $argv $i]
        }
        default {
            puts "ERROR: unknown argument: $arg"
            exit 1
        }
    }
}

if {[info exists env(P3_BUILD56_WORK_DIR)] && $env(P3_BUILD56_WORK_DIR) ne ""} {
    set project_dir [file normalize $env(P3_BUILD56_WORK_DIR)]
} else {
    set project_dir [file normalize "D:/p3b56"]
}

proc p3_check_run {run_name phase} {
    set status [get_property STATUS [get_runs $run_name]]
    set progress [get_property PROGRESS [get_runs $run_name]]
    puts "${phase} status for ${run_name}: ${status}, progress=${progress}"
    if {[string match -nocase "*fail*" $status] ||
        [string match -nocase "*error*" $status] ||
        $progress ne "100%"} {
        puts "ERROR: ${phase} failed"
        exit 1
    }
}

proc p3_latest_file {dir pattern} {
    set files [glob -nocomplain -directory $dir $pattern]
    if {[llength $files] == 0} {
        return ""
    }
    set best [lindex $files 0]
    foreach file $files {
        if {[file mtime $file] > [file mtime $best]} {
            set best $file
        }
    }
    return $best
}

puts "=========================================="
puts " P3 Build 56 standalone SD dual probe"
puts " Project work dir: ${project_dir}"
puts " Output dir:       ${output_dir}"
puts " Jobs:             ${jobs}"
puts "=========================================="

foreach required [list \
    "${src_dir}/p3_sd_dual_probe_top.v" \
    "${src_dir}/p3_sd_dual_probe.xdc" \
] {
    if {![file exists $required]} {
        puts "ERROR: missing required file: $required"
        exit 1
    }
}

file delete -force $project_dir
file delete -force $output_project_dir
file mkdir $output_dir

create_project -force $project_name $project_dir -part $part
set_property target_language Verilog [current_project]

add_files -norecurse "${src_dir}/p3_sd_dual_probe_top.v"
add_files -fileset constrs_1 -norecurse "${src_dir}/p3_sd_dual_probe.xdc"

create_bd_design $bd_name

create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 diff_sysclock
set_property CONFIG.FREQ_HZ 100000000 [get_bd_intf_ports diff_sysclock]
create_bd_port -dir I -type rst reset
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports reset]

create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 clk_wizard_0
set_property -dict [list \
    CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.USE_RESET {true} \
    CONFIG.CLKOUT_USED {true,false,false,false,false,false,false} \
    CONFIG.CLKOUT_PORT {probe_clk,clk_out2,clk_out3,clk_out4,clk_out5,clk_out6,clk_out7} \
    CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {30.000,100.000,100.000,100.000,100.000,100.000,100.000} \
    CONFIG.CLKOUT_REQUESTED_PHASE {0.000,0.000,0.000,0.000,0.000,0.000,0.000} \
    CONFIG.CLKOUT_REQUESTED_DUTY_CYCLE {50.000,50.000,50.000,50.000,50.000,50.000,50.000} \
] [get_bd_cells clk_wizard_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:ps_wizard:1.0 ps_wizard_0
set_property -dict [list \
    CONFIG.PS_PMC_CONFIG { \
        PMC_SMAP_PERIPHERAL {PRIMARY_ENABLE 1 IO 8_Bit} \
        SMON_INTERFACE_TO_USE {PMBus} \
        SMON_PMBUS_ADDRESS {0x18} \
    } \
] [get_bd_cells ps_wizard_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_locked
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells const_locked]

create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 axis_ila_0
set_property -dict [list \
    CONFIG.C_MON_TYPE {Net_Probes} \
    CONFIG.C_NUM_OF_PROBES {4} \
    CONFIG.C_PROBE0_WIDTH {32} \
    CONFIG.C_PROBE1_WIDTH {64} \
    CONFIG.C_PROBE2_WIDTH {64} \
    CONFIG.C_PROBE3_WIDTH {64} \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES {0} \
    CONFIG.ALL_PROBE_SAME_MU {true} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
] [get_bd_cells axis_ila_0]

connect_bd_intf_net [get_bd_intf_ports diff_sysclock] [get_bd_intf_pins clk_wizard_0/CLK_IN1_D]
connect_bd_net [get_bd_ports reset] [get_bd_pins clk_wizard_0/reset]
connect_bd_net [get_bd_ports reset] [get_bd_pins proc_sys_reset_0/ext_reset_in]
connect_bd_net [get_bd_pins clk_wizard_0/probe_clk] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_pins const_locked/dout] [get_bd_pins proc_sys_reset_0/dcm_locked]
connect_bd_net [get_bd_pins clk_wizard_0/probe_clk] [get_bd_pins axis_ila_0/clk]

create_bd_port -dir O probe_clk_o
create_bd_port -dir O -from 0 -to 0 probe_aresetn_o
create_bd_port -dir I -from 31 -to 0 p3_sd_status_i
create_bd_port -dir I -from 63 -to 0 p3_sd_bus0_i
create_bd_port -dir I -from 63 -to 0 p3_sd_bus1_i
create_bd_port -dir I -from 63 -to 0 p3_sd_summary_i

connect_bd_net [get_bd_pins clk_wizard_0/probe_clk] [get_bd_ports probe_clk_o]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_ports probe_aresetn_o]
connect_bd_net [get_bd_ports p3_sd_status_i] [get_bd_pins axis_ila_0/probe0]
connect_bd_net [get_bd_ports p3_sd_bus0_i] [get_bd_pins axis_ila_0/probe1]
connect_bd_net [get_bd_ports p3_sd_bus1_i] [get_bd_pins axis_ila_0/probe2]
connect_bd_net [get_bd_ports p3_sd_summary_i] [get_bd_pins axis_ila_0/probe3]

regenerate_bd_layout
save_bd_design
validate_bd_design
make_wrapper -files [get_files ${bd_name}.bd] -top
add_files -norecurse "${project_dir}/${project_name}.gen/sources_1/bd/${bd_name}/hdl/${bd_name}_wrapper.v"

set_property top p3_sd_dual_probe_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
p3_check_run synth_1 "Synthesis"

launch_runs impl_1 -to_step write_device_image -jobs $jobs
wait_on_run impl_1
p3_check_run impl_1 "Implementation"

set run_dir [get_property DIRECTORY [get_runs impl_1]]
if {$run_dir eq ""} {
    set run_dir "${project_dir}/${project_name}.runs/impl_1"
}
set pdi_src [p3_latest_file $run_dir "*.pdi"]
set ltx_src [p3_latest_file $run_dir "*.ltx"]
if {$pdi_src eq "" || $ltx_src eq ""} {
    puts "ERROR: missing PDI or LTX in ${run_dir}"
    exit 1
}

set pdi_dst "${output_dir}/p3_top_build56_sd_dual_probe.pdi"
set ltx_dst "${output_dir}/p3_top_build56_sd_dual_probe.ltx"
file copy -force $pdi_src $pdi_dst
file copy -force $ltx_src $ltx_dst
puts "Published PDI: ${pdi_dst}"
puts "Published LTX: ${ltx_dst}"

close_project
puts "=========================================="
puts " P3 Build 56 standalone SD dual probe complete"
puts "=========================================="
