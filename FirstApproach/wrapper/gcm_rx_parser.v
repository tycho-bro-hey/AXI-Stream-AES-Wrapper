`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: gcm_rx_parser
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Parses incoming encrypted byte stream (IV + CT + Tag) into
//              its three components. Extracts 12-byte IV into a register,
//              routes N ciphertext bytes to an AXI-Stream output (for the
//              width converter), and accumulates the final 16-byte tag
//              into a register.
//
//              Byte layout (per Section 4.2):
//                Bytes 0-11:                  IV (12 bytes)
//                Bytes 12 to (totalLen-17):   Ciphertext (N bytes)
//                Bytes (totalLen-16) to end:  Tag (16 bytes)
//
//              ctLen = totalLen - 28. When ctLen == 0, no CT bytes are
//              routed and the parser transitions directly to tag accumulation.
//
// Dependencies: None
//
//////////////////////////////////////////////////////////////////////////////////

module gcm_rx_parser (
    input wire         clk,
    input wire         rst,

    // Packet start (from upstream FSM)
    input wire         pktStart,      // Pulse: begin parsing new packet
    input wire [15:0]  totalLen,      // Total encrypted payload (IV + CT + tag)

    // RX payload byte input (from Ethernet stack)
    input wire [7:0]   rx_tdata,
    input wire         rx_tvalid,
    output wire        rx_tready,

    // CT byte output (to width converter slave input)
    output wire [7:0]  ct_tdata,
    output wire        ct_tvalid,
    input wire         ct_tready,
    output wire        ct_tlast,

    // Extracted fields
    output reg [95:0]  ivOut,         // Extracted IV (valid when ivReady pulses)
    output reg         ivReady,       // Pulse: IV extraction complete
    output reg [127:0] tagOut,        // Extracted tag (valid when tagReady pulses)
    output reg         tagReady,      // Pulse: tag extraction complete
    output reg [15:0]  ctLen,         // Ciphertext byte count (valid after pktStart)

    // Status
    output wire        parserBusy,
    output reg         parserDone     // Pulse: all bytes consumed
);

    // =========================================================================
    // State Encoding
    // =========================================================================
    localparam [2:0] S_IDLE     = 3'd0;
    localparam [2:0] S_IV_RECV  = 3'd1;
    localparam [2:0] S_CT_PASS  = 3'd2;
    localparam [2:0] S_TAG_RECV = 3'd3;
    localparam [2:0] S_DONE     = 3'd4;

    // =========================================================================
    // Internal Registers
    // =========================================================================
    reg [2:0]   state;
    reg [15:0]  totalLenReg;
    reg [15:0]  ctLenReg;       // ctLen = totalLen - 28
    reg [3:0]   ivCnt;          // 0..11
    reg [15:0]  ctCnt;          // Counts CT bytes routed
    reg [3:0]   tagCnt;         // 0..15

    // =========================================================================
    // Combinational Control
    // =========================================================================
    assign parserBusy = (state != S_IDLE);

    // RX tready: accept bytes in IV, CT, and TAG phases
    // During CT_PASS, stall if width converter can't accept
    assign rx_tready = (state == S_IV_RECV) ||
                       (state == S_CT_PASS && ct_tready) ||
                       (state == S_TAG_RECV);

    // CT output: valid only during CT_PASS when input is valid
    assign ct_tdata  = rx_tdata;
    assign ct_tvalid = (state == S_CT_PASS) && rx_tvalid;
    assign ct_tlast  = (state == S_CT_PASS) && rx_tvalid &&
                       (ctCnt == ctLenReg - 16'd1);

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            totalLenReg <= 16'd0;
            ctLenReg    <= 16'd0;
            ctLen       <= 16'd0;
            ivOut       <= 96'd0;
            ivCnt       <= 4'd0;
            tagOut      <= 128'd0;
            tagCnt      <= 4'd0;
            ctCnt       <= 16'd0;
            ivReady     <= 1'b0;
            tagReady    <= 1'b0;
            parserDone  <= 1'b0;
        end
        else begin
            // Default: clear single-cycle pulses
            ivReady    <= 1'b0;
            tagReady   <= 1'b0;
            parserDone <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                // IDLE: Wait for pktStart
                // ---------------------------------------------------------
                S_IDLE: begin
                    if (pktStart) begin
                        totalLenReg <= totalLen;
                        ctLenReg    <= totalLen - 16'd28;
                        ctLen       <= totalLen - 16'd28;
                        ivCnt       <= 4'd0;
                        ctCnt       <= 16'd0;
                        tagCnt      <= 4'd0;
                        ivOut       <= 96'd0;
                        tagOut      <= 128'd0;
                        state       <= S_IV_RECV;
                    end
                end

                // ---------------------------------------------------------
                // IV_RECV: Accumulate 12 IV bytes (MSB-first)
                // ---------------------------------------------------------
                S_IV_RECV: begin
                    if (rx_tvalid && rx_tready) begin
                        ivOut <= {ivOut[87:0], rx_tdata};
                        if (ivCnt == 4'd11) begin
                            // Last IV byte
                            ivReady <= 1'b1;
                            if (ctLenReg == 16'd0) begin
                                // No CT bytes — skip to tag
                                state <= S_TAG_RECV;
                            end
                            else begin
                                state <= S_CT_PASS;
                            end
                        end
                        else begin
                            ivCnt <= ivCnt + 4'd1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // CT_PASS: Route CT bytes to width converter output.
                //          Backpressure from width converter stalls rx_tready.
                // ---------------------------------------------------------
                S_CT_PASS: begin
                    if (rx_tvalid && rx_tready) begin
                        ctCnt <= ctCnt + 16'd1;
                        if (ctCnt == ctLenReg - 16'd1) begin
                            // Last CT byte
                            state <= S_TAG_RECV;
                        end
                    end
                end

                // ---------------------------------------------------------
                // TAG_RECV: Accumulate 16 tag bytes (MSB-first)
                // ---------------------------------------------------------
                S_TAG_RECV: begin
                    if (rx_tvalid && rx_tready) begin
                        tagOut <= {tagOut[119:0], rx_tdata};
                        if (tagCnt == 4'd15) begin
                            // Last tag byte
                            tagReady <= 1'b1;
                            state    <= S_DONE;
                        end
                        else begin
                            tagCnt <= tagCnt + 4'd1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // DONE: Pulse parserDone, return to idle
                // ---------------------------------------------------------
                S_DONE: begin
                    parserDone <= 1'b1;
                    state      <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
