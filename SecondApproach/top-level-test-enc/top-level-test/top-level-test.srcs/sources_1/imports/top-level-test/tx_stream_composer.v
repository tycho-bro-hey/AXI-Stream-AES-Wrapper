`timescale 1ns / 1ps
//
// module: tx_stream_composer
// project: aes-gcm-256 for arty a7-100t
//
// sequences three sources into a single 8-bit axi-stream output:
//   1. iv bytes (12 bytes from 96-bit register, msb-first)
//   2. ciphertext bytes (n bytes, passed through from slave port)
//   3. tag bytes (16 bytes from 128-bit register, msb-first)
//
// asserts tlast on the final tag byte. triggered by first ct byte
// arriving on the slave port. stalls ct input during iv/tag phases.
//
// outputs are combinational (driven by registered state) to avoid
// pipeline-lag duplicate-byte issues with registered pass-through.
//
// dependencies: none
//

module tx_stream_composer (
    input wire clk,
    input wire rst,

    // axi-stream slave, ct bytes from dwidth converter (8-bit)
    input wire [7:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,

    // axi-stream master, composed output (8-bit)
    output wire [7:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast,

    // iv input (from iv_loader or top level)
    input wire [95:0] iv,

    // tag input (from adapter sideband)
    input wire [127:0] tag,
    input wire tagValid,

    // payload length output (valid after ct pass-through completes)
    output reg [15:0] payloadLen
);

    // fsm states
    localparam STATE_IDLE = 3'd0;
    localparam STATE_SEND_IV = 3'd1;
    localparam STATE_CT_LOAD = 3'd2;
    localparam STATE_CT_SEND = 3'd3;
    localparam STATE_WAIT_TAG = 3'd4;
    localparam STATE_SEND_TAG = 3'd5;

    reg [2:0] state;
    reg [3:0] byteCount; // 0-11 for iv, 0-15 for tag
    reg [15:0] ctByteCount;

    // latched iv for stable output during send
    reg [95:0] ivReg;

    // latched ct byte and last flag
    reg [7:0] ctByteReg;
    reg ctIsLast;

    // tag capture (in case tag arrives before composer needs it)
    reg [127:0] tagReg;
    reg tagCaptured;

    // capture tag whenever it pulses, clear on return to idle
    always @(posedge clk) begin
        if (rst) begin
            tagReg <= 128'd0;
            tagCaptured <= 1'b0;
        end
        else if (state == STATE_IDLE) begin
            tagCaptured <= 1'b0;
        end
        else if (tagValid) begin
            tagReg <= tag;
            tagCaptured <= 1'b1;
        end
    end

    // iv byte selector (combinational, msb-first)
    wire [7:0] ivByte;
    assign ivByte = ivReg[(4'd11 - byteCount) * 8 +: 8];

    // tag byte selector (combinational, msb-first)
    wire [7:0] tagByte;
    assign tagByte = tagReg[(4'd15 - byteCount) * 8 +: 8];

    // combinational output logic
    assign s_axis_tready = (state == STATE_CT_LOAD);
    assign m_axis_tdata = (state == STATE_SEND_IV)  ? ivByte :
                          (state == STATE_CT_SEND)  ? ctByteReg :
                          (state == STATE_SEND_TAG) ? tagByte :
                          8'd0;
    assign m_axis_tvalid = (state == STATE_SEND_IV) ||
                           (state == STATE_CT_SEND) ||
                           (state == STATE_SEND_TAG);
    assign m_axis_tlast = (state == STATE_SEND_TAG) && (byteCount == 4'd15);

    // sequential state machine
    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            byteCount <= 4'd0;
            ctByteCount <= 16'd0;
            ivReg <= 96'd0;
            ctByteReg <= 8'd0;
            ctIsLast <= 1'b0;
            payloadLen <= 16'd0;
        end
        else begin
            case (state)
                // wait for first ct byte to trigger packet composition
                STATE_IDLE: begin
                    if (s_axis_tvalid) begin
                        ivReg <= iv;
                        byteCount <= 4'd0;
                        ctByteCount <= 16'd0;
                        state <= STATE_SEND_IV;
                    end
                end

                // output 12 iv bytes msb-first
                STATE_SEND_IV: begin
                    if (m_axis_tready) begin
                        if (byteCount == 4'd11) begin
                            state <= STATE_CT_LOAD;
                        end
                        else begin
                            byteCount <= byteCount + 4'd1;
                        end
                    end
                end

                // accept one ct byte from slave
                STATE_CT_LOAD: begin
                    if (s_axis_tvalid) begin
                        ctByteReg <= s_axis_tdata;
                        ctIsLast <= s_axis_tlast;
                        ctByteCount <= ctByteCount + 16'd1;
                        state <= STATE_CT_SEND;
                    end
                end

                // present ct byte on master
                STATE_CT_SEND: begin
                    if (m_axis_tready) begin
                        if (ctIsLast) begin
                            payloadLen <= 16'd12 + ctByteCount + 16'd16;
                            state <= STATE_WAIT_TAG;
                        end
                        else begin
                            state <= STATE_CT_LOAD;
                        end
                    end
                end

                // wait for tag from adapter
                STATE_WAIT_TAG: begin
                    if (tagCaptured) begin
                        byteCount <= 4'd0;
                        state <= STATE_SEND_TAG;
                    end
                end

                // output 16 tag bytes msb-first, tlast on last byte
                STATE_SEND_TAG: begin
                    if (m_axis_tready) begin
                        if (byteCount == 4'd15) begin
                            state <= STATE_IDLE;
                        end
                        else begin
                            byteCount <= byteCount + 4'd1;
                        end
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
