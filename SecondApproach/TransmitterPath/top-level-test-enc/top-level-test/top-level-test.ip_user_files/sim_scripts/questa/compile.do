vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xpm
vlib questa_lib/msim/axis_infrastructure_v1_1_1
vlib questa_lib/msim/axis_register_slice_v1_1_35
vlib questa_lib/msim/axis_dwidth_converter_v1_1_34
vlib questa_lib/msim/xil_defaultlib

vmap xpm questa_lib/msim/xpm
vmap axis_infrastructure_v1_1_1 questa_lib/msim/axis_infrastructure_v1_1_1
vmap axis_register_slice_v1_1_35 questa_lib/msim/axis_register_slice_v1_1_35
vmap axis_dwidth_converter_v1_1_34 questa_lib/msim/axis_dwidth_converter_v1_1_34
vmap xil_defaultlib questa_lib/msim/xil_defaultlib

vlog -work xpm  -incr -mfcu  -sv "+incdir+../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../../top-level-test.gen/sources_1/ip/axis_upsizer/hdl" "+incdir+../../../top-level-test.gen/sources_1/ip/axis_downsizer/hdl" \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm  -93  \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work axis_infrastructure_v1_1_1  -incr -mfcu  "+incdir+../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../../top-level-test.gen/sources_1/ip/axis_upsizer/hdl" "+incdir+../../../top-level-test.gen/sources_1/ip/axis_downsizer/hdl" \
"../../ipstatic/hdl/axis_infrastructure_v1_1_vl_rfs.v" \

vlog -work axis_register_slice_v1_1_35  -incr -mfcu  "+incdir+../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../../top-level-test.gen/sources_1/ip/axis_upsizer/hdl" "+incdir+../../../top-level-test.gen/sources_1/ip/axis_downsizer/hdl" \
"../../ipstatic/hdl/axis_register_slice_v1_1_vl_rfs.v" \

vlog -work axis_dwidth_converter_v1_1_34  -incr -mfcu  "+incdir+../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../../top-level-test.gen/sources_1/ip/axis_upsizer/hdl" "+incdir+../../../top-level-test.gen/sources_1/ip/axis_downsizer/hdl" \
"../../ipstatic/hdl/axis_dwidth_converter_v1_1_vl_rfs.v" \

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../../top-level-test.gen/sources_1/ip/axis_upsizer/hdl" "+incdir+../../../top-level-test.gen/sources_1/ip/axis_downsizer/hdl" \
"../../../top-level-test.gen/sources_1/ip/axis_downsizer/sim/axis_downsizer.v" \
"../../../top-level-test.gen/sources_1/ip/axis_upsizer/sim/axis_upsizer.v" \
"../../../top-level-test.srcs/sources_1/imports/aes/aes256.v" \
"../../../top-level-test.srcs/sources_1/imports/aes/aesKeySchedule.v" \
"../../../top-level-test.srcs/sources_1/imports/aes/aesRound_comb.v" \
"../../../top-level-test.srcs/sources_1/imports/gcm/aes_gcm_256.v" \
"../../../top-level-test.srcs/sources_1/imports/top-level-test/aes_gcm_core_adapter.v" \
"../../../top-level-test.srcs/sources_1/imports/gcm/gf128_mult.v" \
"../../../top-level-test.srcs/sources_1/imports/aes/gfInverse_canright.v" \
"../../../top-level-test.srcs/sources_1/imports/aes/gfMult.v" \
"../../../top-level-test.srcs/sources_1/imports/gcm/ghash.v" \
"../../../top-level-test.srcs/sources_1/imports/top-level-test/iv_loader.v" \
"../../../top-level-test.srcs/sources_1/imports/top-level-test/key_loader.v" \
"../../../top-level-test.srcs/sources_1/imports/aes/mixColumn.v" \
"../../../top-level-test.srcs/sources_1/imports/aes/subByte.v" \
"../../../top-level-test.srcs/sources_1/imports/top-level-test/tx_header_bridge.v" \
"../../../top-level-test.srcs/sources_1/imports/top-level-test/tx_stream_composer.v" \
"../../../top-level-test.srcs/sources_1/imports/top-level-test/aes_gcm_256_axis_top.v" \

vlog -work xil_defaultlib \
"glbl.v"

