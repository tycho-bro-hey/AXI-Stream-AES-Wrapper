`timescale 1ns / 1ps
//
// module: aes_gcm_256_axis_decrypt_top
// project: aes-gcm-256 for arty a7-100t
//
// top-level axi-stream wrapper for aes-gcm-256 decrypt pipeline.
//
//   rx payload (encrypted: iv+ct+tag)
//     -> rx_stream_parser (extracts iv, tag; passes ct through)
//       -> axis_upsizer (8->128) -> byte swap
//         -> aes_gcm_core_adapter (mode=1)
//           -> byte swap -> axis_downsizer (128->8)
//             -> axis_pt_fifo (buffers all pt bytes)
//               -> release gate (holds until auth verified)
//                 -> tx_header_bridge -> tx payload (plaintext)
//
// nist sp 800-38d compliance: plaintext is buffered in a fifo
// until tag verification completes. on auth pass, the gate opens
// and pt drains to the bridge. on auth fail, the fifo is flushed
// and no plaintext reaches the tx interface.
//
// dependencies: key_loader, rx_stream_parser, axis_upsizer (vivado ip),
//   axis_downsizer (vivado ip), axis_pt_fifo (vivado ip),
//   aes_gcm_core_adapter, tx_header_bridge
//

module aes_gcm_256_axis_decrypt_top (
    input wire clk,
    input wire rst,

    // key axi-stream (8-bit, 32 bytes)
    input wire [7:0] key_axis_tdata,
    input wire key_axis_tvalid,
    output wire key_axis_tready,
    input wire key_axis_tlast,

    // rx header handshake (encrypted packet from ethernet stack)
    input wire rx_hdr_valid,
    input wire [15:0] rx_payload_len,
    output wire rx_hdr_ready,

    // rx payload axi-stream (8-bit, encrypted: iv+ct+tag)
    input wire [7:0] rx_payload_tdata,
    input wire rx_payload_tvalid,
    output wire rx_payload_tready,
    input wire rx_payload_tlast,

    // tx header handshake (plaintext to ethernet stack)
    output wire tx_hdr_valid,
    input wire tx_hdr_ready,
    output wire [15:0] tx_payload_len,

    // tx payload axi-stream (plaintext to ethernet stack)
    output wire [7:0] tx_payload_tdata,
    output wire tx_payload_tvalid,
    input wire tx_payload_tready,
    output wire tx_payload_tlast,

    // status/error
    output wire decBusy,
    output wire keyLoadErr,
    output wire authFail
);

    // vivado ip uses active-low reset
    wire rstN = ~rst;

    // byte-swap functions (axi byte 0 at [7:0] <-> core byte 0 at [127:120])
    function [127:0] byteSwap128;
        input [127:0] din;
        integer b;
    begin
        for (b = 0; b < 16; b = b + 1)
            byteSwap128[b*8 +: 8] = din[(15-b)*8 +: 8];
    end
    endfunction

    function [15:0] bitReverse16;
        input [15:0] din;
        integer b;
    begin
        for (b = 0; b < 16; b = b + 1)
            bitReverse16[b] = din[15-b];
    end
    endfunction

    // key register
    wire [255:0] keyReg;

    // parser outputs
    wire [95:0] parsedIv;
    wire parsedIvValid;
    wire [127:0] parsedTag;
    wire parsedTagValid;

    // parser -> upsizer (ct bytes)
    wire [7:0] ct_byte_tdata;
    wire ct_byte_tvalid;
    wire ct_byte_tready;
    wire ct_byte_tlast;

    // upsizer output (axi byte order)
    wire [127:0] up_tdata;
    wire up_tvalid;
    wire up_tready;
    wire up_tlast;
    wire [15:0] up_tkeep;

    // byte-swapped for adapter
    wire [127:0] up_tdata_swap = byteSwap128(up_tdata);
    wire [15:0] up_tkeep_swap = bitReverse16(up_tkeep);

    // adapter output (core byte order)
    wire [127:0] pt_tdata;
    wire pt_tvalid;
    wire pt_tready;
    wire pt_tlast;
    wire [15:0] pt_tkeep;

    // byte-swapped for downsizer
    wire [127:0] pt_tdata_swap = byteSwap128(pt_tdata);
    wire [15:0] pt_tkeep_swap = bitReverse16(pt_tkeep);

    // downsizer output -> fifo input
    wire [7:0] down_tdata;
    wire down_tvalid;
    wire down_tready;
    wire down_tlast;
    wire down_tkeep;

    // fifo output (before gate)
    wire [7:0] fifo_m_tdata;
    wire fifo_m_tvalid;
    wire fifo_m_tready;
    wire fifo_m_tlast;

    // gated fifo output -> bridge input
    wire [7:0] gated_tdata;
    wire gated_tvalid;
    wire gated_tready;
    wire gated_tlast;

    // adapter sideband
    wire [127:0] adapterTagOut;
    wire adapterTagValid;
    wire adapterTagMatch;
    wire adapterAuthFail;

    // plaintext length = encrypted_len - 28 (12 iv + 16 tag)
    reg [15:0] ptLenReg;

    always @(posedge clk) begin
        if (rst)
            ptLenReg <= 16'd0;
        else if (rx_hdr_valid && rx_hdr_ready)
            ptLenReg <= rx_payload_len - 16'd28;
    end

    // auth result latch (hold until next packet)
    reg authFailReg;

    always @(posedge clk) begin
        if (rst)
            authFailReg <= 1'b0;
        else if (rx_hdr_valid && rx_hdr_ready)
            authFailReg <= 1'b0;
        else if (adapterTagValid)
            authFailReg <= adapterAuthFail;
    end

    assign authFail = authFailReg;

    // plaintext release gate
    // pt_released: set when auth passes, cleared on new packet or reset
    // pt_flush: single-cycle pulse to reset fifo on auth failure
    reg ptReleased;
    reg ptFlush;

    always @(posedge clk) begin
        if (rst) begin
            ptReleased <= 1'b0;
            ptFlush <= 1'b0;
        end
        else begin
            ptFlush <= 1'b0; // default: no flush

            if (rx_hdr_valid && rx_hdr_ready) begin
                // new packet starting, close gate
                ptReleased <= 1'b0;
            end
            else if (adapterTagValid) begin
                if (!adapterAuthFail) begin
                    // auth passed: open gate, release buffered pt
                    ptReleased <= 1'b1;
                end
                else begin
                    // auth failed: flush fifo, discard all pt
                    ptFlush <= 1'b1;
                end
            end
        end
    end

    // fifo reset: normal reset or auth-fail flush
    wire fifoRstN = rstN & ~ptFlush;

    // gate logic: mask fifo output until released
    assign gated_tdata = fifo_m_tdata;
    assign gated_tvalid = fifo_m_tvalid & ptReleased;
    assign gated_tlast = fifo_m_tlast;
    assign fifo_m_tready = gated_tready & ptReleased;

    // rx header: accept when not busy
    assign rx_hdr_ready = !decBusy;

    // key loader
    key_loader u_key_loader (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(key_axis_tdata),
        .s_axis_tvalid(key_axis_tvalid),
        .s_axis_tready(key_axis_tready),
        .s_axis_tlast(key_axis_tlast),
        .keyReg(keyReg),
        .encBusy(decBusy),
        .loadErr(keyLoadErr)
    );

    // rx stream parser: extract iv, pass ct, extract tag
    rx_stream_parser u_parser (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(rx_payload_tdata),
        .s_axis_tvalid(rx_payload_tvalid),
        .s_axis_tready(rx_payload_tready),
        .s_axis_tlast(rx_payload_tlast),
        .m_axis_tdata(ct_byte_tdata),
        .m_axis_tvalid(ct_byte_tvalid),
        .m_axis_tready(ct_byte_tready),
        .m_axis_tlast(ct_byte_tlast),
        .packetLen(rx_payload_len),
        .ivOut(parsedIv),
        .ivValid(parsedIvValid),
        .tagOut(parsedTag),
        .tagValid(parsedTagValid)
    );

    // vivado ip: 8-bit ct bytes -> 128-bit blocks (upsizer)
    axis_upsizer u_upsizer (
        .aclk(clk),
        .aresetn(rstN),
        .s_axis_tdata(ct_byte_tdata),
        .s_axis_tvalid(ct_byte_tvalid),
        .s_axis_tready(ct_byte_tready),
        .s_axis_tlast(ct_byte_tlast),
        .s_axis_tkeep(1'b1),
        .m_axis_tdata(up_tdata),
        .m_axis_tvalid(up_tvalid),
        .m_axis_tready(up_tready),
        .m_axis_tlast(up_tlast),
        .m_axis_tkeep(up_tkeep)
    );

    // aes-gcm-256 core adapter (decrypt mode)
    aes_gcm_core_adapter u_adapter (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(up_tdata_swap),
        .s_axis_tvalid(up_tvalid),
        .s_axis_tready(up_tready),
        .s_axis_tlast(up_tlast),
        .s_axis_tkeep(up_tkeep_swap),
        .m_axis_tdata(pt_tdata),
        .m_axis_tvalid(pt_tvalid),
        .m_axis_tready(pt_tready),
        .m_axis_tlast(pt_tlast),
        .m_axis_tkeep(pt_tkeep),
        .key(keyReg),
        .iv(parsedIv),
        .mode(1'b1),
        .tagIn(parsedTag),
        .tagOut(adapterTagOut),
        .tagValid(adapterTagValid),
        .tagMatch(adapterTagMatch),
        .authFail(adapterAuthFail),
        .encBusy(decBusy)
    );

    // vivado ip: 128-bit pt blocks -> 8-bit bytes (downsizer)
    axis_downsizer u_downsizer (
        .aclk(clk),
        .aresetn(rstN),
        .s_axis_tdata(pt_tdata_swap),
        .s_axis_tvalid(pt_tvalid),
        .s_axis_tready(pt_tready),
        .s_axis_tlast(pt_tlast),
        .s_axis_tkeep(pt_tkeep_swap),
        .m_axis_tdata(down_tdata),
        .m_axis_tvalid(down_tvalid),
        .m_axis_tready(down_tready),
        .m_axis_tlast(down_tlast),
        .m_axis_tkeep(down_tkeep)
    );

    // vivado ip: plaintext hold-off fifo
    // buffers all pt bytes until tag verification completes.
    // fifo reset is pulsed on auth failure to discard pt.
    axis_pt_fifo u_pt_fifo (
        .s_axis_aclk(clk),
        .s_axis_aresetn(fifoRstN),
        .s_axis_tdata(down_tdata),
        .s_axis_tvalid(down_tvalid),
        .s_axis_tready(down_tready),
        .s_axis_tlast(down_tlast),
        .m_axis_tdata(fifo_m_tdata),
        .m_axis_tvalid(fifo_m_tvalid),
        .m_axis_tready(fifo_m_tready),
        .m_axis_tlast(fifo_m_tlast)
    );

    // tx header bridge: gated pt bytes -> coworker's tx protocol
    tx_header_bridge u_bridge (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(gated_tdata),
        .s_axis_tvalid(gated_tvalid),
        .s_axis_tready(gated_tready),
        .s_axis_tlast(gated_tlast),
        .payloadLen(ptLenReg),
        .tx_hdr_valid(tx_hdr_valid),
        .tx_hdr_ready(tx_hdr_ready),
        .tx_payload_len(tx_payload_len),
        .tx_payload_tdata(tx_payload_tdata),
        .tx_payload_tvalid(tx_payload_tvalid),
        .tx_payload_tready(tx_payload_tready),
        .tx_payload_tlast(tx_payload_tlast)
    );

endmodule
