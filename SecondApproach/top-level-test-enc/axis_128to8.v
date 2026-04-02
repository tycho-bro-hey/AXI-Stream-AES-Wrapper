`timescale 1ns / 1ps
//
// module: axis_128to8
// project: aes-gcm-256 for arty a7-100t
//
// behavioral model of vivado axis_dwidth_converter (128-bit slave to
// 8-bit master). serializes 128-bit words into bytes msb-first.
// uses tkeep to determine valid byte count. propagates tlast on the
// last valid byte. for simulation only; replaced by vivado ip
// in synthesis.
//
// dependencies: none
//

module axis_128to8 (
    input wire clk,
    input wire rst,

    // 128-bit axi-stream slave
    input wire [127:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output reg s_axis_tready,
    input wire s_axis_tlast,
    input wire [15:0] s_axis_tkeep,

    // 8-bit axi-stream master
    output reg [7:0] m_axis_tdata,
    output reg m_axis_tvalid,
    input wire m_axis_tready,
    output reg m_axis_tlast
);

    reg [127:0] wordReg;
    reg [3:0] byteIdx;
    reg [3:0] lastByteIdx;
    reg lastWord;
    reg outputActive;

    // compute last valid byte index from left-aligned tkeep
    function [3:0] findLastByte;
        input [15:0] keep;
        integer k;
    begin
        findLastByte = 4'd0;
        for (k = 15; k >= 0; k = k - 1) begin
            if (keep[k])
                findLastByte = 4'd15 - k[3:0];
        end
    end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            wordReg <= 128'd0;
            byteIdx <= 4'd0;
            lastByteIdx <= 4'd0;
            lastWord <= 1'b0;
            outputActive <= 1'b0;
            m_axis_tdata <= 8'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            s_axis_tready <= 1'b1;
        end
        else begin
            // accept new word when idle
            if (s_axis_tvalid && s_axis_tready && !outputActive) begin
                wordReg <= s_axis_tdata;
                lastWord <= s_axis_tlast;
                lastByteIdx <= findLastByte(s_axis_tkeep);
                byteIdx <= 4'd0;
                outputActive <= 1'b1;
                s_axis_tready <= 1'b0;
                // present first byte immediately
                m_axis_tdata <= s_axis_tdata[127:120];
                m_axis_tvalid <= 1'b1;
                m_axis_tlast <= s_axis_tlast && (findLastByte(s_axis_tkeep) == 4'd0);
            end

            // output bytes sequentially
            if (outputActive && m_axis_tvalid && m_axis_tready) begin
                if (byteIdx == lastByteIdx) begin
                    // done with this word
                    outputActive <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                    s_axis_tready <= 1'b1;
                end
                else begin
                    // advance to next byte
                    byteIdx <= byteIdx + 4'd1;
                    m_axis_tdata <= wordReg[127 - (byteIdx + 4'd1)*8 -: 8];
                    m_axis_tlast <= lastWord && (byteIdx + 4'd1 == lastByteIdx);
                end
            end
        end
    end

endmodule
