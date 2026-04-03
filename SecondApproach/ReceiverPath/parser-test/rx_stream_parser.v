`timescale 1ns / 1ps
//
// module: rx_stream_parser
// project: aes-gcm-256 for arty a7-100t
//
// parses an incoming encrypted packet (8-bit axi-stream) into
// three components:
//   bytes 0-11:         iv  (captured to 96-bit register)
//   bytes 12 to len-17: ct  (passed through as 8-bit axi-stream)
//   bytes len-16 to len-1: tag (captured to 128-bit register)
//
// packet length must be provided before the first byte arrives.
// ct length = packet-len - 28 (12 iv + 16 tag).
// asserts tlast on the last ct byte output.
// pulses iv-valid after iv capture, tag-valid after tag capture.
//
// combinational outputs for ct pass-through (same pattern as
// tx_stream_composer) to avoid pipeline-lag issues.
//
// dependencies: none
//

module rx_stream_parser (
    input wire clk,
    input wire rst,

    // 8-bit axi-stream slave (encrypted packet bytes)
    input wire [7:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,

    // 8-bit axi-stream master (ct bytes only)
    output wire [7:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast,

    // packet length (total bytes: iv + ct + tag)
    input wire [15:0] packetLen,

    // extracted iv
    output reg [95:0] ivOut,
    output reg ivValid,

    // extracted tag
    output reg [127:0] tagOut,
    output reg tagValid
);

    localparam STATE_IDLE = 2'd0;
    localparam STATE_RECV_IV = 2'd1;
    localparam STATE_PASS_CT = 2'd2;
    localparam STATE_RECV_TAG = 2'd3;

    reg [1:0] state;
    reg [3:0] byteIdx;
    reg [15:0] ctLen;
    reg [15:0] ctCount;

    // iv shift register
    reg [95:0] ivShift;

    // tag shift register
    reg [127:0] tagShift;

    // ct pass-through: combinational output (no lag)
    assign s_axis_tready = (state == STATE_IDLE) ||
                           (state == STATE_RECV_IV) ||
                           (state == STATE_PASS_CT && m_axis_tready) ||
                           (state == STATE_RECV_TAG);

    assign m_axis_tdata = s_axis_tdata;
    assign m_axis_tvalid = (state == STATE_PASS_CT) && s_axis_tvalid;
    assign m_axis_tlast = (state == STATE_PASS_CT) && s_axis_tvalid &&
                          (ctCount == ctLen - 16'd1);

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            byteIdx <= 4'd0;
            ctLen <= 16'd0;
            ctCount <= 16'd0;
            ivShift <= 96'd0;
            ivOut <= 96'd0;
            ivValid <= 1'b0;
            tagShift <= 128'd0;
            tagOut <= 128'd0;
            tagValid <= 1'b0;
        end
        else begin
            // clear single-cycle pulses
            ivValid <= 1'b0;
            tagValid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (s_axis_tvalid && packetLen > 16'd28) begin
                        ctLen <= packetLen - 16'd28;
                        ctCount <= 16'd0;
                        // capture first iv byte immediately
                        ivShift <= {88'd0, s_axis_tdata};
                        byteIdx <= 4'd1;
                        state <= STATE_RECV_IV;
                    end
                end

                STATE_RECV_IV: begin
                    if (s_axis_tvalid) begin
                        ivShift <= {ivShift[87:0], s_axis_tdata};
                        if (byteIdx == 4'd11) begin
                            // iv complete, output it
                            ivOut <= {ivShift[87:0], s_axis_tdata};
                            ivValid <= 1'b1;
                            state <= STATE_PASS_CT;
                        end
                        else begin
                            byteIdx <= byteIdx + 4'd1;
                        end
                    end
                end

                STATE_PASS_CT: begin
                    if (s_axis_tvalid && m_axis_tready) begin
                        ctCount <= ctCount + 16'd1;
                        if (ctCount == ctLen - 16'd1) begin
                            // last ct byte accepted, switch to tag
                            byteIdx <= 4'd0;
                            state <= STATE_RECV_TAG;
                        end
                    end
                end

                STATE_RECV_TAG: begin
                    if (s_axis_tvalid) begin
                        tagShift <= {tagShift[119:0], s_axis_tdata};
                        if (byteIdx == 4'd15) begin
                            // tag complete
                            tagOut <= {tagShift[119:0], s_axis_tdata};
                            tagValid <= 1'b1;
                            state <= STATE_IDLE;
                        end
                        else begin
                            byteIdx <= byteIdx + 4'd1;
                        end
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
