`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: gcm_axi_decrypt
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: AXI-Stream decrypt wrapper for AES-GCM-256. Accepts an
//              encrypted byte stream (IV + CT + Tag), parses it, drives
//              the core in decrypt mode, and outputs plaintext bytes with
//              authentication result.
//
//              Incoming packet format (per Section 4.2):
//                Bytes 0-11:                 IV (12 bytes)
//                Bytes 12 to totalLen-17:    Ciphertext (N bytes)
//                Final 16 bytes:             Tag (16 bytes)
//
//              The core's tag_in is set to 0 at start (since the tag
//              arrives last). After core completes, the wrapper compares
//              the core's computed tag against the parser-extracted tag.
//
// Dependencies: gcm_axi_config, gcm_rx_parser, axis_dwidth_converter_0,
//               gcm_rx_shim, aes_gcm_256, gcm_pt_serializer
//
//////////////////////////////////////////////////////////////////////////////////

module gcm_axi_decrypt (
    input wire         clk,
    input wire         rst,

    // Key AXI-Stream (32 bytes, MSB-first)
    input wire [7:0]   key_axis_tdata,
    input wire         key_axis_tvalid,
    output wire        key_axis_tready,
    input wire         key_axis_tlast,

    // RX header (from Ethernet stack)
    input wire         rx_hdr_valid,
    input wire [15:0]  rx_payload_len,   // Total encrypted payload (IV+CT+Tag)
    output wire        rx_hdr_ready,

    // RX payload AXI-Stream (8-bit, encrypted bytes from Ethernet stack)
    input wire [7:0]   rx_payload_tdata,
    input wire         rx_payload_tvalid,
    output wire        rx_payload_tready,
    input wire         rx_payload_tlast,

    // TX header (plaintext output to downstream)
    output wire        tx_hdr_valid,
    output wire [15:0] tx_payload_len,
    input wire         tx_hdr_ready,

    // TX payload AXI-Stream (8-bit, plaintext bytes)
    output wire [7:0]  tx_payload_tdata,
    output wire        tx_payload_tvalid,
    input wire         tx_payload_tready,
    output wire        tx_payload_tlast,

    // Status
    output wire        keyError,
    output wire        decBusy,
    output reg         decDone,        // Pulses 1 cycle when complete
    output reg         authOk,         // Valid on decDone: tags match
    output reg         authFail        // Valid on decDone: tags mismatch
);

    // =========================================================================
    // Sequencing FSM States
    // =========================================================================
    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_WAIT_IV    = 4'd1;
    localparam [3:0] ST_CORE_START = 4'd2;
    localparam [3:0] ST_INIT_WAIT  = 4'd3;
    localparam [3:0] ST_PULL_DATA  = 4'd4;
    localparam [3:0] ST_FEED       = 4'd5;
    localparam [3:0] ST_WAIT_PT    = 4'd6;
    localparam [3:0] ST_PUSH_PT    = 4'd7;
    localparam [3:0] ST_GHASH_WAIT = 4'd8;
    localparam [3:0] ST_FINALIZE   = 4'd9;
    localparam [3:0] ST_WAIT_DONE  = 4'd10;
    localparam [3:0] ST_WAIT_TX    = 4'd11;
    localparam [3:0] ST_PKT_DONE   = 4'd12;

    localparam [7:0] INIT_DELAY  = 8'd25;
    localparam [7:0] GHASH_DELAY = 8'd140;

    // =========================================================================
    // FSM Registers
    // =========================================================================
    reg [3:0]   fsmState;
    reg [15:0]  totalLenReg;
    reg [127:0] ptCapture;       // Captured plaintext block
    reg [127:0] tagCapture;      // Core's computed tag
    reg [127:0] blkData;         // Block from shim
    reg [4:0]   blkBytes;
    reg         blkLast;
    reg [7:0]   waitCnt;
    reg         tagExtracted;    // Set when parser's tagReady pulses

    // =========================================================================
    // Internal Wires — Config
    // =========================================================================
    wire [255:0] keyOut;
    wire [95:0]  cfgIvOut;       // Unused — IV from parser
    wire         coreIdle;

    // =========================================================================
    // Internal Wires — Parser
    // =========================================================================
    wire [95:0]  parsedIv;
    wire         ivReady;
    wire [127:0] parsedTag;
    wire         parsedTagReady;
    wire [15:0]  ctLen;
    wire         parserBusy;
    wire         parserDone;
    wire [7:0]   parserCtData;
    wire         parserCtValid;
    wire         parserCtReady;
    wire         parserCtTlast;

    // =========================================================================
    // Internal Wires — Width Converter → Shim
    // =========================================================================
    wire [127:0] wc_m_tdata;
    wire [15:0]  wc_m_tkeep;
    wire         wc_m_tvalid;
    wire         wc_m_tready;
    wire         wc_m_tlast;

    // =========================================================================
    // Internal Wires — Shim → FSM
    // =========================================================================
    wire [127:0] shim_m_tdata;
    wire         shim_m_tvalid;
    wire         shim_m_tready;
    wire         shim_m_tlast;
    wire [4:0]   shim_m_byteCount;

    // =========================================================================
    // Internal Wires — Core
    // =========================================================================
    wire         coreBusy;
    wire         coreDone;
    wire [127:0] corePtOut;      // ct_out port = plaintext in decrypt mode
    wire         corePtValid;    // ct_valid = plaintext valid
    wire [127:0] coreTag;

    // =========================================================================
    // Internal Wires — PT Serializer
    // =========================================================================
    wire         ptSerBusy;
    wire         ptSerDone;
    wire         ptSerReady;

    // =========================================================================
    // Combinational Control
    // =========================================================================
    assign coreIdle     = !coreBusy;
    assign decBusy      = (fsmState != ST_IDLE);
    assign rx_hdr_ready = (fsmState == ST_IDLE) && !ptSerBusy;

    // Parser start: registered pulse from FSM (avoids XSim evaluation-order
    // race with combinational wire that depends on fsmState)
    reg parserStartReg;

    // Shim tready: pull blocks in ST_PULL_DATA
    assign shim_m_tready = (fsmState == ST_PULL_DATA);

    // Core control
    wire coreStart    = (fsmState == ST_CORE_START);
    wire corePtFeed   = (fsmState == ST_FEED);
    wire coreFinalize = (fsmState == ST_FINALIZE);

    // PT serializer control
    wire ptSerStart  = (fsmState == ST_CORE_START);
    wire ptSerPush   = (fsmState == ST_PUSH_PT);

    // Active-low reset for Vivado IP
    wire aresetn = ~rst;

    // =========================================================================
    // Config Module (key management only — IV from parser)
    // =========================================================================
    gcm_axi_config u_config (
        .clk              (clk),
        .rst              (rst),
        .key_axis_tdata   (key_axis_tdata),
        .key_axis_tvalid  (key_axis_tvalid),
        .key_axis_tready  (key_axis_tready),
        .key_axis_tlast   (key_axis_tlast),
        .iv_axis_tdata    (8'd0),
        .iv_axis_tvalid   (1'b0),
        .iv_axis_tready   (),
        .iv_axis_tlast    (1'b0),
        .coreIdle         (coreIdle),
        .pktDone          (1'b0),        // No IV auto-increment in decrypt
        .keyOut           (keyOut),
        .ivOut            (cfgIvOut),
        .keyUpdated       (),
        .ivUpdated        (),
        .keyError         (keyError),
        .ivError          ()
    );

    // =========================================================================
    // RX Parser (separates IV, CT bytes, and tag)
    // =========================================================================
    gcm_rx_parser u_parser (
        .clk        (clk),
        .rst        (rst),
        .pktStart   (parserStartReg),
        .totalLen   (rx_payload_len),
        .rx_tdata   (rx_payload_tdata),
        .rx_tvalid  (rx_payload_tvalid),
        .rx_tready  (rx_payload_tready),
        .ct_tdata   (parserCtData),
        .ct_tvalid  (parserCtValid),
        .ct_tready  (parserCtReady),
        .ct_tlast   (parserCtTlast),
        .ivOut      (parsedIv),
        .ivReady    (ivReady),
        .tagOut     (parsedTag),
        .tagReady   (parsedTagReady),
        .ctLen      (ctLen),
        .parserBusy (parserBusy),
        .parserDone (parserDone)
    );

    // =========================================================================
    // Width Converter (CT bytes 8→128 bit)
    // =========================================================================
    axis_dwidth_converter_0 u_wc (
        .aclk            (clk),
        .aresetn         (aresetn),
        .s_axis_tdata    (parserCtData),
        .s_axis_tkeep    (1'b1),
        .s_axis_tvalid   (parserCtValid),
        .s_axis_tready   (parserCtReady),
        .s_axis_tlast    (parserCtTlast),
        .m_axis_tdata    (wc_m_tdata),
        .m_axis_tkeep    (wc_m_tkeep),
        .m_axis_tvalid   (wc_m_tvalid),
        .m_axis_tready   (wc_m_tready),
        .m_axis_tlast    (wc_m_tlast)
    );

    // =========================================================================
    // Byte-Order Shim (AXI LE → GCM BE)
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
    // AES-GCM-256 Core (decrypt mode)
    // =========================================================================
    aes_gcm_256 u_core (
        .clk       (clk),
        .rst       (rst),
        .start     (coreStart),
        .mode      (1'b1),            // Decrypt
        .busy      (coreBusy),
        .done      (coreDone),
        .key       (keyOut),
        .iv        (parsedIv),        // IV from parser, not config
        .aad_in    (128'd0),
        .aad_valid (1'b0),
        .aad_len   (5'd0),
        .aad_last  (1'b0),
        .pt_in     (blkData),         // CT input (named pt_in in core)
        .pt_valid  (corePtFeed),
        .pt_len    (blkBytes),
        .pt_last   (blkLast),
        .finalize  (coreFinalize),
        .ct_out    (corePtOut),       // PT output (named ct_out in core)
        .ct_valid  (corePtValid),
        .tag       (coreTag),
        .tag_in    (128'd0),          // Compared manually after done
        .tag_match (),
        .auth_fail ()
    );

    // =========================================================================
    // PT Serializer (plaintext blocks → byte output)
    // =========================================================================
    gcm_pt_serializer u_pt_ser (
        .clk              (clk),
        .rst              (rst),
        .txStart          (ptSerStart),
        .txPtLen          (ctLen),
        .txPtBlock        (ptCapture),
        .txPtValid        (ptSerPush),
        .txPtBytes        (blkBytes),
        .txPtLast         (blkLast),
        .txBusy           (ptSerBusy),
        .txDone           (ptSerDone),
        .txPtReady        (ptSerReady),
        .tx_hdr_valid     (tx_hdr_valid),
        .tx_payload_len   (tx_payload_len),
        .tx_hdr_ready     (tx_hdr_ready),
        .tx_payload_tdata (tx_payload_tdata),
        .tx_payload_tvalid(tx_payload_tvalid),
        .tx_payload_tready(tx_payload_tready),
        .tx_payload_tlast (tx_payload_tlast)
    );

    // =========================================================================
    // Capture tagReady pulse (may arrive while FSM is busy)
    // =========================================================================
    always @(posedge clk) begin
        if (rst)
            tagExtracted <= 1'b0;
        else if (fsmState == ST_IDLE)
            tagExtracted <= 1'b0;
        else if (parsedTagReady)
            tagExtracted <= 1'b1;
    end

    // =========================================================================
    // Sequencing FSM
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            fsmState       <= ST_IDLE;
            totalLenReg    <= 16'd0;
            blkData        <= 128'd0;
            blkBytes       <= 5'd0;
            blkLast        <= 1'b0;
            ptCapture      <= 128'd0;
            tagCapture     <= 128'd0;
            waitCnt        <= 8'd0;
            parserStartReg <= 1'b0;
            decDone        <= 1'b0;
            authOk         <= 1'b0;
            authFail       <= 1'b0;
        end
        else begin
            decDone        <= 1'b0;
            authOk         <= 1'b0;
            authFail       <= 1'b0;
            parserStartReg <= 1'b0;

            case (fsmState)
                // ---------------------------------------------------------
                ST_IDLE: begin
                    if (rx_hdr_valid && rx_hdr_ready) begin
                        totalLenReg    <= rx_payload_len;
                        parserStartReg <= 1'b1;
                        fsmState       <= ST_WAIT_IV;
                    end
                end

                // ---------------------------------------------------------
                // Wait for parser to extract 12-byte IV
                // ---------------------------------------------------------
                ST_WAIT_IV: begin
                    if (ivReady) begin
                        fsmState <= ST_CORE_START;
                    end
                end

                // ---------------------------------------------------------
                // Start core (decrypt mode) and PT serializer
                // ---------------------------------------------------------
                ST_CORE_START: begin
                    waitCnt  <= 8'd0;
                    fsmState <= ST_INIT_WAIT;
                end

                // ---------------------------------------------------------
                // Wait for H computation + GHASH init
                // ---------------------------------------------------------
                ST_INIT_WAIT: begin
                    if (waitCnt == INIT_DELAY) begin
                        if (ctLen == 16'd0)
                            fsmState <= ST_FINALIZE;
                        else
                            fsmState <= ST_PULL_DATA;
                    end
                    else begin
                        waitCnt <= waitCnt + 8'd1;
                    end
                end

                // ---------------------------------------------------------
                // Pull next 128-bit CT block from shim
                // ---------------------------------------------------------
                ST_PULL_DATA: begin
                    if (shim_m_tvalid) begin
                        blkData  <= shim_m_tdata;
                        blkBytes <= shim_m_byteCount;
                        blkLast  <= shim_m_tlast;
                        fsmState <= ST_FEED;
                    end
                end

                // ---------------------------------------------------------
                // Feed block to core (pulse pt_valid)
                // ---------------------------------------------------------
                ST_FEED: begin
                    fsmState <= ST_WAIT_PT;
                end

                // ---------------------------------------------------------
                // Wait for core plaintext output
                // ---------------------------------------------------------
                ST_WAIT_PT: begin
                    if (corePtValid) begin
                        ptCapture <= corePtOut;
                        fsmState  <= ST_PUSH_PT;
                    end
                end

                // ---------------------------------------------------------
                // Push PT block to serializer
                // ---------------------------------------------------------
                ST_PUSH_PT: begin
                    if (ptSerReady) begin
                        waitCnt <= 8'd0;
                        if (blkLast)
                            fsmState <= ST_WAIT_DONE;
                        else
                            fsmState <= ST_GHASH_WAIT;
                    end
                end

                // ---------------------------------------------------------
                // Wait for GHASH processing between blocks
                // ---------------------------------------------------------
                ST_GHASH_WAIT: begin
                    if (waitCnt == GHASH_DELAY) begin
                        fsmState <= ST_PULL_DATA;
                    end
                    else begin
                        waitCnt <= waitCnt + 8'd1;
                    end
                end

                // ---------------------------------------------------------
                // Finalize (zero-CT case)
                // ---------------------------------------------------------
                ST_FINALIZE: begin
                    fsmState <= ST_WAIT_DONE;
                end

                // ---------------------------------------------------------
                // Wait for core done, capture computed tag
                // ---------------------------------------------------------
                ST_WAIT_DONE: begin
                    if (coreDone) begin
                        tagCapture <= coreTag;
                        fsmState   <= ST_WAIT_TX;
                    end
                end

                // ---------------------------------------------------------
                // Wait for PT serializer to finish outputting bytes
                // ---------------------------------------------------------
                ST_WAIT_TX: begin
                    if (ptSerDone || !ptSerBusy) begin
                        fsmState <= ST_PKT_DONE;
                    end
                end

                // ---------------------------------------------------------
                // Compare tags, report result, return to idle
                // ---------------------------------------------------------
                ST_PKT_DONE: begin
                    decDone  <= 1'b1;
                    authOk   <= (tagCapture == parsedTag);
                    authFail <= (tagCapture != parsedTag);
                    fsmState <= ST_IDLE;
                end

                default: fsmState <= ST_IDLE;
            endcase
        end
    end

endmodule
