`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: gcm_rx_shim
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Byte-order shim between the Vivado axis_dwidth_converter
//              (8→128 bit) and the gcm_axi_encrypt wrapper. Performs two
//              transformations:
//
//              1. Byte-reversal: AXI-Stream convention places the first
//                 received byte in tdata[7:0] (little-endian byte lane).
//                 The GCM core expects the first byte in tdata[127:120]
//                 (big-endian / left-aligned). This module swaps all 16
//                 byte lanes.
//
//              2. tkeep[15:0] → byteCount[4:0]: The width converter
//                 outputs a contiguous tkeep bitmask indicating valid
//                 bytes. The GCM core expects a 5-bit byte count where
//                 0 encodes 16 full bytes.
//
//              Pure combinational — no clock, no registers. Both the
//              width converter output and the FSM input are registered,
//              so this adds zero pipeline latency.
//
// Dependencies: None
//
//////////////////////////////////////////////////////////////////////////////////

module gcm_rx_shim (
    // AXI-Stream input (from axis_dwidth_converter master)
    input wire [127:0] s_tdata,
    input wire [15:0]  s_tkeep,
    input wire         s_tvalid,
    input wire         s_tlast,
    output wire        s_tready,

    // Block output (to gcm_axi_encrypt rxBlk interface)
    output wire [127:0] m_tdata,
    output wire         m_tvalid,
    output wire         m_tlast,
    input wire          m_tready,
    output wire [4:0]   m_byteCount    // 1-16, 0 encodes 16
);

    // =========================================================================
    // Byte reversal: AXI byte lane i → GCM byte lane (15 - i)
    //
    // AXI:  byte 0 in [7:0],   byte 1 in [15:8],   ..., byte 15 in [127:120]
    // GCM:  byte 0 in [127:120], byte 1 in [119:112], ..., byte 15 in [7:0]
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : byteSwap
            assign m_tdata[127 - i*8 -: 8] = s_tdata[i*8 +: 8];
        end
    endgenerate

    // =========================================================================
    // tkeep → byteCount conversion
    //
    // tkeep is guaranteed contiguous from bit 0 by the width converter.
    // Popcount gives valid byte count. Convention: 0 encodes 16.
    // =========================================================================
    wire [4:0] popCount;

    assign popCount = s_tkeep[0]  + s_tkeep[1]  + s_tkeep[2]  + s_tkeep[3]
                    + s_tkeep[4]  + s_tkeep[5]  + s_tkeep[6]  + s_tkeep[7]
                    + s_tkeep[8]  + s_tkeep[9]  + s_tkeep[10] + s_tkeep[11]
                    + s_tkeep[12] + s_tkeep[13] + s_tkeep[14] + s_tkeep[15];

    // 16 → 5'd0 (encodes 16), 1-15 → pass through
    assign m_byteCount = (popCount == 5'd16) ? 5'd0 : popCount;

    // =========================================================================
    // Pass-through signals (no transformation needed)
    // =========================================================================
    assign m_tvalid = s_tvalid;
    assign m_tlast  = s_tlast;
    assign s_tready = m_tready;

endmodule
