`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: gcm_pt_serializer
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Plaintext byte serializer for the decrypt output path.
//              Converts 128-bit plaintext blocks from the GCM core into
//              byte-serial AXI-Stream output with Section 7 header
//              handshake. Simpler than gcm_tx_serializer — no IV prefix
//              or tag suffix, just raw plaintext bytes.
//
// Dependencies: None
//
//////////////////////////////////////////////////////////////////////////////////

module gcm_pt_serializer (
    input wire         clk,
    input wire         rst,

    // Packet start (from wrapper FSM)
    input wire         txStart,       // Pulse: begin new TX packet
    input wire [15:0]  txPtLen,       // Plaintext byte count (latched on txStart)

    // PT block input (from crypto core via wrapper FSM)
    input wire [127:0] txPtBlock,     // 128-bit plaintext block
    input wire         txPtValid,     // PT block valid (pulse)
    input wire [4:0]   txPtBytes,     // Valid bytes: 1-16 (0 encodes 16)
    input wire         txPtLast,      // Last PT block flag

    // Status outputs
    output wire        txBusy,
    output reg         txDone,        // Pulse: TX packet complete
    output wire        txPtReady,     // Ready to accept PT block

    // TX AXI-Stream to downstream (Section 7)
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
    localparam [2:0] S_PT_WAIT  = 3'd2;
    localparam [2:0] S_PT_SEND  = 3'd3;
    localparam [2:0] S_DONE     = 3'd4;

    // =========================================================================
    // Internal Registers
    // =========================================================================
    reg [2:0]   state;
    reg [127:0] shiftReg;
    reg [4:0]   bytesRemain;
    reg [15:0]  payloadLenReg;
    reg         ptLastSeen;

    // =========================================================================
    // Combinational Outputs
    // =========================================================================
    assign txBusy           = (state != S_IDLE);
    assign txPtReady        = (state == S_PT_WAIT);
    assign tx_hdr_valid     = (state == S_HDR);
    assign tx_payload_len   = payloadLenReg;
    assign tx_payload_tdata = shiftReg[127:120];
    assign tx_payload_tvalid = (state == S_PT_SEND);
    assign tx_payload_tlast  = (state == S_PT_SEND) && (bytesRemain == 5'd1) && ptLastSeen;

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            shiftReg      <= 128'd0;
            bytesRemain   <= 5'd0;
            payloadLenReg <= 16'd0;
            ptLastSeen    <= 1'b0;
            txDone        <= 1'b0;
        end
        else begin
            txDone <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (txStart) begin
                        payloadLenReg <= txPtLen;
                        ptLastSeen    <= 1'b0;
                        if (txPtLen == 16'd0)
                            state <= S_DONE;
                        else
                            state <= S_HDR;
                    end
                end

                S_HDR: begin
                    if (tx_hdr_ready) begin
                        state <= S_PT_WAIT;
                    end
                end

                S_PT_WAIT: begin
                    if (txPtValid) begin
                        shiftReg    <= txPtBlock;
                        bytesRemain <= (txPtBytes == 5'd0) ? 5'd16 : txPtBytes;
                        ptLastSeen  <= txPtLast;
                        state       <= S_PT_SEND;
                    end
                end

                S_PT_SEND: begin
                    if (tx_payload_tready) begin
                        if (bytesRemain == 5'd1) begin
                            if (ptLastSeen)
                                state <= S_DONE;
                            else
                                state <= S_PT_WAIT;
                        end
                        else begin
                            shiftReg    <= {shiftReg[119:0], 8'd0};
                            bytesRemain <= bytesRemain - 5'd1;
                        end
                    end
                end

                S_DONE: begin
                    txDone <= 1'b1;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
