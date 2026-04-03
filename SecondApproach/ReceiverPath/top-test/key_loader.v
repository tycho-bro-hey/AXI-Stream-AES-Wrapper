`timescale 1ns / 1ps
//
// module: key_loader
// project: aes-gcm-256 for arty a7-100t
//
// accumulates 32 bytes from an 8-bit axi-stream slave into a
// 256-bit key register. msb-first byte order. power-up default
// from localparam. commits new key only when crypto core is idle.
// tlast must arrive on byte 31; early or late tlast discards the
// partial key and asserts load error.
//
// dependencies: none
//

module key_loader (
    input wire clk,
    input wire rst,

    // axi-stream slave (8-bit key bytes)
    input wire [7:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output reg s_axis_tready,
    input wire s_axis_tlast,

    // key output register
    output reg [255:0] keyReg,

    // control/status
    input wire encBusy,
    output reg loadErr
);

    localparam DEFAULT_KEY = 256'h0;
    localparam KEY_BYTES = 6'd32;

    reg [255:0] shiftReg;
    reg [5:0] byteCount;
    reg loadPending;

    always @(posedge clk) begin
        if (rst) begin
            keyReg <= DEFAULT_KEY;
            shiftReg <= 256'd0;
            byteCount <= 6'd0;
            loadPending <= 1'b0;
            loadErr <= 1'b0;
            s_axis_tready <= 1'b1;
        end
        else if (loadPending) begin
            // wait for core idle before committing
            s_axis_tready <= 1'b0;
            if (!encBusy) begin
                keyReg <= shiftReg;
                loadPending <= 1'b0;
                s_axis_tready <= 1'b1;
                byteCount <= 6'd0;
            end
        end
        else if (s_axis_tvalid && s_axis_tready) begin
            // shift in byte (msb-first)
            shiftReg <= {shiftReg[247:0], s_axis_tdata};
            byteCount <= byteCount + 6'd1;
            loadErr <= 1'b0;

            if (s_axis_tlast) begin
                if (byteCount == KEY_BYTES - 6'd1) begin
                    // correct: byte 31 with tlast
                    loadPending <= 1'b1;
                end
                else begin
                    // error: tlast too early
                    loadErr <= 1'b1;
                    byteCount <= 6'd0;
                end
            end
            else if (byteCount == KEY_BYTES - 6'd1) begin
                // error: byte 31 without tlast
                loadErr <= 1'b1;
                byteCount <= 6'd0;
            end
        end
    end

endmodule
