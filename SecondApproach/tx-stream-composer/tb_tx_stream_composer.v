`timescale 1ns / 1ps
//
// module: tb_tx_stream_composer
// project: aes-gcm-256 for arty a7-100t
//
// testbench for tx_stream_composer (stage 2).
// verifies iv + ct + tag byte sequencing on 8-bit axi-stream output.
//
// test 1: 16 ct bytes (1 block), known nist tc15 block 0 values
// test 2: 1 ct byte, minimal packet
// test 3: 64 ct bytes (4 blocks), full nist tc15
// test 4: backpressure during iv and tag output
//
// dependencies: tx_stream_composer
//

module tb_tx_stream_composer;

    reg clk;
    reg rst;

    // axi-stream slave (tb drives, ct bytes)
    reg [7:0] s_axis_tdata;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;

    // axi-stream master (dut drives, composed output)
    wire [7:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready;
    wire m_axis_tlast;

    // iv, tag, tag valid
    reg [95:0] iv;
    reg [127:0] tag;
    reg tagValid;

    // payload length output
    wire [15:0] payloadLen;

    // test tracking
    integer passCount;
    integer failCount;
    integer totalTests;

    // output capture
    reg [7:0] outBytes [0:255];
    integer outCount;
    reg outTlast [0:255];

    // 100 mhz clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // dut
    tx_stream_composer u_dut (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .iv(iv),
        .tag(tag),
        .tagValid(tagValid),
        .payloadLen(payloadLen)
    );

    // capture output bytes
    always @(posedge clk) begin
        if (rst) begin
            outCount <= 0;
        end
        else if (m_axis_tvalid && m_axis_tready) begin
            outBytes[outCount] <= m_axis_tdata;
            outTlast[outCount] <= m_axis_tlast;
            outCount <= outCount + 1;
        end
    end

    task init;
    begin
        s_axis_tdata = 8'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        m_axis_tready = 1'b1;
        iv = 96'd0;
        tag = 128'd0;
        tagValid = 1'b0;
        outCount = 0;
    end
    endtask

    task reset_dut;
    begin
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
    end
    endtask

    // send one ct byte on slave port, wait for handshake
    task send_ct_byte;
        input [7:0] data;
        input last;
        integer timeout;
    begin
        s_axis_tdata = data;
        s_axis_tlast = last;
        s_axis_tvalid = 1'b1;
        timeout = 0;
        while (!(s_axis_tvalid && s_axis_tready) && timeout < 50000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 50000) begin
            $display("  ERROR: timeout waiting for s_axis_tready");
            $stop;
        end
        @(posedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
    endtask

    // wait for composer to return to idle
    task wait_for_idle;
        integer timeout;
    begin
        timeout = 0;
        repeat (5) @(posedge clk);
        while (m_axis_tvalid && timeout < 10000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat (2) @(posedge clk);
    end
    endtask

    // pulse tag valid for 1 cycle
    task pulse_tag;
        input [127:0] tagVal;
    begin
        tag = tagVal;
        tagValid = 1'b1;
        @(posedge clk);
        tagValid = 1'b0;
    end
    endtask

    // check a single output byte
    task check_byte;
        input integer idx;
        input [7:0] expected;
        input [159:0] label;
    begin
        totalTests = totalTests + 1;
        if (outBytes[idx] == expected) begin
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: %0s byte[%0d] expected=%h got=%h",
                     label, idx, expected, outBytes[idx]);
            failCount = failCount + 1;
        end
    end
    endtask

    // check tlast on a specific output byte
    task check_tlast;
        input integer idx;
        input expectedTlast;
        input [159:0] label;
    begin
        totalTests = totalTests + 1;
        if (outTlast[idx] == expectedTlast) begin
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: %0s tlast[%0d] expected=%b got=%b",
                     label, idx, expectedTlast, outTlast[idx]);
            failCount = failCount + 1;
        end
    end
    endtask

    // check iv bytes in output (12 bytes starting at index 0)
    task check_iv_bytes;
        input [95:0] expectedIv;
        integer i;
    begin
        for (i = 0; i < 12; i = i + 1) begin
            check_byte(i, expectedIv[(11 - i) * 8 +: 8], "iv");
            check_tlast(i, 1'b0, "iv");
        end
    end
    endtask

    // check tag bytes in output (16 bytes starting at offset)
    task check_tag_bytes;
        input integer offset;
        input [127:0] expectedTag;
        integer i;
    begin
        for (i = 0; i < 16; i = i + 1) begin
            check_byte(offset + i, expectedTag[(15 - i) * 8 +: 8], "tag");
            if (i == 15)
                check_tlast(offset + i, 1'b1, "tag last");
            else
                check_tlast(offset + i, 1'b0, "tag");
        end
    end
    endtask

    integer i;

    // known ct bytes from nist tc15 block 0: 522dc1f099567d07f47f37a32a84427d
    reg [7:0] tc15_ct_block0 [0:15];

    // all 64 ct bytes from nist tc15
    reg [7:0] tc15_ct_all [0:63];

    initial begin
        // tc15 block 0
        tc15_ct_block0[0]  = 8'h52; tc15_ct_block0[1]  = 8'h2d;
        tc15_ct_block0[2]  = 8'hc1; tc15_ct_block0[3]  = 8'hf0;
        tc15_ct_block0[4]  = 8'h99; tc15_ct_block0[5]  = 8'h56;
        tc15_ct_block0[6]  = 8'h7d; tc15_ct_block0[7]  = 8'h07;
        tc15_ct_block0[8]  = 8'hf4; tc15_ct_block0[9]  = 8'h7f;
        tc15_ct_block0[10] = 8'h37; tc15_ct_block0[11] = 8'ha3;
        tc15_ct_block0[12] = 8'h2a; tc15_ct_block0[13] = 8'h84;
        tc15_ct_block0[14] = 8'h42; tc15_ct_block0[15] = 8'h7d;

        // tc15 all 4 blocks (64 bytes)
        // block 0: 522dc1f099567d07f47f37a32a84427d
        tc15_ct_all[0]  = 8'h52; tc15_ct_all[1]  = 8'h2d;
        tc15_ct_all[2]  = 8'hc1; tc15_ct_all[3]  = 8'hf0;
        tc15_ct_all[4]  = 8'h99; tc15_ct_all[5]  = 8'h56;
        tc15_ct_all[6]  = 8'h7d; tc15_ct_all[7]  = 8'h07;
        tc15_ct_all[8]  = 8'hf4; tc15_ct_all[9]  = 8'h7f;
        tc15_ct_all[10] = 8'h37; tc15_ct_all[11] = 8'ha3;
        tc15_ct_all[12] = 8'h2a; tc15_ct_all[13] = 8'h84;
        tc15_ct_all[14] = 8'h42; tc15_ct_all[15] = 8'h7d;
        // block 1: 643a8cdcbfe5c0c97598a2bd2555d1aa
        tc15_ct_all[16] = 8'h64; tc15_ct_all[17] = 8'h3a;
        tc15_ct_all[18] = 8'h8c; tc15_ct_all[19] = 8'hdc;
        tc15_ct_all[20] = 8'hbf; tc15_ct_all[21] = 8'he5;
        tc15_ct_all[22] = 8'hc0; tc15_ct_all[23] = 8'hc9;
        tc15_ct_all[24] = 8'h75; tc15_ct_all[25] = 8'h98;
        tc15_ct_all[26] = 8'ha2; tc15_ct_all[27] = 8'hbd;
        tc15_ct_all[28] = 8'h25; tc15_ct_all[29] = 8'h55;
        tc15_ct_all[30] = 8'hd1; tc15_ct_all[31] = 8'haa;
        // block 2: 8cb08e48590dbb3da7b08b1056828838
        tc15_ct_all[32] = 8'h8c; tc15_ct_all[33] = 8'hb0;
        tc15_ct_all[34] = 8'h8e; tc15_ct_all[35] = 8'h48;
        tc15_ct_all[36] = 8'h59; tc15_ct_all[37] = 8'h0d;
        tc15_ct_all[38] = 8'hbb; tc15_ct_all[39] = 8'h3d;
        tc15_ct_all[40] = 8'ha7; tc15_ct_all[41] = 8'hb0;
        tc15_ct_all[42] = 8'h8b; tc15_ct_all[43] = 8'h10;
        tc15_ct_all[44] = 8'h56; tc15_ct_all[45] = 8'h82;
        tc15_ct_all[46] = 8'h88; tc15_ct_all[47] = 8'h38;
        // block 3: c5f61e6393ba7a0abcc9f662898015ad
        tc15_ct_all[48] = 8'hc5; tc15_ct_all[49] = 8'hf6;
        tc15_ct_all[50] = 8'h1e; tc15_ct_all[51] = 8'h63;
        tc15_ct_all[52] = 8'h93; tc15_ct_all[53] = 8'hba;
        tc15_ct_all[54] = 8'h7a; tc15_ct_all[55] = 8'h0a;
        tc15_ct_all[56] = 8'hbc; tc15_ct_all[57] = 8'hc9;
        tc15_ct_all[58] = 8'hf6; tc15_ct_all[59] = 8'h62;
        tc15_ct_all[60] = 8'h89; tc15_ct_all[61] = 8'h80;
        tc15_ct_all[62] = 8'h15; tc15_ct_all[63] = 8'had;
    end

    // main test sequence
    initial begin
        $display("");
        $display("tb_tx_stream_composer, stage 2 verification");
        $display("");

        passCount = 0;
        failCount = 0;
        totalTests = 0;

        init();
        reset_dut();

        // test 1: 16 ct bytes (1 block)
        // iv = cafebabefacedbaddecaf888
        // tag = b094dac5d93471bdec1a502270e3cc6c
        // expected output: iv(12) + ct(16) + tag(16) = 44 bytes
        $display("test 1: 16 ct bytes (1 block), 44 bytes total");
        init();
        outCount = 0;

        iv = 96'hcafebabefacedbaddecaf888;

        for (i = 0; i < 16; i = i + 1) begin
            send_ct_byte(tc15_ct_block0[i], (i == 15));
        end

        repeat (20) @(posedge clk);
        pulse_tag(128'hb094dac5d93471bdec1a502270e3cc6c);

        wait_for_idle();

        totalTests = totalTests + 1;
        if (outCount == 44) begin
            $display("    PASS: output %0d bytes (expected 44)", outCount);
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: output %0d bytes (expected 44)", outCount);
            failCount = failCount + 1;
        end

        check_iv_bytes(96'hcafebabefacedbaddecaf888);

        for (i = 0; i < 16; i = i + 1) begin
            check_byte(12 + i, tc15_ct_block0[i], "ct");
            check_tlast(12 + i, 1'b0, "ct");
        end

        check_tag_bytes(28, 128'hb094dac5d93471bdec1a502270e3cc6c);

        totalTests = totalTests + 1;
        if (payloadLen == 16'd44) begin
            $display("    PASS: payloadLen = %0d", payloadLen);
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: payloadLen = %0d (expected 44)", payloadLen);
            failCount = failCount + 1;
        end

        $display("    test 1 complete");
        reset_dut();

        // test 2: 1 ct byte, minimal packet
        // iv = 000000000000000000000001
        // tag = aaaabbbbccccddddeeee111122223333
        // expected output: iv(12) + ct(1) + tag(16) = 29 bytes
        $display("");
        $display("test 2: 1 ct byte, 29 bytes total");
        init();
        outCount = 0;

        iv = 96'h000000000000000000000001;

        send_ct_byte(8'hAB, 1'b1);

        repeat (20) @(posedge clk);
        pulse_tag(128'hAAAABBBBCCCCDDDDEEEE111122223333);

        wait_for_idle();

        totalTests = totalTests + 1;
        if (outCount == 29) begin
            $display("    PASS: output %0d bytes (expected 29)", outCount);
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: output %0d bytes (expected 29)", outCount);
            failCount = failCount + 1;
        end

        check_byte(11, 8'h01, "iv lsb");
        check_byte(12, 8'hAB, "ct");
        check_tlast(12, 1'b0, "ct");
        check_tag_bytes(13, 128'hAAAABBBBCCCCDDDDEEEE111122223333);

        totalTests = totalTests + 1;
        if (payloadLen == 16'd29) begin
            $display("    PASS: payloadLen = %0d", payloadLen);
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: payloadLen = %0d (expected 29)", payloadLen);
            failCount = failCount + 1;
        end

        $display("    test 2 complete");
        reset_dut();

        // test 3: 64 ct bytes (4 blocks), full nist tc15
        // expected output: iv(12) + ct(64) + tag(16) = 92 bytes
        $display("");
        $display("test 3: 64 ct bytes (4 blocks), 92 bytes total");
        init();
        outCount = 0;

        iv = 96'hcafebabefacedbaddecaf888;

        for (i = 0; i < 64; i = i + 1) begin
            send_ct_byte(tc15_ct_all[i], (i == 63));
        end

        repeat (20) @(posedge clk);
        pulse_tag(128'hb094dac5d93471bdec1a502270e3cc6c);

        wait_for_idle();

        totalTests = totalTests + 1;
        if (outCount == 92) begin
            $display("    PASS: output %0d bytes (expected 92)", outCount);
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: output %0d bytes (expected 92)", outCount);
            failCount = failCount + 1;
        end

        check_iv_bytes(96'hcafebabefacedbaddecaf888);

        for (i = 0; i < 64; i = i + 1) begin
            check_byte(12 + i, tc15_ct_all[i], "ct");
        end

        check_tag_bytes(76, 128'hb094dac5d93471bdec1a502270e3cc6c);

        for (i = 12; i < 76; i = i + 1) begin
            check_tlast(i, 1'b0, "ct");
        end

        totalTests = totalTests + 1;
        if (payloadLen == 16'd92) begin
            $display("    PASS: payloadLen = %0d", payloadLen);
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: payloadLen = %0d (expected 92)", payloadLen);
            failCount = failCount + 1;
        end

        $display("    test 3 complete");
        reset_dut();

        // test 4: backpressure during iv and tag phases
        $display("");
        $display("test 4: backpressure during iv and tag output");
        init();
        outCount = 0;
        m_axis_tready = 1'b0;

        iv = 96'hcafebabefacedbaddecaf888;

        fork
            begin : backpressure_gen
                integer bp;
                for (bp = 0; bp < 500; bp = bp + 1) begin
                    @(posedge clk);
                    m_axis_tready = ~m_axis_tready;
                end
                m_axis_tready = 1'b1;
            end
            begin : data_gen
                for (i = 0; i < 16; i = i + 1) begin
                    send_ct_byte(tc15_ct_block0[i], (i == 15));
                end
                repeat (20) @(posedge clk);
                pulse_tag(128'hb094dac5d93471bdec1a502270e3cc6c);
            end
        join

        wait_for_idle();

        totalTests = totalTests + 1;
        if (outCount == 44) begin
            $display("    PASS: output %0d bytes with backpressure (expected 44)", outCount);
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: output %0d bytes with backpressure (expected 44)", outCount);
            failCount = failCount + 1;
        end

        check_iv_bytes(96'hcafebabefacedbaddecaf888);
        check_tag_bytes(28, 128'hb094dac5d93471bdec1a502270e3cc6c);

        $display("    test 4 complete");

        // summary
        $display("");
        $display("summary: %0d passed, %0d failed out of %0d tests",
                 passCount, failCount, totalTests);

        if (failCount == 0) begin
            $display("ALL TESTS PASSED");
        end
        else begin
            $display("SOME TESTS FAILED");
        end

        $display("");
        $finish;
    end

endmodule
