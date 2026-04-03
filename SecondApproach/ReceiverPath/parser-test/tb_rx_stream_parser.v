`timescale 1ns / 1ps
//
// module: tb_rx_stream_parser
// project: aes-gcm-256 for arty a7-100t
//
// testbench for rx_stream_parser (stage d1).
// all dut-facing signals driven from clocked always blocks
// using non-blocking assignments (zero active-region races).
//
// test 1: nist tc14 packet (44 bytes: 12 iv + 16 ct + 16 tag)
// test 2: nist tc15 packet (92 bytes: 12 iv + 64 ct + 16 tag)
// test 3: backpressure on ct output
// test 4: back-to-back packets
//
// dependencies: rx_stream_parser
//

module tb_rx_stream_parser;

    reg clk;
    reg rst;

    // dut signals
    reg [7:0] s_axis_tdata;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;

    wire [7:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready;
    wire m_axis_tlast;

    reg [15:0] packetLen;

    wire [95:0] ivOut;
    wire ivValid;
    wire [127:0] tagOut;
    wire tagValid;

    // test infrastructure
    integer passCount;
    integer failCount;
    integer totalTests;

    // ct byte capture
    reg [7:0] ctBytes [0:255];
    reg ctTlast [0:255];
    integer ctCount;
    reg captureRst;

    // iv/tag capture
    reg sawIvValid;
    reg [95:0] capturedIv;
    reg sawTagValid;
    reg [127:0] capturedTag;

    // stream data
    reg [7:0] pktData [0:255];

    // driver control
    reg streamGo;
    reg streamDone;
    reg [15:0] streamLen;
    reg [15:0] streamIdx;

    // backpressure control
    reg bpEnable;
    reg bpToggle;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    rx_stream_parser u_dut (
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
        .packetLen(packetLen),
        .ivOut(ivOut),
        .ivValid(ivValid),
        .tagOut(tagOut),
        .tagValid(tagValid)
    );

    // packet stream driver (clocked, nb, race-free)
    always @(posedge clk) begin
        if (rst) begin
            s_axis_tdata <= 8'd0;
            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
            streamIdx <= 16'd0;
            streamDone <= 1'b0;
        end
        else if (streamGo && !streamDone) begin
            if (!s_axis_tvalid) begin
                s_axis_tdata <= pktData[0];
                s_axis_tvalid <= 1'b1;
                s_axis_tlast <= (streamLen == 16'd1);
                streamIdx <= 16'd0;
            end
            else if (s_axis_tready) begin
                if (s_axis_tlast) begin
                    s_axis_tvalid <= 1'b0;
                    s_axis_tlast <= 1'b0;
                    streamDone <= 1'b1;
                end
                else begin
                    s_axis_tdata <= pktData[streamIdx + 16'd1];
                    s_axis_tlast <= (streamIdx + 16'd1 == streamLen - 16'd1);
                    streamIdx <= streamIdx + 16'd1;
                end
            end
        end
        else if (!streamGo) begin
            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
            streamDone <= 1'b0;
            streamIdx <= 16'd0;
        end
    end

    // ct output capture
    always @(posedge clk) begin
        if (rst || captureRst) begin
            ctCount <= 0;
        end
        else if (m_axis_tvalid && m_axis_tready) begin
            ctBytes[ctCount] <= m_axis_tdata;
            ctTlast[ctCount] <= m_axis_tlast;
            ctCount <= ctCount + 1;
        end
    end

    // iv/tag valid capture
    always @(posedge clk) begin
        if (rst || captureRst) begin
            sawIvValid <= 1'b0;
            capturedIv <= 96'd0;
            sawTagValid <= 1'b0;
            capturedTag <= 128'd0;
        end
        else begin
            if (ivValid) begin
                sawIvValid <= 1'b1;
                capturedIv <= ivOut;
            end
            if (tagValid) begin
                sawTagValid <= 1'b1;
                capturedTag <= tagOut;
            end
        end
    end

    // backpressure on ct output
    always @(posedge clk) begin
        if (rst) begin
            m_axis_tready <= 1'b1;
            bpToggle <= 1'b0;
        end
        else if (bpEnable) begin
            bpToggle <= ~bpToggle;
            m_axis_tready <= ~bpToggle;
        end
        else begin
            m_axis_tready <= 1'b1;
        end
    end

    // helpers
    task do_reset;
    begin
        rst = 1'b1;
        streamGo = 1'b0;
        captureRst = 1'b0;
        bpEnable = 1'b0;
        repeat (5) @(posedge clk);
        #1; rst = 1'b0;
        repeat (2) @(posedge clk);
        #1;
    end
    endtask

    task start_test;
        input [15:0] pktLen;
        input bp;
    begin
        captureRst = 1'b1;
        streamGo = 1'b0;
        @(posedge clk); #1;
        captureRst = 1'b0;
        packetLen = pktLen;
        streamLen = pktLen;
        bpEnable = bp;
        @(posedge clk); #1;
        streamGo = 1'b1;
    end
    endtask

    task wait_done;
        integer timeout;
    begin
        timeout = 0;
        while (!streamDone && timeout < 50000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 50000) begin
            $display("  ERROR: timeout");
            $stop;
        end
        repeat (10) @(posedge clk);
        #1;
        streamGo = 1'b0;
        bpEnable = 1'b0;
        repeat (5) @(posedge clk);
        #1;
    end
    endtask

    // fill packet from iv(96) + ct data + tag(128)
    task fill_96;
        input integer base;
        input [95:0] val;
        integer b;
    begin
        for (b = 0; b < 12; b = b + 1)
            pktData[base + b] = val[(11-b)*8 +: 8];
    end
    endtask

    task fill_128;
        input integer base;
        input [127:0] val;
        integer b;
    begin
        for (b = 0; b < 16; b = b + 1)
            pktData[base + b] = val[(15-b)*8 +: 8];
    end
    endtask

    task check_ct_byte;
        input integer idx;
        input [7:0] expected;
    begin
        totalTests = totalTests + 1;
        if (ctBytes[idx] == expected) begin
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: ct byte[%0d] expected=%h got=%h",
                     idx, expected, ctBytes[idx]);
            failCount = failCount + 1;
        end
    end
    endtask

    // expected ct data arrays
    reg [7:0] expectedCt [0:255];

    task fill_expected_128;
        input integer base;
        input [127:0] val;
        integer b;
    begin
        for (b = 0; b < 16; b = b + 1)
            expectedCt[base + b] = val[(15-b)*8 +: 8];
    end
    endtask

    integer i;

    initial begin
        $display("");
        $display("tb_rx_stream_parser, stage d1 verification");
        $display("");

        passCount = 0;
        failCount = 0;
        totalTests = 0;

        do_reset();

        // test 1: nist tc14 packet (44 bytes)
        // iv  = 000000000000000000000000
        // ct  = cea7403d4d606b6e074ec5d3baf39d18
        // tag = d0d1c8a799996bf0265b98b5d48ab919
        $display("test 1: nist tc14 packet (44 bytes)");

        fill_96(0, 96'h000000000000000000000000);
        fill_128(12, 128'hcea7403d4d606b6e074ec5d3baf39d18);
        fill_128(28, 128'hd0d1c8a799996bf0265b98b5d48ab919);

        fill_expected_128(0, 128'hcea7403d4d606b6e074ec5d3baf39d18);

        start_test(16'd44, 1'b0);
        wait_done();

        // check iv
        totalTests = totalTests + 1;
        if (sawIvValid && capturedIv == 96'h000000000000000000000000) begin
            $display("    PASS: iv extracted");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: iv seen=%b val=%h", sawIvValid, capturedIv);
            failCount = failCount + 1;
        end

        // check tag
        totalTests = totalTests + 1;
        if (sawTagValid && capturedTag == 128'hd0d1c8a799996bf0265b98b5d48ab919) begin
            $display("    PASS: tag extracted");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tag seen=%b val=%h", sawTagValid, capturedTag);
            failCount = failCount + 1;
        end

        // check ct bytes
        totalTests = totalTests + 1;
        if (ctCount == 16) begin
            $display("    PASS: %0d ct bytes", ctCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d ct bytes (expected 16)", ctCount);
            failCount = failCount + 1;
        end

        for (i = 0; i < 16; i = i + 1) check_ct_byte(i, expectedCt[i]);

        // check tlast on last ct byte
        totalTests = totalTests + 1;
        if (ctCount >= 16 && ctTlast[15]) begin
            $display("    PASS: tlast on ct byte 15");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tlast not on ct byte 15");
            failCount = failCount + 1;
        end

        $display("    test 1 complete");

        // test 2: nist tc15 packet (92 bytes)
        // iv  = cafebabefacedbaddecaf888
        // ct  = 522dc1f0...898015ad (64 bytes)
        // tag = b094dac5d93471bdec1a502270e3cc6c
        $display("");
        $display("test 2: nist tc15 packet (92 bytes)");

        fill_96(0, 96'hcafebabefacedbaddecaf888);
        fill_128(12, 128'h522dc1f099567d07f47f37a32a84427d);
        fill_128(28, 128'h643a8cdcbfe5c0c97598a2bd2555d1aa);
        fill_128(44, 128'h8cb08e48590dbb3da7b08b1056828838);
        fill_128(60, 128'hc5f61e6393ba7a0abcc9f662898015ad);
        fill_128(76, 128'hb094dac5d93471bdec1a502270e3cc6c);

        fill_expected_128(0, 128'h522dc1f099567d07f47f37a32a84427d);
        fill_expected_128(16, 128'h643a8cdcbfe5c0c97598a2bd2555d1aa);
        fill_expected_128(32, 128'h8cb08e48590dbb3da7b08b1056828838);
        fill_expected_128(48, 128'hc5f61e6393ba7a0abcc9f662898015ad);

        start_test(16'd92, 1'b0);
        wait_done();

        // check iv
        totalTests = totalTests + 1;
        if (sawIvValid && capturedIv == 96'hcafebabefacedbaddecaf888) begin
            $display("    PASS: iv extracted");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: iv val=%h", capturedIv);
            failCount = failCount + 1;
        end

        // check tag
        totalTests = totalTests + 1;
        if (sawTagValid && capturedTag == 128'hb094dac5d93471bdec1a502270e3cc6c) begin
            $display("    PASS: tag extracted");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tag val=%h", capturedTag);
            failCount = failCount + 1;
        end

        // check ct byte count
        totalTests = totalTests + 1;
        if (ctCount == 64) begin
            $display("    PASS: %0d ct bytes", ctCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d ct bytes (expected 64)", ctCount);
            failCount = failCount + 1;
        end

        for (i = 0; i < 64; i = i + 1) check_ct_byte(i, expectedCt[i]);

        // check tlast
        totalTests = totalTests + 1;
        if (ctCount >= 64 && ctTlast[63]) begin
            $display("    PASS: tlast on ct byte 63");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tlast not on ct byte 63");
            failCount = failCount + 1;
        end

        $display("    test 2 complete");

        // test 3: tc14 packet with backpressure on ct output
        $display("");
        $display("test 3: tc14 with backpressure");

        fill_96(0, 96'h000000000000000000000000);
        fill_128(12, 128'hcea7403d4d606b6e074ec5d3baf39d18);
        fill_128(28, 128'hd0d1c8a799996bf0265b98b5d48ab919);
        fill_expected_128(0, 128'hcea7403d4d606b6e074ec5d3baf39d18);

        start_test(16'd44, 1'b1);
        wait_done();

        totalTests = totalTests + 1;
        if (sawIvValid && capturedIv == 96'h000000000000000000000000) begin
            $display("    PASS: iv with backpressure");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: iv val=%h", capturedIv);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (ctCount == 16) begin
            $display("    PASS: %0d ct bytes with backpressure", ctCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d ct bytes (expected 16)", ctCount);
            failCount = failCount + 1;
        end

        for (i = 0; i < 16; i = i + 1) check_ct_byte(i, expectedCt[i]);

        totalTests = totalTests + 1;
        if (sawTagValid && capturedTag == 128'hd0d1c8a799996bf0265b98b5d48ab919) begin
            $display("    PASS: tag with backpressure");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tag val=%h", capturedTag);
            failCount = failCount + 1;
        end

        $display("    test 3 complete");

        // test 4: back-to-back packets (no reset)
        $display("");
        $display("test 4: back-to-back packets");

        // packet 1 (tc14)
        fill_96(0, 96'h000000000000000000000000);
        fill_128(12, 128'hcea7403d4d606b6e074ec5d3baf39d18);
        fill_128(28, 128'hd0d1c8a799996bf0265b98b5d48ab919);
        fill_expected_128(0, 128'hcea7403d4d606b6e074ec5d3baf39d18);

        start_test(16'd44, 1'b0);
        wait_done();

        totalTests = totalTests + 1;
        if (ctCount == 16 && sawIvValid && sawTagValid) begin
            $display("    PASS: packet 1 complete");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: packet 1 ct=%0d iv=%b tag=%b",
                     ctCount, sawIvValid, sawTagValid);
            failCount = failCount + 1;
        end

        // packet 2 (different iv, same ct/tag for simplicity)
        fill_96(0, 96'hcafebabefacedbaddecaf888);
        fill_128(12, 128'hcea7403d4d606b6e074ec5d3baf39d18);
        fill_128(28, 128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA);

        start_test(16'd44, 1'b0);
        wait_done();

        totalTests = totalTests + 1;
        if (capturedIv == 96'hcafebabefacedbaddecaf888) begin
            $display("    PASS: packet 2 iv");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: packet 2 iv=%h", capturedIv);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (capturedTag == 128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA) begin
            $display("    PASS: packet 2 tag");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: packet 2 tag=%h", capturedTag);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (ctCount == 16) begin
            $display("    PASS: packet 2 ct bytes");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: packet 2 ct=%0d", ctCount);
            failCount = failCount + 1;
        end

        $display("    test 4 complete");

        // summary
        $display("");
        $display("summary: %0d passed, %0d failed out of %0d tests",
                 passCount, failCount, totalTests);

        if (failCount == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $display("");
        $finish;
    end

endmodule
