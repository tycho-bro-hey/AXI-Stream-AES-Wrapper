`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: gcm_axi_top
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Top-level AXI-Stream encrypt wrapper. Integrates the Vivado
//              axis_dwidth_converter IP (8→128 bit), byte-order shim, and
//              gcm_axi_encrypt into a single module with byte-serial RX/TX
//              interfaces matching the coworker's Ethernet stack.
//
//              External ports use the naming conventions from Project Context
//              Sections 7 (TX) and 8 (Key/IV), plus the proposed RX interface.
//
// Dependencies: axis_dwidth_converter_0 (Vivado IP),
//               gcm_rx_shim, gcm_axi_encrypt,
//               gcm_axi_config, gcm_tx_serializer,
//               aes_gcm_256 and all crypto core submodules
//
//////////////////////////////////////////////////////////////////////////////////

module gcm_axi_top (
    input wire         clk,
    input wire         rst,              // Active-high synchronous reset

    // Key AXI-Stream (32 bytes, MSB-first)
    input wire [7:0]   key_axis_tdata,
    input wire         key_axis_tvalid,
    output wire        key_axis_tready,
    input wire         key_axis_tlast,

    // IV Seed AXI-Stream (12 bytes, MSB-first)
    input wire [7:0]   iv_axis_tdata,
    input wire         iv_axis_tvalid,
    output wire        iv_axis_tready,
    input wire         iv_axis_tlast,

    // RX header (from Ethernet stack → wrapper)
    input wire         rx_hdr_valid,
    input wire [15:0]  rx_payload_len,   // Plaintext byte count
    output wire        rx_hdr_ready,

    // RX payload AXI-Stream (8-bit, from Ethernet stack → wrapper)
    input wire [7:0]   rx_payload_tdata,
    input wire         rx_payload_tvalid,
    output wire        rx_payload_tready,
    input wire         rx_payload_tlast,

    // TX header (wrapper → Ethernet stack)
    output wire        tx_hdr_valid,
    output wire [15:0] tx_payload_len,   // 12 + N + 16
    input wire         tx_hdr_ready,

    // TX payload AXI-Stream (8-bit, wrapper → Ethernet stack)
    output wire [7:0]  tx_payload_tdata,
    output wire        tx_payload_tvalid,
    input wire         tx_payload_tready,
    output wire        tx_payload_tlast,

    // Status
    output wire        keyError,
    output wire        ivError,
    output wire        encBusy,
    output wire        encDone
);

    // =========================================================================
    // Internal wires: width converter → shim
    // =========================================================================
    wire [127:0] wc_m_tdata;
    wire [15:0]  wc_m_tkeep;
    wire         wc_m_tvalid;
    wire         wc_m_tready;
    wire         wc_m_tlast;

    // =========================================================================
    // Internal wires: shim → encrypt wrapper
    // =========================================================================
    wire [127:0] shim_m_tdata;
    wire         shim_m_tvalid;
    wire         shim_m_tready;
    wire         shim_m_tlast;
    wire [4:0]   shim_m_byteCount;

    // =========================================================================
    // Active-low reset for Vivado IP
    // =========================================================================
    wire aresetn;
    assign aresetn = ~rst;

    // =========================================================================
    // Vivado axis_dwidth_converter IP (8-bit → 128-bit)
    // =========================================================================
    axis_dwidth_converter_0 u_wc (
        .aclk            (clk),
        .aresetn         (aresetn),

        // Slave: 8-bit input from Ethernet RX payload
        .s_axis_tdata    (rx_payload_tdata),
        .s_axis_tkeep    (1'b1),              // Single byte always valid
        .s_axis_tvalid   (rx_payload_tvalid),
        .s_axis_tready   (rx_payload_tready),
        .s_axis_tlast    (rx_payload_tlast),

        // Master: 128-bit output to shim
        .m_axis_tdata    (wc_m_tdata),
        .m_axis_tkeep    (wc_m_tkeep),
        .m_axis_tvalid   (wc_m_tvalid),
        .m_axis_tready   (wc_m_tready),
        .m_axis_tlast    (wc_m_tlast)
    );

    // =========================================================================
    // Byte-order shim (AXI little-endian → GCM big-endian)
    // =========================================================================
    gcm_rx_shim u_shim (
        .s_tdata     (wc_m_tdata),
        .s_tkeep     (wc_m_tkeep),
        .s_tvalid    (wc_m_tvalid),
        .s_tlast     (wc_m_tlast),
        .s_tready    (wc_m_tready),

        .m_tdata     (shim_m_tdata),
        .m_tvalid    (shim_m_tvalid),
        .m_tlast     (shim_m_tlast),
        .m_tready    (shim_m_tready),
        .m_byteCount (shim_m_byteCount)
    );

    // =========================================================================
    // Encrypt wrapper (config + sequencing FSM + core + TX serializer)
    // =========================================================================
    gcm_axi_encrypt u_enc (
        .clk              (clk),
        .rst              (rst),

        .key_axis_tdata   (key_axis_tdata),
        .key_axis_tvalid  (key_axis_tvalid),
        .key_axis_tready  (key_axis_tready),
        .key_axis_tlast   (key_axis_tlast),

        .iv_axis_tdata    (iv_axis_tdata),
        .iv_axis_tvalid   (iv_axis_tvalid),
        .iv_axis_tready   (iv_axis_tready),
        .iv_axis_tlast    (iv_axis_tlast),

        .rx_hdr_valid     (rx_hdr_valid),
        .rx_payload_len   (rx_payload_len),
        .rx_hdr_ready     (rx_hdr_ready),

        .rxBlk_tdata      (shim_m_tdata),
        .rxBlk_tvalid     (shim_m_tvalid),
        .rxBlk_tready     (shim_m_tready),
        .rxBlk_tlast      (shim_m_tlast),
        .rxBlk_byteCount  (shim_m_byteCount),

        .tx_hdr_valid     (tx_hdr_valid),
        .tx_payload_len   (tx_payload_len),
        .tx_hdr_ready     (tx_hdr_ready),
        .tx_payload_tdata (tx_payload_tdata),
        .tx_payload_tvalid(tx_payload_tvalid),
        .tx_payload_tready(tx_payload_tready),
        .tx_payload_tlast (tx_payload_tlast),

        .keyError         (keyError),
        .ivError          (ivError),
        .encBusy          (encBusy),
        .encDone          (encDone)
    );

endmodule
