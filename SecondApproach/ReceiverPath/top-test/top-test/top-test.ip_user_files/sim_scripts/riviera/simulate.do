transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+tb_aes_gcm_256_axis_decrypt_top  -L xil_defaultlib -L xpm -L axis_infrastructure_v1_1_1 -L axis_register_slice_v1_1_35 -L axis_dwidth_converter_v1_1_34 -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.tb_aes_gcm_256_axis_decrypt_top xil_defaultlib.glbl

do {tb_aes_gcm_256_axis_decrypt_top.udo}

run 1000ns

endsim

quit -force
