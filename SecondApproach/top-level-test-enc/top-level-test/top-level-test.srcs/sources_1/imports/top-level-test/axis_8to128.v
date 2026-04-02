`timescale 1ns / 1ps
//
// module: axis_8to128
// project: aes-gcm-256 for arty a7-100t
//
// behavioral model of vivado axis_dwidth_converter (8-bit slave to
// 128-bit master). accumulates 16 bytes msb-first into a 128-bit
// word. generates left-aligned tkeep for partial final blocks.
// propagates tlast. for simulation only; replaced by vivado ip
// in synthesis.
//
// dependencies: none
//

module axis_8to128 (
    input wire clk,
    input wire rst,

    // 8-bit axi-stream slave
    input wire [7:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output reg s_axis_tready,
    input wire s_axis_tlast,

    // 128-bit axi-stream master
    output reg [127:0] m_axis_tdata,
    output reg m_axis_tvalid,
    input wire m_axis_tready,
    output reg m_axis_tlast,
    output reg [15:0] m_axis_tkeep
);

    reg [127:0] accumReg;
    reg [3:0] byteIdx;

    // combinational: accumulator with current byte placed
    reg [127:0] nextWord;
    always @(*) begin
        nextWord = accumReg;
        nextWord[127 - byteIdx*8 -: 8] = s_axis_tdata;
    end

    always @(posedge clk) begin
        if (rst) begin
            accumReg <= 128'd0;
            byteIdx <= 4'd0;
            m_axis_tdata <= 128'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            m_axis_tkeep <= 16'd0;
            s_axis_tready <= 1'b1;
        end
        else begin
            // clear output when downstream accepts
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
                s_axis_tready <= 1'b1;
            end

            // accept input byte
            if (s_axis_tvalid && s_axis_tready && !(m_axis_tvalid && !m_axis_tready)) begin
                if (s_axis_tlast || byteIdx == 4'd15) begin
                    // emit word with all accumulated bytes including current
                    m_axis_tdata <= nextWord;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast <= s_axis_tlast;
                    m_axis_tkeep <= (16'hFFFF << (4'd15 - byteIdx));
                    byteIdx <= 4'd0;
                    accumReg <= 128'd0;
                    s_axis_tready <= 1'b0;
                end
                else begin
                    accumReg <= nextWord;
                    byteIdx <= byteIdx + 4'd1;
                end
            end
        end
    end

endmodule
