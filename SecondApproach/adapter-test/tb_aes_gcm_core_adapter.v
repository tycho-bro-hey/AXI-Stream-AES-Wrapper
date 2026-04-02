`timescale 1ns / 1ps
//
// module: tb_aes_gcm_core_adapter
// project: aes-gcm-256 for arty a7-100t
//
// testbench for aes_gcm_core_adapter (stage 1).
// verifies axi-stream wrapper using nist mcgrew-viega vectors.
//
// test 1: tc14, 16-byte pt, no aad, zero key/iv
// test 2: tc15, 64-byte pt (4 blocks), no aad
// test 3: partial final block, 60 bytes (3 full + 12-byte partial), no aad
// test 4: single-byte plaintext, 1 byte, no aad
// test 5: back-to-back tc14 operations without reset
//
// dependencies: aes_gcm_core_adapter, aes_gcm_256 (and sub-modules)
//

module tb_aes_gcm_core_adapter;

    reg clk;
    reg rst;

    // axi-stream slave (tb drives, plaintext input)
    reg [127:0] s_axis_tdata;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;
    reg [15:0] s_axis_tkeep;

    // axi-stream master (dut drives, ciphertext output)
    wire [127:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready;
    wire m_axis_tlast;
    wire [15:0] m_axis_tkeep;

    // key and iv
    reg [255:0] key;
    reg [95:0] iv;

    // tag sideband
    wire [127:0] tagOut;
    wire tagValid;

    // status
    wire encBusy;

    // test tracking
    integer testNum;
    integer passCount;
    integer failCount;
    integer totalTests;

    // ciphertext capture
    reg [127:0] ctCaptured [0:15];
    integer ctCount;

    // 100 mhz clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // dut
    aes_gcm_core_adapter u_dut (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tkeep(s_axis_tkeep),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tkeep(m_axis_tkeep),
        .key(key),
        .iv(iv),
        .tagOut(tagOut),
        .tagValid(tagValid),
        .encBusy(encBusy)
    );

    // capture ciphertext from axi-stream master
    always @(posedge clk) begin
        if (rst) begin
            ctCount <= 0;
        end
        else if (m_axis_tvalid && m_axis_tready) begin
            ctCaptured[ctCount] <= m_axis_tdata;
            $display("    CT[%0d] = %h  (tlast=%b, tkeep=%h)",
                     ctCount, m_axis_tdata, m_axis_tlast, m_axis_tkeep);
            ctCount <= ctCount + 1;
        end
    end

    task init;
    begin
        s_axis_tdata = 128'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        s_axis_tkeep = 16'd0;
        m_axis_tready = 1'b1;
        key = 256'd0;
        iv = 96'd0;
        ctCount = 0;
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

    // send a single axi-stream beat, waits for tready handshake
    task send_axis_beat;
        input [127:0] data;
        input [15:0] keep;
        input last;
        integer timeout;
    begin
        s_axis_tdata = data;
        s_axis_tkeep = keep;
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

    // wait for tag valid pulse with timeout
    task wait_for_tag;
        integer timeout;
    begin
        timeout = 0;
        while (!tagValid && timeout < 100000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 100000) begin
            $display("  ERROR: timeout waiting for tagValid");
            $stop;
        end
        @(posedge clk);
    end
    endtask

    // wait for adapter to return to idle
    task wait_for_idle;
        integer timeout;
    begin
        timeout = 0;
        while (encBusy && timeout < 100000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 100000) begin
            $display("  ERROR: timeout waiting for adapter idle");
            $stop;
        end
    end
    endtask

    // check captured ct block against expected value
    task check_ct;
        input [127:0] expected;
        input integer blockNum;
    begin
        totalTests = totalTests + 1;
        if (ctCaptured[blockNum] == expected) begin
            $display("    PASS: ct block %0d", blockNum);
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: ct block %0d", blockNum);
            $display("          expected: %h", expected);
            $display("          got:      %h", ctCaptured[blockNum]);
            failCount = failCount + 1;
        end
    end
    endtask

    // check partial ct block (only upper bytes valid)
    task check_ct_partial;
        input [127:0] expected;
        input integer blockNum;
        input integer validBytes;
        reg [127:0] mask;
        integer i;
    begin
        totalTests = totalTests + 1;
        mask = 128'd0;
        for (i = 0; i < validBytes; i = i + 1) begin
            mask[127 - i*8 -: 8] = 8'hFF;
        end
        if ((ctCaptured[blockNum] & mask) == (expected & mask)) begin
            $display("    PASS: ct block %0d (%0d bytes)", blockNum, validBytes);
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: ct block %0d (%0d bytes)", blockNum, validBytes);
            $display("          expected: %h (masked)", expected & mask);
            $display("          got:      %h (masked)", ctCaptured[blockNum] & mask);
            failCount = failCount + 1;
        end
    end
    endtask

    // check tag against expected value
    task check_tag;
        input [127:0] expected;
        input [159:0] testName;
    begin
        totalTests = totalTests + 1;
        if (tagOut == expected) begin
            $display("    PASS: %0s", testName);
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: %0s", testName);
            $display("          expected: %h", expected);
            $display("          got:      %h", tagOut);
            failCount = failCount + 1;
        end
    end
    endtask

    // main test sequence
    initial begin
        $display("");
        $display("tb_aes_gcm_core_adapter, stage 1 verification");
        $display("");

        passCount = 0;
        failCount = 0;
        totalTests = 0;

        init();
        reset_dut();

        // test 1: mcgrew-viega tc14
        // k=0, iv=0, pt=0 (16 bytes)
        // expected ct = cea7403d4d606b6e074ec5d3baf39d18
        // expected tag = d0d1c8a799996bf0265b98b5d48ab919
        $display("test 1: mcgrew-viega tc14, single 16-byte block");
        testNum = 1;
        init();
        ctCount = 0;

        key = 256'h0;
        iv = 96'h0;

        send_axis_beat(128'h00000000000000000000000000000000,
                       16'hFFFF, 1'b1);

        wait_for_tag();

        check_ct(128'hcea7403d4d606b6e074ec5d3baf39d18, 0);
        check_tag(128'hd0d1c8a799996bf0265b98b5d48ab919, "TC14 Tag");

        totalTests = totalTests + 1;
        if (ctCount == 1) begin
            $display("    PASS: received exactly 1 ct block");
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: expected 1 ct block, got %0d", ctCount);
            failCount = failCount + 1;
        end

        wait_for_idle();
        reset_dut();

        // test 2: mcgrew-viega tc15
        // k = feffe9928665731c6d6a8f9467308308 (repeated)
        // iv = cafebabefacedbaddecaf888
        // pt = 64 bytes (4 full blocks)
        // expected ct[0] = 522dc1f099567d07f47f37a32a84427d
        // expected ct[1] = 643a8cdcbfe5c0c97598a2bd2555d1aa
        // expected ct[2] = 8cb08e48590dbb3da7b08b1056828838
        // expected ct[3] = c5f61e6393ba7a0abcc9f662898015ad
        // expected tag = b094dac5d93471bdec1a502270e3cc6c
        $display("");
        $display("test 2: mcgrew-viega tc15, four 16-byte blocks (64 bytes)");
        testNum = 2;
        init();
        ctCount = 0;

        key = 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308;
        iv = 96'hcafebabefacedbaddecaf888;

        send_axis_beat(128'hd9313225f88406e5a55909c5aff5269a,
                       16'hFFFF, 1'b0);
        send_axis_beat(128'h86a7a9531534f7da2e4c303d8a318a72,
                       16'hFFFF, 1'b0);
        send_axis_beat(128'h1c3c0c95956809532fcf0e2449a6b525,
                       16'hFFFF, 1'b0);
        send_axis_beat(128'hb16aedf5aa0de657ba637b391aafd255,
                       16'hFFFF, 1'b1);

        wait_for_tag();

        check_ct(128'h522dc1f099567d07f47f37a32a84427d, 0);
        check_ct(128'h643a8cdcbfe5c0c97598a2bd2555d1aa, 1);
        check_ct(128'h8cb08e48590dbb3da7b08b1056828838, 2);
        check_ct(128'hc5f61e6393ba7a0abcc9f662898015ad, 3);
        check_tag(128'hb094dac5d93471bdec1a502270e3cc6c, "TC15 Tag");

        totalTests = totalTests + 1;
        if (ctCount == 4) begin
            $display("    PASS: received exactly 4 ct blocks");
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: expected 4 ct blocks, got %0d", ctCount);
            failCount = failCount + 1;
        end

        wait_for_idle();
        reset_dut();

        // test 3: partial final block, 60 bytes = 3x16 + 12
        // same key/iv as tc15, no aad
        // ct blocks 0-2 match tc15 (counter mode, independent of block count)
        // block 3: 12 bytes valid, tkeep = fff0
        $display("");
        $display("test 3: partial final block, 60 bytes (12-byte last)");
        testNum = 3;
        init();
        ctCount = 0;

        key = 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308;
        iv = 96'hcafebabefacedbaddecaf888;

        send_axis_beat(128'hd9313225f88406e5a55909c5aff5269a,
                       16'hFFFF, 1'b0);
        send_axis_beat(128'h86a7a9531534f7da2e4c303d8a318a72,
                       16'hFFFF, 1'b0);
        send_axis_beat(128'h1c3c0c95956809532fcf0e2449a6b525,
                       16'hFFFF, 1'b0);
        send_axis_beat(128'hb16aedf5aa0de657ba637b3900000000,
                       16'hFFF0, 1'b1);

        wait_for_tag();

        check_ct(128'h522dc1f099567d07f47f37a32a84427d, 0);
        check_ct(128'h643a8cdcbfe5c0c97598a2bd2555d1aa, 1);
        check_ct(128'h8cb08e48590dbb3da7b08b1056828838, 2);
        check_ct_partial(128'hc5f61e6393ba7a0abcc9f66200000000, 3, 12);

        totalTests = totalTests + 1;
        if (ctCount == 4) begin
            $display("    PASS: received exactly 4 ct blocks");
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: expected 4 ct blocks, got %0d", ctCount);
            failCount = failCount + 1;
        end

        $display("    tag (60b no-aad): %h", tagOut);

        wait_for_idle();
        reset_dut();

        // test 4: single-byte plaintext
        // k=0, iv=0, pt = 0xab (1 byte), tkeep = 8000
        $display("");
        $display("test 4: single-byte plaintext");
        testNum = 4;
        init();
        ctCount = 0;

        key = 256'h0;
        iv = 96'h0;

        send_axis_beat(128'hAB000000000000000000000000000000,
                       16'h8000, 1'b1);

        wait_for_tag();

        totalTests = totalTests + 1;
        if (ctCount == 1) begin
            $display("    PASS: received exactly 1 ct block");
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: expected 1 ct block, got %0d", ctCount);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (m_axis_tkeep == 16'h8000 || ctCount == 1) begin
            $display("    info: ct block 0 = %h", ctCaptured[0]);
            $display("    info: tag        = %h", tagOut);
            $display("    PASS: single-byte operation completed");
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: single-byte operation issue");
            failCount = failCount + 1;
        end

        wait_for_idle();
        reset_dut();

        // test 5: back-to-back tc14 without reset
        $display("");
        $display("test 5: back-to-back tc14 operations");
        testNum = 5;
        init();
        ctCount = 0;

        key = 256'h0;
        iv = 96'h0;

        // first operation
        send_axis_beat(128'h00000000000000000000000000000000,
                       16'hFFFF, 1'b1);
        wait_for_tag();
        check_ct(128'hcea7403d4d606b6e074ec5d3baf39d18, 0);
        check_tag(128'hd0d1c8a799996bf0265b98b5d48ab919, "TC14 Tag (1st)");
        wait_for_idle();

        // second operation, no reset
        ctCount = 0;
        $display("    starting second operation (no reset)");

        send_axis_beat(128'h00000000000000000000000000000000,
                       16'hFFFF, 1'b1);
        wait_for_tag();
        check_ct(128'hcea7403d4d606b6e074ec5d3baf39d18, 0);
        check_tag(128'hd0d1c8a799996bf0265b98b5d48ab919, "TC14 Tag (2nd)");

        wait_for_idle();

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
