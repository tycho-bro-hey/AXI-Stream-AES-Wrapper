transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xpm
vlib riviera/axis_infrastructure_v1_1_1
vlib riviera/axis_data_fifo_v2_0_17
vlib riviera/xil_defaultlib
vlib riviera/proc_sys_reset_v5_0_17

vmap xpm riviera/xpm
vmap axis_infrastructure_v1_1_1 riviera/axis_infrastructure_v1_1_1
vmap axis_data_fifo_v2_0_17 riviera/axis_data_fifo_v2_0_17
vmap xil_defaultlib riviera/xil_defaultlib
vmap proc_sys_reset_v5_0_17 riviera/proc_sys_reset_v5_0_17

vlog -work xpm  -incr "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" "+incdir+../../ipstatic" -l xpm -l axis_infrastructure_v1_1_1 -l axis_data_fifo_v2_0_17 -l xil_defaultlib -l proc_sys_reset_v5_0_17 \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  -incr \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work axis_infrastructure_v1_1_1  -incr -v2k5 "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" "+incdir+../../ipstatic" -l xpm -l axis_infrastructure_v1_1_1 -l axis_data_fifo_v2_0_17 -l xil_defaultlib -l proc_sys_reset_v5_0_17 \
"../../ipstatic/hdl/axis_infrastructure_v1_1_vl_rfs.v" \

vlog -work axis_data_fifo_v2_0_17  -incr -v2k5 "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" "+incdir+../../ipstatic" -l xpm -l axis_infrastructure_v1_1_1 -l axis_data_fifo_v2_0_17 -l xil_defaultlib -l proc_sys_reset_v5_0_17 \
"../../ipstatic/hdl/axis_data_fifo_v2_0_vl_rfs.v" \

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" "+incdir+../../ipstatic" -l xpm -l axis_infrastructure_v1_1_1 -l axis_data_fifo_v2_0_17 -l xil_defaultlib -l proc_sys_reset_v5_0_17 \
"../../../axis_pt_fifo_ex.gen/sources_1/ip/axis_pt_fifo/sim/axis_pt_fifo.v" \

vcom -work proc_sys_reset_v5_0_17 -93  -incr \
"../../ipstatic/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \

vcom -work xil_defaultlib -93  -incr \
"../../../axis_pt_fifo_ex.gen/sources_1/ip/proc_sys_reset_0/sim/proc_sys_reset_0.vhd" \

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" "+incdir+../../ipstatic" -l xpm -l axis_infrastructure_v1_1_1 -l axis_data_fifo_v2_0_17 -l xil_defaultlib -l proc_sys_reset_v5_0_17 \
"../../../axis_pt_fifo_ex.gen/sources_1/ip/clk_wiz_0/clk_wiz_0_clk_wiz.v" \
"../../../axis_pt_fifo_ex.gen/sources_1/ip/clk_wiz_0/clk_wiz_0.v" \
"../../../imports/axis_pt_fifo_example_master.v" \
"../../../imports/axis_pt_fifo_example_slave.v" \
"../../../imports/exdes_top.v" \
"../../../imports/exdes_tb.v" \

vlog -work xil_defaultlib \
"glbl.v"

