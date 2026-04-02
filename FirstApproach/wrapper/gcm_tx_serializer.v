`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: gcm_tx_serializer
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: TX output byte serializer for AES-GCM-256 AXI-Stream wrapper.
//              Converts 96-bit IV, 128-bit ciphertext blocks, and 128-bit tag
//              into byte-serial AXI-Stream output per Section 7 TX protocol.
//              Implements two-phase header handshake, backpressure handling,
//              and tlast generation on the final tag byte.
//
//              Upstream FSM must not assert txCtValid or txTagValid while
//              this module is still serializing a previous block.
//
// Dependencies: None
//
//////////////////////////////////////////////////////////////////////////////////

module gcm_tx_serializer (
    input wire         clk,
    input wire         rst,

    // Packet start (from wrapper FSM)
    input wire         txStart,       // Pulse: begin new TX packet
    input wire [95:0]  txIv,          // IV for this packet (latched on txStart)
    input wire [15:0]  txPtLen,       // Plaintext byte count (latched on txStart)

    // CT block input (from crypto core via wrapper FSM)
    input wire [127:0] txCtBlock,     // 128-bit ciphertext block
    input wire         txCtValid,     // CT block valid (pulse)
    input wire [4:0]   txCtBytes,     // Valid bytes: 1-16 (0 encodes 16)
    input wire         txCtLast,      // Last CT block flag

    // Tag input (from crypto core via wrapper FSM)
    input wire [127:0] txTag,         // 128-bit authentication tag
    input wire         txTagValid,    // Tag valid (pulse, after core done)

    // Status outputs
    output wire        txBusy,        // TX serializer is active
    output reg         txDone,        // Pulse: TX packet complete
    output wire        txCtReady,     // Ready to accept CT block (in CT_WAIT)
    output wire        txTagReady,    // Ready to accept tag (in TAG_WAIT)

    // TX AXI-Stream to Ethernet stack (Section 7)
    output wire        tx_hdr_valid,
    output wire [15:0] tx_payload_len,
    input wire         tx_hdr_ready,

    output wire [7:0]  tx_payload_tdata,
    output wire        tx_payload_tvalid,
    input wire         tx_payload_tready,
    output wire        tx_payload_tlast
);

    // =========================================================================
    // State Encoding
    // =========================================================================
    localparam [2:0] S_IDLE     = 3'd0;
    localparam [2:0] S_HDR      = 3'd1;
    localparam [2:0] S_IV       = 3'd2;
    localparam [2:0] S_CT_WAIT  = 3'd3;
    localparam [2:0] S_CT_SEND  = 3'd4;
    localparam [2:0] S_TAG_WAIT = 3'd5;
    localparam [2:0] S_TAG_SEND = 3'd6;
    localparam [2:0] S_DONE     = 3'd7;

    // =========================================================================
    // Internal Registers
    // =========================================================================
    reg [2:0]   state;
    reg [127:0] shiftReg;      // Holds data being serialized (MSB-first)
    reg [4:0]   bytesRemain;   // Bytes remaining in current phase (incl. current)
    reg [15:0]  payloadLenReg; // 12 + ptLen + 16
    reg         ctLastSeen;    // Set when final CT block has been serialized
    reg         ptIsZero;      // Set when ptLen == 0 (no CT blocks expected)

    // =========================================================================
    // Combinational Outputs
    // =========================================================================
    assign txBusy           = (state != S_IDLE);
    assign txCtReady        = (state == S_CT_WAIT);
    assign txTagReady       = (state == S_TAG_WAIT);
    assign tx_hdr_valid     = (state == S_HDR);
    assign tx_payload_len   = payloadLenReg;
    assign tx_payload_tdata = shiftReg[127:120];

    assign tx_payload_tvalid = (state == S_IV) ||
                               (state == S_CT_SEND) ||
                               (state == S_TAG_SEND);

    assign tx_payload_tlast  = (state == S_TAG_SEND) &&
                               (bytesRemain == 5'd1);

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            shiftReg       <= 128'd0;
            bytesRemain    <= 5'd0;
            payloadLenReg  <= 16'd0;
            ctLastSeen     <= 1'b0;
            ptIsZero       <= 1'b0;
            txDone         <= 1'b0;
        end
        else begin
            // Default: clear single-cycle pulses
            txDone <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                // IDLE: Wait for txStart
                // ---------------------------------------------------------
                S_IDLE: begin
                    if (txStart) begin
                        payloadLenReg <= txPtLen + 16'd28; // 12 + ptLen + 16
                        shiftReg      <= {txIv, 32'd0};
                        bytesRemain   <= 5'd12;
                        ctLastSeen    <= 1'b0;
                        ptIsZero      <= (txPtLen == 16'd0);
                        state         <= S_HDR;
                    end
                end

                // ---------------------------------------------------------
                // HDR: Header handshake — hold tx_hdr_valid until accepted
                // ---------------------------------------------------------
                S_HDR: begin
                    if (tx_hdr_ready) begin
                        state <= S_IV;
                    end
                end

                // ---------------------------------------------------------
                // IV: Serialize 12 IV bytes
                // ---------------------------------------------------------
                S_IV: begin
                    if (tx_payload_tready) begin
                        if (bytesRemain == 5'd1) begin
                            // Last IV byte accepted
                            if (ptIsZero) begin
                                state <= S_TAG_WAIT;
                            end
                            else begin
                                state <= S_CT_WAIT;
                            end
                        end
                        else begin
                            shiftReg    <= {shiftReg[119:0], 8'd0};
                            bytesRemain <= bytesRemain - 5'd1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // CT_WAIT: Wait for next ciphertext block
                // ---------------------------------------------------------
                S_CT_WAIT: begin
                    if (txCtValid) begin
                        shiftReg    <= txCtBlock;
                        bytesRemain <= (txCtBytes == 5'd0) ? 5'd16 : txCtBytes;
                        ctLastSeen  <= txCtLast;
                        state       <= S_CT_SEND;
                    end
                end

                // ---------------------------------------------------------
                // CT_SEND: Serialize ciphertext block bytes
                // ---------------------------------------------------------
                S_CT_SEND: begin
                    if (tx_payload_tready) begin
                        if (bytesRemain == 5'd1) begin
                            // Last byte of this CT block
                            if (ctLastSeen) begin
                                state <= S_TAG_WAIT;
                            end
                            else begin
                                state <= S_CT_WAIT;
                            end
                        end
                        else begin
                            shiftReg    <= {shiftReg[119:0], 8'd0};
                            bytesRemain <= bytesRemain - 5'd1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // TAG_WAIT: Wait for authentication tag
                // ---------------------------------------------------------
                S_TAG_WAIT: begin
                    if (txTagValid) begin
                        shiftReg    <= txTag;
                        bytesRemain <= 5'd16;
                        state       <= S_TAG_SEND;
                    end
                end

                // ---------------------------------------------------------
                // TAG_SEND: Serialize 16 tag bytes
                // ---------------------------------------------------------
                S_TAG_SEND: begin
                    if (tx_payload_tready) begin
                        if (bytesRemain == 5'd1) begin
                            // Last tag byte — packet complete
                            state <= S_DONE;
                        end
                        else begin
                            shiftReg    <= {shiftReg[119:0], 8'd0};
                            bytesRemain <= bytesRemain - 5'd1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // DONE: Pulse txDone for one cycle, return to idle
                // ---------------------------------------------------------
                S_DONE: begin
                    txDone <= 1'b1;
                    state  <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
