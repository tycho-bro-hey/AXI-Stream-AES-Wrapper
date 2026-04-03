transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib activehdl/xpm
vlib activehdl/axis_infrastructure_v1_1_1
vlib activehdl/axis_register_slice_v1_1_35
vlib activehdl/axis_dwidth_converter_v1_1_34
vlib activehdl/xil_defaultlib

vmap xpm activehdl/xpm
vmap axis_infrastructure_v1_1_1 activehdl/axis_infrastructure_v1_1_1
vmap axis_register_slice_v1_1_35 activehdl/axis_register_slice_v1_1_35
vmap axis_dwidth_converter_v1_1_34 activehdl/axis_dwidth_converter_v1_1_34
vmap xil_defaultlib activehdl/xil_defaultlib

vlog -work xpm  -sv2k12 "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" -l xpm -l axis_infrastructure_v1_1_1 -l axis_register_slice_v1_1_35 -l axis_dwidth_converter_v1_1_34 -l xil_defaultlib \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  \
"C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work axis_infrastructure_v1_1_1  -v2k5 "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" -l xpm -l axis_infrastructure_v1_1_1 -l axis_register_slice_v1_1_35 -l axis_dwidth_converter_v1_1_34 -l xil_defaultlib \
"../../ipstatic/hdl/axis_infrastructure_v1_1_vl_rfs.v" \

vlog -work axis_register_slice_v1_1_35  -v2k5 "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" -l xpm -l axis_infrastructure_v1_1_1 -l axis_register_slice_v1_1_35 -l axis_dwidth_converter_v1_1_34 -l xil_defaultlib \
"../../ipstatic/hdl/axis_register_slice_v1_1_vl_rfs.v" \

vlog -work axis_dwidth_converter_v1_1_34  -v2k5 "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" -l xpm -l axis_infrastructure_v1_1_1 -l axis_register_slice_v1_1_35 -l axis_dwidth_converter_v1_1_34 -l xil_defaultlib \
"../../ipstatic/hdl/axis_dwidth_converter_v1_1_vl_rfs.v" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../../../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" "+incdir+../../ipstatic/hdl" -l xpm -l axis_infrastructure_v1_1_1 -l axis_register_slice_v1_1_35 -l axis_dwidth_converter_v1_1_34 -l xil_defaultlib \
"../../../top-test.gen/sources_1/ip/axis_downsizer/sim/axis_downsizer.v" \
"../../../top-test.gen/sources_1/ip/axis_upsizer/sim/axis_upsizer.v" \
"../../../top-test.srcs/sources_1/imports/aes/aes256.v" \
"../../../top-test.srcs/sources_1/imports/aes/aesKeySchedule.v" \
"../../../top-test.srcs/sources_1/imports/aes/aesRound_comb.v" \
"../../../top-test.srcs/sources_1/imports/gcm/aes_gcm_256.v" \
"../../../top-test.srcs/sources_1/imports/top-test/aes_gcm_256_axis_decrypt_top.v" \
"../../../top-test.srcs/sources_1/imports/top-test/aes_gcm_core_adapter.v" \
"../../../top-test.srcs/sources_1/imports/gcm/gf128_mult.v" \
"../../../top-test.srcs/sources_1/imports/aes/gfInverse_canright.v" \
"../../../top-test.srcs/sources_1/imports/aes/gfMult.v" \
"../../../top-test.srcs/sources_1/imports/gcm/ghash.v" \
"../../../top-test.srcs/sources_1/imports/top-test/key_loader.v" \
"../../../top-test.srcs/sources_1/imports/aes/mixColumn.v" \
"../../../top-test.srcs/sources_1/imports/top-test/rx_stream_parser.v" \
"../../../top-test.srcs/sources_1/imports/aes/subByte.v" \
"../../../top-test.srcs/sources_1/imports/top-test/tx_header_bridge.v" \
"../../../top-test.srcs/sim_1/imports/top-test/tb_aes_gcm_256_axis_decrypt_top.v" \

vlog -work xil_defaultlib \
"glbl.v"

