`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: gcm_axi_encrypt
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: AXI-Stream encrypt wrapper for AES-GCM-256. Integrates key/IV
//              configuration (gcm_axi_config), TX byte serializer
//              (gcm_tx_serializer), and the aes_gcm_256 core with a
//              sequencing FSM. Accepts 128-bit plaintext blocks (from an
//              external width converter), drives the core protocol, and
//              outputs byte-serial IV + ciphertext + tag per Section 7.
//
//              AAD is not used in the initial implementation (per §4.2).
//
//              The rxBlk interface expects big-endian byte order (MSB-first,
//              byte 0 in bits [127:120]) matching the core's convention.
//              A byte-reversal shim is needed between the Vivado
//              axis_dwidth_converter (AXI little-endian) and this module.
//
// Dependencies: gcm_axi_config, gcm_tx_serializer, aes_gcm_256
//
//////////////////////////////////////////////////////////////////////////////////

module gcm_axi_encrypt (
    input wire         clk,
    input wire         rst,

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

    // RX header (from Ethernet stack)
    input wire         rx_hdr_valid,
    input wire [15:0]  rx_payload_len,
    output wire        rx_hdr_ready,

    // RX data blocks (128-bit, big-endian byte order, from width converter shim)
    input wire [127:0] rxBlk_tdata,
    input wire         rxBlk_tvalid,
    output wire        rxBlk_tready,
    input wire         rxBlk_tlast,
    input wire [4:0]   rxBlk_byteCount, // Valid bytes: 1-16, 0 encodes 16

    // TX to Ethernet stack (Section 7)
    output wire        tx_hdr_valid,
    output wire [15:0] tx_payload_len,
    input wire         tx_hdr_ready,
    output wire [7:0]  tx_payload_tdata,
    output wire        tx_payload_tvalid,
    input wire         tx_payload_tready,
    output wire        tx_payload_tlast,

    // Status
    output wire        keyError,
    output wire        ivError,
    output wire        encBusy,
    output wire        encDone        // Pulses 1 cycle when packet complete
);

    // =========================================================================
    // Sequencing FSM States
    // =========================================================================
    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_START      = 4'd1;
    localparam [3:0] ST_INIT_WAIT  = 4'd2;
    localparam [3:0] ST_PULL_DATA  = 4'd3;
    localparam [3:0] ST_FEED       = 4'd4;
    localparam [3:0] ST_WAIT_CT    = 4'd5;
    localparam [3:0] ST_PUSH_CT    = 4'd6;
    localparam [3:0] ST_GHASH_WAIT = 4'd7;
    localparam [3:0] ST_FINALIZE   = 4'd8;
    localparam [3:0] ST_WAIT_DONE  = 4'd9;
    localparam [3:0] ST_PUSH_TAG   = 4'd10;
    localparam [3:0] ST_WAIT_TX    = 4'd11;
    localparam [3:0] ST_PKT_DONE   = 4'd12;

    // Fixed delays (in clock cycles)
    localparam [7:0] INIT_DELAY  = 8'd25;  // H computation + GHASH init
    localparam [7:0] GHASH_DELAY = 8'd140; // GHASH processing between blocks

    // =========================================================================
    // FSM Registers
    // =========================================================================
    reg [3:0]   fsmState;
    reg [15:0]  ptLenReg;       // Latched plaintext byte count
    reg [127:0] blkData;        // Latched block data from rxBlk
    reg [4:0]   blkBytes;       // Latched byte count from rxBlk
    reg         blkLast;        // Latched tlast from rxBlk
    reg [127:0] ctCapture;      // Captured ciphertext block from core
    reg [127:0] tagCapture;     // Captured authentication tag from core
    reg [7:0]   waitCnt;        // Delay counter

    // =========================================================================
    // Internal Wires — Config Module
    // =========================================================================
    wire [255:0] keyOut;
    wire [95:0]  ivOut;
    wire         keyUpdated;
    wire         ivUpdated;
    wire         coreIdle;
    wire         pktDonePulse;

    // =========================================================================
    // Internal Wires — Crypto Core
    // =========================================================================
    wire         coreBusy;
    wire         coreDone;
    wire [127:0] coreCtOut;
    wire         coreCtValid;
    wire [127:0] coreTag;

    // =========================================================================
    // Internal Wires — TX Serializer
    // =========================================================================
    wire         txSerBusy;
    wire         txSerDone;
    wire         txCtReady;
    wire         txTagReady;

    // =========================================================================
    // Combinational Control Signals
    // =========================================================================
    assign coreIdle     = !coreBusy;
    assign pktDonePulse = (fsmState == ST_PKT_DONE);
    assign encBusy      = (fsmState != ST_IDLE);
    assign encDone      = (fsmState == ST_PKT_DONE);

    // RX header handshake: accept when idle and TX serializer is not busy
    assign rx_hdr_ready = (fsmState == ST_IDLE) && !txSerBusy;

    // RX block handshake: pull data only in ST_PULL_DATA
    assign rxBlk_tready = (fsmState == ST_PULL_DATA);

    // Core control (single-cycle pulses from FSM state)
    wire coreStart    = (fsmState == ST_START);
    wire corePtValid  = (fsmState == ST_FEED);
    wire coreFinalize = (fsmState == ST_FINALIZE);

    // TX serializer control
    wire txStartPulse = (fsmState == ST_START);
    wire txCtValidW   = (fsmState == ST_PUSH_CT);
    wire txTagValidW  = (fsmState == ST_PUSH_TAG);

    // =========================================================================
    // Config Module Instance (Stage 1)
    // =========================================================================
    gcm_axi_config u_config (
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
        .coreIdle         (coreIdle),
        .pktDone          (pktDonePulse),
        .keyOut           (keyOut),
        .ivOut            (ivOut),
        .keyUpdated       (keyUpdated),
        .ivUpdated        (ivUpdated),
        .keyError         (keyError),
        .ivError          (ivError)
    );

    // =========================================================================
    // AES-GCM-256 Core Instance
    // =========================================================================
    aes_gcm_256 u_core (
        .clk       (clk),
        .rst       (rst),
        .start     (coreStart),
        .mode      (1'b0),            // Encrypt only
        .busy      (coreBusy),
        .done      (coreDone),
        .key       (keyOut),
        .iv        (ivOut),
        .aad_in    (128'd0),          // AAD unused (§4.2)
        .aad_valid (1'b0),
        .aad_len   (5'd0),
        .aad_last  (1'b0),
        .pt_in     (blkData),
        .pt_valid  (corePtValid),
        .pt_len    (blkBytes),
        .pt_last   (blkLast),
        .finalize  (coreFinalize),
        .ct_out    (coreCtOut),
        .ct_valid  (coreCtValid),
        .tag       (coreTag),
        .tag_in    (128'd0),
        .tag_match (),                // Unused in encrypt mode
        .auth_fail ()                 // Unused in encrypt mode
    );

    // =========================================================================
    // TX Serializer Instance (Stage 2)
    // =========================================================================
    gcm_tx_serializer u_tx (
        .clk              (clk),
        .rst              (rst),
        .txStart          (txStartPulse),
        .txIv             (ivOut),
        .txPtLen          (ptLenReg),
        .txCtBlock        (ctCapture),
        .txCtValid        (txCtValidW),
        .txCtBytes        (blkBytes),
        .txCtLast         (blkLast),
        .txTag            (tagCapture),
        .txTagValid       (txTagValidW),
        .txBusy           (txSerBusy),
        .txDone           (txSerDone),
        .txCtReady        (txCtReady),
        .txTagReady       (txTagReady),
        .tx_hdr_valid     (tx_hdr_valid),
        .tx_payload_len   (tx_payload_len),
        .tx_hdr_ready     (tx_hdr_ready),
        .tx_payload_tdata (tx_payload_tdata),
        .tx_payload_tvalid(tx_payload_tvalid),
        .tx_payload_tready(tx_payload_tready),
        .tx_payload_tlast (tx_payload_tlast)
    );

    // =========================================================================
    // Sequencing FSM
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            fsmState   <= ST_IDLE;
            ptLenReg   <= 16'd0;
            blkData    <= 128'd0;
            blkBytes   <= 5'd0;
            blkLast    <= 1'b0;
            ctCapture  <= 128'd0;
            tagCapture <= 128'd0;
            waitCnt    <= 8'd0;
        end
        else begin
            case (fsmState)
                // ---------------------------------------------------------
                // IDLE: Wait for RX header handshake
                // ---------------------------------------------------------
                ST_IDLE: begin
                    if (rx_hdr_valid && rx_hdr_ready) begin
                        ptLenReg <= rx_payload_len;
                        fsmState <= ST_START;
                    end
                end

                // ---------------------------------------------------------
                // START: Pulse start to core and txStart to TX serializer.
                //        Both fire on this single cycle.
                // ---------------------------------------------------------
                ST_START: begin
                    waitCnt  <= 8'd0;
                    fsmState <= ST_INIT_WAIT;
                end

                // ---------------------------------------------------------
                // INIT_WAIT: Fixed delay for H computation + GHASH init.
                //            Core transitions through COMPUTE_H → WAIT_H →
                //            INIT_GHASH → READY during this time.
                // ---------------------------------------------------------
                ST_INIT_WAIT: begin
                    if (waitCnt == INIT_DELAY) begin
                        if (ptLenReg == 16'd0)
                            fsmState <= ST_FINALIZE;
                        else
                            fsmState <= ST_PULL_DATA;
                    end
                    else begin
                        waitCnt <= waitCnt + 8'd1;
                    end
                end

                // ---------------------------------------------------------
                // PULL_DATA: Accept next 128-bit block from width converter.
                //            rxBlk_tready is high in this state.
                // ---------------------------------------------------------
                ST_PULL_DATA: begin
                    if (rxBlk_tvalid) begin
                        blkData  <= rxBlk_tdata;
                        blkBytes <= rxBlk_byteCount;
                        blkLast  <= rxBlk_tlast;
                        fsmState <= ST_FEED;
                    end
                end

                // ---------------------------------------------------------
                // FEED: Pulse pt_valid to core for exactly 1 cycle.
                //       Core is in STATE_READY and latches pt_in.
                // ---------------------------------------------------------
                ST_FEED: begin
                    fsmState <= ST_WAIT_CT;
                end

                // ---------------------------------------------------------
                // WAIT_CT: Wait for core to output ct_valid (AES complete).
                //          Capture the ciphertext block.
                // ---------------------------------------------------------
                ST_WAIT_CT: begin
                    if (coreCtValid) begin
                        ctCapture <= coreCtOut;
                        fsmState  <= ST_PUSH_CT;
                    end
                end

                // ---------------------------------------------------------
                // PUSH_CT: Hold txCtValid until TX serializer accepts.
                //          Handshake: txCtValid && txCtReady.
                // ---------------------------------------------------------
                ST_PUSH_CT: begin
                    if (txCtReady) begin
                        waitCnt <= 8'd0;
                        if (blkLast)
                            fsmState <= ST_WAIT_DONE;
                        else
                            fsmState <= ST_GHASH_WAIT;
                    end
                end

                // ---------------------------------------------------------
                // GHASH_WAIT: Fixed delay for GHASH processing of current
                //             block. Core returns to STATE_READY after this.
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
                // FINALIZE: Pulse finalize for zero-PT case (GMAC).
                // ---------------------------------------------------------
                ST_FINALIZE: begin
                    fsmState <= ST_WAIT_DONE;
                end

                // ---------------------------------------------------------
                // WAIT_DONE: Wait for core done signal, capture tag.
                // ---------------------------------------------------------
                ST_WAIT_DONE: begin
                    if (coreDone) begin
                        tagCapture <= coreTag;
                        fsmState   <= ST_PUSH_TAG;
                    end
                end

                // ---------------------------------------------------------
                // PUSH_TAG: Hold txTagValid until TX serializer accepts.
                //           Handshake: txTagValid && txTagReady.
                // ---------------------------------------------------------
                ST_PUSH_TAG: begin
                    if (txTagReady) begin
                        fsmState <= ST_WAIT_TX;
                    end
                end

                // ---------------------------------------------------------
                // WAIT_TX: Wait for TX serializer to finish outputting
                //          all bytes (IV + CT + tag).
                // ---------------------------------------------------------
                ST_WAIT_TX: begin
                    if (txSerDone) begin
                        fsmState <= ST_PKT_DONE;
                    end
                end

                // ---------------------------------------------------------
                // PKT_DONE: Single-cycle pulse for IV auto-increment
                //           and encDone output. Return to idle.
                // ---------------------------------------------------------
                ST_PKT_DONE: begin
                    fsmState <= ST_IDLE;
                end

                default: begin
                    fsmState <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
