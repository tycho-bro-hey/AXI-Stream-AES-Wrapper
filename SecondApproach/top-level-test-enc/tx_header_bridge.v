`timescale 1ns / 1ps
//
// module: tx_header_bridge
// project: aes-gcm-256 for arty a7-100t
//
// bridges standard axi-stream to the coworker's custom tx header
// handshake protocol (section 7). accepts 8-bit axi-stream slave
// input and a payload length, performs the tx_hdr_valid/tx_hdr_ready
// handshake with the ethernet stack, then passes the axi-stream
// payload through to the coworker's tx_payload_* signals.
//
// two-phase protocol:
//   phase 1: assert tx_hdr_valid + tx_payload_len, wait for tx_hdr_ready
//   phase 2: pass axi-stream bytes to tx_payload_tdata/tvalid/tlast
//
// dependencies: none
//

module tx_header_bridge (
    input wire clk,
    input wire rst,

    // axi-stream slave (from composer or fifo)
    input wire [7:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,

    // payload length input (from composer or top level)
    input wire [15:0] payloadLen,

    // coworker's tx interface (section 7 signals)
    output wire tx_hdr_valid,
    input wire tx_hdr_ready,
    output wire [15:0] tx_payload_len,
    output wire [7:0] tx_payload_tdata,
    output wire tx_payload_tvalid,
    input wire tx_payload_tready,
    output wire tx_payload_tlast
);

    // fsm states
    localparam STATE_IDLE = 2'd0;
    localparam STATE_HDR_SEND = 2'd1;
    localparam STATE_PAYLOAD = 2'd2;

    reg [1:0] state;
    reg [15:0] lenReg; // latched payload length for stable header output

    // combinational outputs: header handshake
    assign tx_hdr_valid = (state == STATE_HDR_SEND);
    assign tx_payload_len = lenReg;

    // combinational outputs: payload pass-through (active only in payload state)
    assign tx_payload_tdata = s_axis_tdata;
    assign tx_payload_tvalid = (state == STATE_PAYLOAD) & s_axis_tvalid;
    assign tx_payload_tlast = (state == STATE_PAYLOAD) & s_axis_tlast;

    // combinational: backpressure pass-through
    assign s_axis_tready = (state == STATE_PAYLOAD) & tx_payload_tready;

    // sequential state machine
    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            lenReg <= 16'd0;
        end
        else begin
            case (state)
                // wait for upstream data to be available
                STATE_IDLE: begin
                    if (s_axis_tvalid) begin
                        lenReg <= payloadLen;
                        state <= STATE_HDR_SEND;
                    end
                end

                // header handshake with ethernet stack
                STATE_HDR_SEND: begin
                    if (tx_hdr_ready) begin
                        state <= STATE_PAYLOAD;
                    end
                end

                // pass payload bytes through
                STATE_PAYLOAD: begin
                    if (s_axis_tvalid && tx_payload_tready && s_axis_tlast) begin
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
