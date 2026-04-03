vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xpm
vlib questa_lib/msim/axis_infrastructure_v1_1_1
vlib questa_lib/msim/axis_data_fifo_v2_0_17
vlib questa_lib/msim/xil_defaultlib
vlib questa_lib/msim/proc_sys_reset_v5_0_17

vmap xpm questa_lib/msim/xpm
vmap axis_infrastructure_v1_1_1 questa_lib/msim/axis_infrastructure_v1_1_1
vmap axis_data_fifo_v2_0_17 questa_lib/msim/axis_data_fifo_v2_0_17
vmap xil_defaultlib questa_lib/msim/xil_defaultlib
vmap proc_sys_reset_v5_0_17 questa_lib/msim/proc_sys_reset_v5_0_17

vlog -work xpm  -incr -mfcu  -sv "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" "+incdir+../../ipstatic" \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm  -93  \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work axis_infrastructure_v1_1_1  -incr -mfcu  "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" "+incdir+../../ipstatic" \
"../../ipstatic/hdl/axis_infrastructure_v1_1_vl_rfs.v" \

vlog -work axis_data_fifo_v2_0_17  -incr -mfcu  "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" "+incdir+../../ipstatic" \
"../../ipstatic/hdl/axis_data_fifo_v2_0_vl_rfs.v" \

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" "+incdir+../../ipstatic" \
"../../../axis_pt_fifo_ex.gen/sources_1/ip/axis_pt_fifo/sim/axis_pt_fifo.v" \

vcom -work proc_sys_reset_v5_0_17  -93  \
"../../ipstatic/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \

vcom -work xil_defaultlib  -93  \
"../../../axis_pt_fifo_ex.gen/sources_1/ip/proc_sys_reset_0/sim/proc_sys_reset_0.vhd" \

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" "+incdir+../../ipstatic" \
"../../../axis_pt_fifo_ex.gen/sources_1/ip/clk_wiz_0/clk_wiz_0_clk_wiz.v" \
"../../../axis_pt_fifo_ex.gen/sources_1/ip/clk_wiz_0/clk_wiz_0.v" \
"../../../imports/axis_pt_fifo_example_master.v" \
"../../../imports/axis_pt_fifo_example_slave.v" \
"../../../imports/exdes_top.v" \
"../../../imports/exdes_tb.v" \

vlog -work xil_defaultlib \
"glbl.v"

