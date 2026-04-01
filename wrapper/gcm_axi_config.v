`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: gcm_axi_config
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Key and IV configuration registers with 8-bit AXI-Stream
//              loading interfaces. Provides hardcoded defaults on reset,
//              runtime overwrite via AXI-Stream, and IV auto-increment
//              after each packet. Validates tlast alignment and gates
//              commits on core idle.
//
// Dependencies: None
//
//////////////////////////////////////////////////////////////////////////////////

module gcm_axi_config (
    input wire         clk,
    input wire         rst,

    // Key AXI-Stream input (32 bytes, MSB-first)
    input wire [7:0]   key_axis_tdata,
    input wire         key_axis_tvalid,
    output wire        key_axis_tready,
    input wire         key_axis_tlast,

    // IV Seed AXI-Stream input (12 bytes, MSB-first)
    input wire [7:0]   iv_axis_tdata,
    input wire         iv_axis_tvalid,
    output wire        iv_axis_tready,
    input wire         iv_axis_tlast,

    // Control inputs
    input wire         coreIdle,      // High when crypto core is idle
    input wire         pktDone,       // Pulse after each encryption completes

    // Configuration outputs
    output wire [255:0] keyOut,
    output wire [95:0]  ivOut,

    // Status outputs
    output reg         keyUpdated,    // Pulses 1 cycle when new key committed
    output reg         ivUpdated,     // Pulses 1 cycle when new IV committed
    output reg         keyError,      // Sticky: tlast misalignment on key port
    output reg         ivError        // Sticky: tlast misalignment on IV port
);

    // =========================================================================
    // Default values (NIST Test Case 14 — for development/validation)
    // =========================================================================
    localparam [255:0] DEFAULT_KEY = 256'h0000000000000000000000000000000000000000000000000000000000000000;
    localparam [95:0]  DEFAULT_IV  = 96'h000000000000000000000000;

    localparam [4:0] KEY_BYTE_MAX = 5'd31;  // 0-indexed: bytes 0..31
    localparam [3:0] IV_BYTE_MAX  = 4'd11;  // 0-indexed: bytes 0..11

    // =========================================================================
    // Key loading registers
    // =========================================================================
    reg [255:0] keyReg;
    reg [255:0] keyShadow;    // Accumulates incoming bytes
    reg [4:0]   keyByteCnt;   // Counts 0..31
    reg         keyLoading;   // High while accumulating key bytes
    reg         keyPending;   // Shadow is complete, waiting for coreIdle

    // =========================================================================
    // IV loading registers
    // =========================================================================
    reg [95:0]  ivReg;
    reg [95:0]  ivShadow;     // Accumulates incoming bytes
    reg [3:0]   ivByteCnt;    // Counts 0..11
    reg         ivLoading;    // High while accumulating IV bytes
    reg         ivPending;    // Shadow is complete, waiting for coreIdle

    // =========================================================================
    // Output assignments
    // =========================================================================
    assign keyOut = keyReg;
    assign ivOut  = ivReg;

    // Accept bytes when not waiting to commit and no error has occurred
    assign key_axis_tready = !keyPending && !keyError;
    assign iv_axis_tready  = !ivPending  && !ivError;

    // =========================================================================
    // Key loading FSM
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            keyReg     <= DEFAULT_KEY;
            keyShadow  <= 256'd0;
            keyByteCnt <= 5'd0;
            keyLoading <= 1'b0;
            keyPending <= 1'b0;
            keyUpdated <= 1'b0;
            keyError   <= 1'b0;
        end
        else begin
            // Default: clear single-cycle pulses
            keyUpdated <= 1'b0;

            // Commit pending key when core is idle
            if (keyPending && coreIdle) begin
                keyReg     <= keyShadow;
                keyPending <= 1'b0;
                keyUpdated <= 1'b1;
            end

            // Accept incoming key bytes
            if (key_axis_tvalid && key_axis_tready) begin
                // Shift byte into shadow register (MSB-first)
                keyShadow <= {keyShadow[247:0], key_axis_tdata};
                keyLoading <= 1'b1;

                if (keyByteCnt == KEY_BYTE_MAX) begin
                    // Last byte received
                    if (!key_axis_tlast) begin
                        // tlast should be asserted on byte 31 but isn't
                        keyError   <= 1'b1;
                        keyLoading <= 1'b0;
                        keyByteCnt <= 5'd0;
                    end
                    else begin
                        // Correct: tlast on byte 31
                        keyPending <= 1'b1;
                        keyLoading <= 1'b0;
                        keyByteCnt <= 5'd0;
                    end
                end
                else begin
                    // Not the last byte yet
                    if (key_axis_tlast) begin
                        // tlast arrived too early — discard partial key
                        keyError   <= 1'b1;
                        keyLoading <= 1'b0;
                        keyByteCnt <= 5'd0;
                    end
                    else begin
                        keyByteCnt <= keyByteCnt + 5'd1;
                    end
                end
            end
        end
    end

    // =========================================================================
    // IV loading and auto-increment FSM
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            ivReg     <= DEFAULT_IV;
            ivShadow  <= 96'd0;
            ivByteCnt <= 4'd0;
            ivLoading <= 1'b0;
            ivPending <= 1'b0;
            ivUpdated <= 1'b0;
            ivError   <= 1'b0;
        end
        else begin
            // Default: clear single-cycle pulses
            ivUpdated <= 1'b0;

            // Commit pending IV when core is idle
            if (ivPending && coreIdle) begin
                ivReg     <= ivShadow;
                ivPending <= 1'b0;
                ivUpdated <= 1'b1;
            end

            // IV auto-increment: lower 64 bits after each packet
            if (pktDone && !ivPending) begin
                ivReg[63:0] <= ivReg[63:0] + 64'd1;
            end

            // Accept incoming IV bytes
            if (iv_axis_tvalid && iv_axis_tready) begin
                // Shift byte into shadow register (MSB-first)
                ivShadow <= {ivShadow[87:0], iv_axis_tdata};
                ivLoading <= 1'b1;

                if (ivByteCnt == IV_BYTE_MAX) begin
                    // Last byte received
                    if (!iv_axis_tlast) begin
                        // tlast should be asserted on byte 11 but isn't
                        ivError   <= 1'b1;
                        ivLoading <= 1'b0;
                        ivByteCnt <= 4'd0;
                    end
                    else begin
                        // Correct: tlast on byte 11
                        ivPending <= 1'b1;
                        ivLoading <= 1'b0;
                        ivByteCnt <= 4'd0;
                    end
                end
                else begin
                    // Not the last byte yet
                    if (iv_axis_tlast) begin
                        // tlast arrived too early — discard partial IV
                        ivError   <= 1'b1;
                        ivLoading <= 1'b0;
                        ivByteCnt <= 4'd0;
                    end
                    else begin
                        ivByteCnt <= ivByteCnt + 4'd1;
                    end
                end
            end
        end
    end

endmodule
