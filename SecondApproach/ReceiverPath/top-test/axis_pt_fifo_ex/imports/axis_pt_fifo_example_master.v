//  (c) Copyright  2013 - 2026 Advanced Micro Devices, Inc. All rights reserved.
//
//  This file contains confidential and proprietary information
//  of Advanced Micro Devices, Inc. and is protected under U.S. and
//  international copyright and other intellectual property
//  laws.
//
//  DISCLAIMER
//  This disclaimer is not a license and does not grant any
//  rights to the materials distributed herewith. Except as
//  otherwise provided in a valid license issued to you by
//  AMD, and to the maximum extent permitted by applicable
//  law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
//  WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
//  AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
//  BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
//  INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
//  (2) AMD shall not be liable (whether in contract or tort,
//  including negligence, or under any other theory of
//  liability) for any loss or damage of any kind or nature
//  related to, arising under or in connection with these
//  materials, including for any direct, or any indirect,
//  special, incidental, or consequential loss or damage
//  (including loss of data, profits, goodwill, or any type of
//  loss or damage suffered as a result of any action brought
//  by a third party) even if such damage or loss was
//  reasonably foreseeable or AMD had been advised of the
//  possibility of the same.
//
//  CRITICAL APPLICATIONS
//  AMD products are not designed or intended to be fail-
//  safe, or for use in any application requiring fail-safe
//  performance, such as life-support or safety devices or
//  systems, Class III medical devices, nuclear facilities,
//  applications related to the deployment of airbags, or any
//  other applications that could lead to death, personal
//  injury, or severe property or environmental damage
//  (individually and collectively, "Critical
//  Applications"). Customer assumes the sole risk and
//  liability of any use of AMD products in Critical
//  Applications, subject only to applicable laws and
//  regulations governing limitations on product liability.
//
//  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
//  PART OF THIS FILE AT ALL TIMES.
//-----------------------------------------------------------------------------

`timescale 1ps/1ps

`default_nettype none

module
axis_pt_fifo_example_master #(
  parameter integer C_MASTER_ID = 0
)
(
  /**************** Stream Signals ****************/
  output reg                             m_axis_tvalid = 0,
  input  wire                            m_axis_tready,
  output wire [8-1:0]     m_axis_tdata,
  output reg                             m_axis_tlast = 0,
  /**************** System Signals ****************/
  input  wire                            aclk,
  input  wire                            aresetn,
  /**************** Done Signal ****************/
  output reg                             done = 0
);

  /**************** Local Parameters ****************/
  localparam integer  P_M_TDATA_BYTES = 8 / 8;
  localparam [8-1:0]  P_M_PACKET_SIZE = (16 - 1);
  localparam [16-1:0] P_M_PACKET_NUM = 16;
  localparam [16-1:0] P_M_SINGLES_NUM = 256;
  localparam [17-1:0] P_M_DONE_NUM = 272;

  /**************** Internal Wires/Regs ****************/
  genvar  i;
  reg [8*P_M_TDATA_BYTES-1:0]  tdata_i = {P_M_TDATA_BYTES{8'h00}};
  reg [16-1:0] pcnt_i = 16'h0000;
  reg [16-1:0] tcnt_i = 16'h0000;
  wire         done_i;
  wire         transfer_i;
  wire         areset = ~aresetn;
  reg [2-1:0]  areset_i = 2'b00;

  /**************** Assign Signals ****************/
  assign m_axis_tdata = tdata_i;
  assign transfer_i = m_axis_tready && m_axis_tvalid;

    assign done_i = (transfer_i && (pcnt_i == P_M_DONE_NUM - 1'b1) && (tcnt_i == P_M_PACKET_SIZE));


  // Register Reset
  always @(posedge aclk) begin
    areset_i <= {areset_i[0], areset};
  end

  //**********************************************
  // TDATA
  //**********************************************
  generate
    for(i=0; i<P_M_TDATA_BYTES; i=i+1) begin: tdata_incr_g
      always @(posedge aclk) begin
        if(areset) begin
          tdata_i[8*i+:8] <= 8'h00;
        end
        else
        begin
          tdata_i[8*i+:8] <= (transfer_i) ? tdata_i[8*i+:8] + 1'b1 : tdata_i[8*i+:8];
        end
      end
    end
  endgenerate



  //**********************************************
  // TVALID
  //**********************************************
  always @(posedge aclk) begin
    if(areset) begin
      m_axis_tvalid <= 1'b0;
    end
    else
    begin
      // TVALID
      if(done_i) begin
        m_axis_tvalid <= 1'b0;
      end
      else if(areset_i == 2'b10) begin
        m_axis_tvalid <= 1'b1;
      end
      else begin
        m_axis_tvalid <= m_axis_tvalid;
      end
    end
  end

  //**********************************************
  // TLAST
  //**********************************************
  always @(posedge aclk) begin
    if(areset) begin
      m_axis_tlast <= 1'b0;
    end
    else
    begin
      // TLAST
      if(areset_i == 2'b10) begin
        m_axis_tlast <= 1'b1;
      end
      else if((pcnt_i >= (P_M_SINGLES_NUM - 1'b1)) && transfer_i && m_axis_tlast) begin
        m_axis_tlast <= 1'b0;
      end
      else if(tcnt_i == (P_M_PACKET_SIZE - 1'b1) && transfer_i) begin
        m_axis_tlast <= 1'b1;
      end
      else begin
        m_axis_tlast <= m_axis_tlast;
      end
    end
  end


  //**********************************************
  // PCNT, TCNT, DONE
  //**********************************************
  always @(posedge aclk) begin
    if(areset) begin
      pcnt_i <= 16'h0000;
      tcnt_i <= 16'h0000;
      done <= 1'b0;
    end
    else
    begin
      // DONE
      done <= (done_i) ? 1'b1 : done;

      // Increment counters
      tcnt_i <= (transfer_i) ? (m_axis_tlast ? 16'h0000 : (tcnt_i + 1'b1)) : tcnt_i;
      pcnt_i <= (transfer_i && m_axis_tlast) ? (pcnt_i + 1'b1) : pcnt_i;
    end
  end

endmodule

`default_nettype wire

