`timescale 1ns / 1ps
//
// module: aes_gcm_core_adapter
// project: aes-gcm-256 for arty a7-100t
//
// wraps the aes_gcm_256 core with axi-stream interfaces. accepts 128-bit
// data blocks via axi-stream slave, drives the core's handshake protocol,
// outputs 128-bit result blocks via axi-stream master. tag on sideband
// output. supports both encrypt (mode=0) and decrypt (mode=1).
// no aad path.
//
// in encrypt mode: slave=plaintext, master=ciphertext
// in decrypt mode: slave=ciphertext, master=plaintext
//   tag_in must be valid before the first block arrives.
//   tag_match/auth_fail are valid after tag_valid pulses.
//
// uses fixed-delay timing per project context section 2.
//
// dependencies: aes_gcm_256
//

module aes_gcm_core_adapter (
    input wire clk,
    input wire rst,

    // axi-stream slave, data input (128-bit)
    // encrypt: plaintext in. decrypt: ciphertext in.
    input wire [127:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output reg s_axis_tready,
    input wire s_axis_tlast,
    input wire [15:0] s_axis_tkeep,

    // axi-stream master, data output (128-bit)
    // encrypt: ciphertext out. decrypt: plaintext out.
    output reg [127:0] m_axis_tdata,
    output reg m_axis_tvalid,
    input wire m_axis_tready,
    output reg m_axis_tlast,
    output reg [15:0] m_axis_tkeep,

    // key and iv (directly wired from key_loader / iv_loader)
    input wire [255:0] key,
    input wire [95:0] iv,

    // mode: 0 = encrypt, 1 = decrypt
    input wire mode,

    // decrypt tag input (must be stable before first block)
    input wire [127:0] tagIn,

    // tag output (sideband, read by tx_stream_composer)
    output reg [127:0] tagOut,
    output reg tagValid,

    // decrypt verification (valid after tag_valid)
    output reg tagMatch,
    output reg authFail,

    // status
    output wire encBusy
);

    // fsm states
    localparam STATE_IDLE = 4'd0;
    localparam STATE_START_CORE = 4'd1;
    localparam STATE_WAIT_INIT = 4'd2;
    localparam STATE_FEED_BLOCK = 4'd3;
    localparam STATE_WAIT_CT = 4'd4;
    localparam STATE_OUTPUT_CT = 4'd5;
    localparam STATE_WAIT_GHASH = 4'd6;
    localparam STATE_ACCEPT_NEXT = 4'd7;
    localparam STATE_WAIT_DONE = 4'd8;
    localparam STATE_OUTPUT_TAG = 4'd9;

    // timing constants
    localparam INIT_WAIT_CYCLES = 8'd25;
    localparam BLOCK_WAIT_CYCLES = 8'd160;

    reg [3:0] state;
    reg [7:0] waitCounter;

    // latched axi-stream input
    reg [127:0] dataReg;
    reg lastReg;
    reg [15:0] keepReg;

    // latched mode and tag for decrypt
    reg modeReg;
    reg [127:0] tagInReg;

    // captured output from core
    reg [127:0] ctReg;
    reg [15:0] ctKeepReg;

    // core interface signals
    reg coreStart;
    reg [127:0] corePtIn;
    reg corePtValid;
    reg [4:0] corePtLen;
    reg corePtLast;
    reg coreFinalize;

    wire coreBusy;
    wire coreDone;
    wire [127:0] coreCtOut;
    wire coreCtValid;
    wire [127:0] coreTag;
    wire coreTagMatch;
    wire coreAuthFail;

    assign encBusy = (state != STATE_IDLE);

    // tkeep to byte count (popcount)
    function [4:0] tkeepToLen;
        input [15:0] keep;
        integer j;
        begin
            tkeepToLen = 5'd0;
            for (j = 0; j < 16; j = j + 1) begin
                tkeepToLen = tkeepToLen + {4'd0, keep[j]};
            end
        end
    endfunction

    // core instantiation
    aes_gcm_256 u_gcm_core (
        .clk(clk),
        .rst(rst),
        .start(coreStart),
        .mode(modeReg),
        .busy(coreBusy),
        .done(coreDone),
        .key(key),
        .iv(iv),
        .aad_in(128'd0),
        .aad_valid(1'b0),
        .aad_len(5'd0),
        .aad_last(1'b0),
        .pt_in(corePtIn),
        .pt_valid(corePtValid),
        .pt_len(corePtLen),
        .pt_last(corePtLast),
        .finalize(coreFinalize),
        .ct_out(coreCtOut),
        .ct_valid(coreCtValid),
        .tag(coreTag),
        .tag_in(tagInReg),
        .tag_match(coreTagMatch),
        .auth_fail(coreAuthFail)
    );

    // main fsm
    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            waitCounter <= 8'd0;
            s_axis_tready <= 1'b0;
            m_axis_tdata <= 128'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            m_axis_tkeep <= 16'd0;
            coreStart <= 1'b0;
            corePtIn <= 128'd0;
            corePtValid <= 1'b0;
            corePtLen <= 5'd0;
            corePtLast <= 1'b0;
            coreFinalize <= 1'b0;
            dataReg <= 128'd0;
            lastReg <= 1'b0;
            keepReg <= 16'd0;
            modeReg <= 1'b0;
            tagInReg <= 128'd0;
            ctReg <= 128'd0;
            ctKeepReg <= 16'd0;
            tagOut <= 128'd0;
            tagValid <= 1'b0;
            tagMatch <= 1'b0;
            authFail <= 1'b0;
        end
        else begin
            // deassert single-cycle pulses
            coreStart <= 1'b0;
            corePtValid <= 1'b0;
            coreFinalize <= 1'b0;

            case (state)
                // wait for first data block
                STATE_IDLE: begin
                    tagValid <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                    s_axis_tready <= 1'b1;
                    if (s_axis_tvalid && s_axis_tready) begin
                        dataReg <= s_axis_tdata;
                        lastReg <= s_axis_tlast;
                        keepReg <= s_axis_tkeep;
                        modeReg <= mode;
                        tagInReg <= tagIn;
                        s_axis_tready <= 1'b0;
                        state <= STATE_START_CORE;
                    end
                end

                // assert start for 1 cycle
                STATE_START_CORE: begin
                    coreStart <= 1'b1;
                    waitCounter <= 8'd0;
                    state <= STATE_WAIT_INIT;
                end

                // wait for h computation + ghash init
                STATE_WAIT_INIT: begin
                    waitCounter <= waitCounter + 8'd1;
                    if (waitCounter >= INIT_WAIT_CYCLES) begin
                        state <= STATE_FEED_BLOCK;
                    end
                end

                // present data to core for 1 cycle
                STATE_FEED_BLOCK: begin
                    corePtIn <= dataReg;
                    corePtValid <= 1'b1;
                    corePtLen <= tkeepToLen(keepReg);
                    corePtLast <= lastReg;
                    waitCounter <= 8'd0;
                    state <= STATE_WAIT_CT;
                end

                // wait for ct_valid pulse from core
                STATE_WAIT_CT: begin
                    waitCounter <= waitCounter + 8'd1;
                    if (coreCtValid) begin
                        ctReg <= coreCtOut;
                        ctKeepReg <= keepReg;
                        state <= STATE_OUTPUT_CT;
                    end
                end

                // present output block on axi-stream master
                STATE_OUTPUT_CT: begin
                    waitCounter <= waitCounter + 8'd1;
                    m_axis_tdata <= ctReg;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast <= lastReg;
                    m_axis_tkeep <= ctKeepReg;
                    if (m_axis_tready && m_axis_tvalid) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast <= 1'b0;
                        if (lastReg) begin
                            state <= STATE_WAIT_DONE;
                        end
                        else begin
                            state <= STATE_WAIT_GHASH;
                        end
                    end
                end

                // wait for ghash processing to complete
                STATE_WAIT_GHASH: begin
                    waitCounter <= waitCounter + 8'd1;
                    if (waitCounter >= BLOCK_WAIT_CYCLES) begin
                        state <= STATE_ACCEPT_NEXT;
                    end
                end

                // accept next data block
                STATE_ACCEPT_NEXT: begin
                    s_axis_tready <= 1'b1;
                    if (s_axis_tvalid && s_axis_tready) begin
                        dataReg <= s_axis_tdata;
                        lastReg <= s_axis_tlast;
                        keepReg <= s_axis_tkeep;
                        s_axis_tready <= 1'b0;
                        state <= STATE_FEED_BLOCK;
                    end
                end

                // wait for core to finish tag computation
                STATE_WAIT_DONE: begin
                    if (coreDone) begin
                        tagOut <= coreTag;
                        tagValid <= 1'b1;
                        tagMatch <= coreTagMatch;
                        authFail <= coreAuthFail;
                        state <= STATE_OUTPUT_TAG;
                    end
                end

                // clear tag valid, return to idle
                STATE_OUTPUT_TAG: begin
                    tagValid <= 1'b0;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
