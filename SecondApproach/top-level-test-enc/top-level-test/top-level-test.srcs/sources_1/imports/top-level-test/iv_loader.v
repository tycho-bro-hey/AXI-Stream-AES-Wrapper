`timescale 1ns / 1ps
//
// module: iv_loader
// project: aes-gcm-256 for arty a7-100t
//
// accumulates 12 bytes from an 8-bit axi-stream slave into a
// 96-bit iv register. msb-first byte order. power-up default
// from localparam. commits new iv seed only when crypto core is
// idle. auto-increments lower 64 bits on each pkt-done pulse
// per nist sp 800-38d section 8.2.1.
// tlast must arrive on byte 11; early or late tlast discards
// the partial iv and asserts load error.
//
// dependencies: none
//

module iv_loader (
    input wire clk,
    input wire rst,

    // axi-stream slave (8-bit iv seed bytes)
    input wire [7:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output reg s_axis_tready,
    input wire s_axis_tlast,

    // iv output register
    output reg [95:0] ivReg,

    // control/status
    input wire encBusy,
    input wire pktDone, // pulse after each encryption for auto-increment
    output reg loadErr
);

    localparam DEFAULT_IV = 96'h0;
    localparam IV_BYTES = 4'd12;

    reg [95:0] shiftReg;
    reg [3:0] byteCount;
    reg loadPending;

    always @(posedge clk) begin
        if (rst) begin
            ivReg <= DEFAULT_IV;
            shiftReg <= 96'd0;
            byteCount <= 4'd0;
            loadPending <= 1'b0;
            loadErr <= 1'b0;
            s_axis_tready <= 1'b1;
        end
        else if (loadPending) begin
            // wait for core idle before committing new seed
            s_axis_tready <= 1'b0;
            if (!encBusy) begin
                ivReg <= shiftReg;
                loadPending <= 1'b0;
                s_axis_tready <= 1'b1;
                byteCount <= 4'd0;
            end
        end
        else begin
            // auto-increment lower 64 bits on packet completion
            if (pktDone) begin
                ivReg[63:0] <= ivReg[63:0] + 64'd1;
            end

            // accumulate iv seed bytes
            if (s_axis_tvalid && s_axis_tready) begin
                shiftReg <= {shiftReg[87:0], s_axis_tdata};
                byteCount <= byteCount + 4'd1;
                loadErr <= 1'b0;

                if (s_axis_tlast) begin
                    if (byteCount == IV_BYTES - 4'd1) begin
                        // correct: byte 11 with tlast
                        loadPending <= 1'b1;
                    end
                    else begin
                        // error: tlast too early
                        loadErr <= 1'b1;
                        byteCount <= 4'd0;
                    end
                end
                else if (byteCount == IV_BYTES - 4'd1) begin
                    // error: byte 11 without tlast
                    loadErr <= 1'b1;
                    byteCount <= 4'd0;
                end
            end
        end
    end

endmodule
