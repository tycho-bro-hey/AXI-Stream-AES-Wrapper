## Synthesis constraints for gcm_axi_top
## Out-of-context: clock only, no pin assignments
## Target: XC7A100T-1CSG324C (Arty A7-100T), 100 MHz

create_clock -period 10.000 -name clk [get_ports clk]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
