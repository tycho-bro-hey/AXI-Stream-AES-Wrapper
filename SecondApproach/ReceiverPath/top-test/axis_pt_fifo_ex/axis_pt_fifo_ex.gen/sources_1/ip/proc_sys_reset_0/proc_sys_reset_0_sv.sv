// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------
// This file contains confidential and proprietary information
// of AMD and is protected under U.S. and international copyright
// and other intellectual property laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// AMD, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) AMD shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or AMD had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// AMD products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of AMD products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
//
// DO NOT MODIFY THIS FILE.

// MODULE VLNV: xilinx.com:ip:proc_sys_reset:5.0

`timescale 1ps / 1ps

`include "vivado_interfaces.svh"

module proc_sys_reset_0_sv (
  (* X_INTERFACE_IGNORE = "true" *)
  input wire slowest_sync_clk,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire ext_reset_in,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire aux_reset_in,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire mb_debug_sys_rst,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire dcm_locked,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire mb_reset,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [0:0] bus_struct_reset,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [0:0] peripheral_reset,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [0:0] interconnect_aresetn,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [0:0] peripheral_aresetn
);

  proc_sys_reset_0 inst (
    .slowest_sync_clk(slowest_sync_clk),
    .ext_reset_in(ext_reset_in),
    .aux_reset_in(aux_reset_in),
    .mb_debug_sys_rst(mb_debug_sys_rst),
    .dcm_locked(dcm_locked),
    .mb_reset(mb_reset),
    .bus_struct_reset(bus_struct_reset),
    .peripheral_reset(peripheral_reset),
    .interconnect_aresetn(interconnect_aresetn),
    .peripheral_aresetn(peripheral_aresetn)
  );

endmodule
