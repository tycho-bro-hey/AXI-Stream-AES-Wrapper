`timescale 1ns / 1ps
//
// module: aes_gcm_256_axis_top
// project: aes-gcm-256 for arty a7-100t
//
// top-level axi-stream wrapper for aes-gcm-256 encrypt pipeline.
// wires together all custom modules and vivado ip cores:
//
//   rx payload (8-bit) -> axis_upsizer -> byte-swap -> core adapter
//     -> byte-swap -> axis_downsizer -> tx_stream_composer
//     -> tx_header_bridge -> tx interface
//
//   key_loader -> adapter.key
//   iv_loader  -> adapter.iv, composer.iv
//
// byte order: vivado ip uses axi convention (byte 0 at tdata[7:0]).
// the aes core uses network order (byte 0 at tdata[127:120]).
// byte-swap and tkeep-reverse are inserted at both boundaries.
//
// tx payload length is pre-computed from rx_payload_len + 28
// (12 iv + pt_len + 16 tag) rather than waiting for the composer.
//
// vivado ip uses aresetn (active-low); custom modules use rst
// (active-high). rst is inverted for ip instances.
//
// dependencies: key_loader, iv_loader, axis_upsizer (vivado ip),
//   axis_downsizer (vivado ip), aes_gcm_core_adapter,
//   tx_stream_composer, tx_header_bridge
//

module aes_gcm_256_axis_top (
    input wire clk,
    input wire rst,

    // key axi-stream (8-bit, 32 bytes)
    input wire [7:0] key_axis_tdata,
    input wire key_axis_tvalid,
    output wire key_axis_tready,
    input wire key_axis_tlast,

    // iv seed axi-stream (8-bit, 12 bytes)
    input wire [7:0] iv_axis_tdata,
    input wire iv_axis_tvalid,
    output wire iv_axis_tready,
    input wire iv_axis_tlast,

    // rx header handshake (from ethernet stack)
    input wire rx_hdr_valid,
    input wire [15:0] rx_payload_len,
    output wire rx_hdr_ready,

    // rx payload axi-stream (8-bit, from ethernet stack)
    input wire [7:0] rx_payload_tdata,
    input wire rx_payload_tvalid,
    output wire rx_payload_tready,
    input wire rx_payload_tlast,

    // tx header handshake (to ethernet stack)
    output wire tx_hdr_valid,
    input wire tx_hdr_ready,
    output wire [15:0] tx_payload_len,

    // tx payload axi-stream (to ethernet stack)
    output wire [7:0] tx_payload_tdata,
    output wire tx_payload_tvalid,
    input wire tx_payload_tready,
    output wire tx_payload_tlast,

    // status/error
    output wire encBusy,
    output wire keyLoadErr,
    output wire ivLoadErr
);

    // vivado ip uses active-low reset
    wire rstN = ~rst;

    // byte-swap 128-bit word (axi byte 0 at [7:0] <-> core byte 0 at [127:120])
    function [127:0] byteSwap128;
        input [127:0] din;
        integer b;
    begin
        for (b = 0; b < 16; b = b + 1)
            byteSwap128[b*8 +: 8] = din[(15-b)*8 +: 8];
    end
    endfunction

    // bit-reverse 16-bit tkeep (axi bit 0 = byte 0 <-> core bit 15 = byte 0)
    function [15:0] bitReverse16;
        input [15:0] din;
        integer b;
    begin
        for (b = 0; b < 16; b = b + 1)
            bitReverse16[b] = din[15-b];
    end
    endfunction

    // internal wires: key and iv registers
    wire [255:0] keyReg;
    wire [95:0] ivReg;

    // internal wires: upsizer output (axi byte order)
    wire [127:0] up_tdata;
    wire up_tvalid;
    wire up_tready;
    wire up_tlast;
    wire [15:0] up_tkeep;

    // byte-swapped upsizer output (core byte order) for adapter
    wire [127:0] up_tdata_swap = byteSwap128(up_tdata);
    wire [15:0] up_tkeep_swap = bitReverse16(up_tkeep);

    // internal wires: adapter ct output (core byte order)
    wire [127:0] ct_tdata;
    wire ct_tvalid;
    wire ct_tready;
    wire ct_tlast;
    wire [15:0] ct_tkeep;

    // byte-swapped adapter output (axi byte order) for downsizer
    wire [127:0] ct_tdata_swap = byteSwap128(ct_tdata);
    wire [15:0] ct_tkeep_swap = bitReverse16(ct_tkeep);

    // internal wires: downsizer output -> composer input
    wire [7:0] down_tdata;
    wire down_tvalid;
    wire down_tready;
    wire down_tlast;

    // internal wires: composer output -> bridge input
    wire [7:0] comp_tdata;
    wire comp_tvalid;
    wire comp_tready;
    wire comp_tlast;

    // internal wires: adapter tag sideband
    wire [127:0] tagOut;
    wire tagValid;

    // internal wires: composer payload length (not used by bridge)
    wire [15:0] composerPayloadLen;

    // tx payload length: pre-computed from rx header
    // 12 iv bytes + plaintext length + 16 tag bytes = rx_payload_len + 28
    reg [15:0] txPayloadLenReg;

    always @(posedge clk) begin
        if (rst)
            txPayloadLenReg <= 16'd0;
        else if (rx_hdr_valid && rx_hdr_ready)
            txPayloadLenReg <= rx_payload_len + 16'd28;
    end

    // rx header: accept when crypto core is idle
    assign rx_hdr_ready = !encBusy;

    // key loader
    key_loader u_key_loader (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(key_axis_tdata),
        .s_axis_tvalid(key_axis_tvalid),
        .s_axis_tready(key_axis_tready),
        .s_axis_tlast(key_axis_tlast),
        .keyReg(keyReg),
        .encBusy(encBusy),
        .loadErr(keyLoadErr)
    );

    // iv loader (pkt-done from adapter tag-valid for auto-increment)
    iv_loader u_iv_loader (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(iv_axis_tdata),
        .s_axis_tvalid(iv_axis_tvalid),
        .s_axis_tready(iv_axis_tready),
        .s_axis_tlast(iv_axis_tlast),
        .ivReg(ivReg),
        .encBusy(encBusy),
        .pktDone(tagValid),
        .loadErr(ivLoadErr)
    );

    // vivado ip: 8-bit -> 128-bit width converter (upsizer)
    axis_upsizer u_upsizer (
        .aclk(clk),
        .aresetn(rstN),
        .s_axis_tdata(rx_payload_tdata),
        .s_axis_tvalid(rx_payload_tvalid),
        .s_axis_tready(rx_payload_tready),
        .s_axis_tlast(rx_payload_tlast),
        .s_axis_tkeep(1'b1),
        .m_axis_tdata(up_tdata),
        .m_axis_tvalid(up_tvalid),
        .m_axis_tready(up_tready),
        .m_axis_tlast(up_tlast),
        .m_axis_tkeep(up_tkeep)
    );

    // aes-gcm-256 core adapter (byte-swapped interfaces)
    aes_gcm_core_adapter u_adapter (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(up_tdata_swap),
        .s_axis_tvalid(up_tvalid),
        .s_axis_tready(up_tready),
        .s_axis_tlast(up_tlast),
        .s_axis_tkeep(up_tkeep_swap),
        .m_axis_tdata(ct_tdata),
        .m_axis_tvalid(ct_tvalid),
        .m_axis_tready(ct_tready),
        .m_axis_tlast(ct_tlast),
        .m_axis_tkeep(ct_tkeep),
        .key(keyReg),
        .iv(ivReg),
        .tagOut(tagOut),
        .tagValid(tagValid),
        .encBusy(encBusy)
    );

    // vivado ip: 128-bit -> 8-bit width converter (downsizer)
    // fed with byte-swapped ct data (core order -> axi order)
    wire down_tkeep;

    axis_downsizer u_downsizer (
        .aclk(clk),
        .aresetn(rstN),
        .s_axis_tdata(ct_tdata_swap),
        .s_axis_tvalid(ct_tvalid),
        .s_axis_tready(ct_tready),
        .s_axis_tlast(ct_tlast),
        .s_axis_tkeep(ct_tkeep_swap),
        .m_axis_tdata(down_tdata),
        .m_axis_tvalid(down_tvalid),
        .m_axis_tready(down_tready),
        .m_axis_tlast(down_tlast),
        .m_axis_tkeep(down_tkeep)
    );

    // tx stream composer: iv(12b) + ct(nb) + tag(16b)
    tx_stream_composer u_composer (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(down_tdata),
        .s_axis_tvalid(down_tvalid),
        .s_axis_tready(down_tready),
        .s_axis_tlast(down_tlast),
        .m_axis_tdata(comp_tdata),
        .m_axis_tvalid(comp_tvalid),
        .m_axis_tready(comp_tready),
        .m_axis_tlast(comp_tlast),
        .iv(ivReg),
        .tag(tagOut),
        .tagValid(tagValid),
        .payloadLen(composerPayloadLen)
    );

    // tx header bridge: axi-stream -> coworker's tx protocol
    // uses pre-computed payload length instead of composer output
    tx_header_bridge u_bridge (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(comp_tdata),
        .s_axis_tvalid(comp_tvalid),
        .s_axis_tready(comp_tready),
        .s_axis_tlast(comp_tlast),
        .payloadLen(txPayloadLenReg),
        .tx_hdr_valid(tx_hdr_valid),
        .tx_hdr_ready(tx_hdr_ready),
        .tx_payload_len(tx_payload_len),
        .tx_payload_tdata(tx_payload_tdata),
        .tx_payload_tvalid(tx_payload_tvalid),
        .tx_payload_tready(tx_payload_tready),
        .tx_payload_tlast(tx_payload_tlast)
    );

endmodule
