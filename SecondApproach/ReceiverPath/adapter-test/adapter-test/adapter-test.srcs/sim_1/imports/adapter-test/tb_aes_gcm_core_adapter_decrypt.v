`timescale 1ns / 1ps
//
// module: tb_aes_gcm_core_adapter_decrypt
// project: aes-gcm-256 for arty a7-100t
//
// testbench for updated aes_gcm_core_adapter with decrypt support
// (stage d2). uses clocked always blocks for signal driving.
//
// test 1: encrypt regression (nist tc14, mode=0)
// test 2: decrypt nist tc14 (single block, mode=1)
// test 3: decrypt nist tc15 (4 blocks, mode=1)
// test 4: decrypt with corrupted tag (auth fail)
//
// dependencies: aes_gcm_core_adapter, aes_gcm_256 + sub-modules
//

module tb_aes_gcm_core_adapter_decrypt;

    reg clk;
    reg rst;

    reg [127:0] s_axis_tdata;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;
    reg [15:0] s_axis_tkeep;

    wire [127:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready;
    wire m_axis_tlast;
    wire [15:0] m_axis_tkeep;

    reg [255:0] key;
    reg [95:0] iv;
    reg mode;
    reg [127:0] tagIn;

    wire [127:0] tagOut;
    wire tagValid;
    wire tagMatch;
    wire authFail;
    wire encBusy;

    integer passCount;
    integer failCount;
    integer totalTests;

    // output capture
    reg [127:0] outBlocks [0:15];
    integer outCount;
    reg sawTagValid;
    reg [127:0] capturedTag;
    reg capturedTagMatch;
    reg capturedAuthFail;
    reg captureRst;

    // block driver control
    reg [127:0] inBlocks [0:15];
    reg [15:0] inKeep [0:15];
    reg [3:0] blockCount;
    reg driverGo;
    reg driverDone;
    reg [3:0] driverIdx;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

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
        .mode(mode),
        .tagIn(tagIn),
        .tagOut(tagOut),
        .tagValid(tagValid),
        .tagMatch(tagMatch),
        .authFail(authFail),
        .encBusy(encBusy)
    );

    // block driver (clocked, nb, race-free)
    always @(posedge clk) begin
        if (rst) begin
            s_axis_tdata <= 128'd0;
            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
            s_axis_tkeep <= 16'd0;
            driverIdx <= 4'd0;
            driverDone <= 1'b0;
        end
        else if (driverGo && !driverDone) begin
            if (!s_axis_tvalid) begin
                s_axis_tdata <= inBlocks[0];
                s_axis_tvalid <= 1'b1;
                s_axis_tkeep <= inKeep[0];
                s_axis_tlast <= (blockCount == 4'd1);
                driverIdx <= 4'd0;
            end
            else if (s_axis_tready) begin
                if (driverIdx == blockCount - 4'd1) begin
                    s_axis_tvalid <= 1'b0;
                    s_axis_tlast <= 1'b0;
                    driverDone <= 1'b1;
                end
                else begin
                    driverIdx <= driverIdx + 4'd1;
                    s_axis_tdata <= inBlocks[driverIdx + 4'd1];
                    s_axis_tkeep <= inKeep[driverIdx + 4'd1];
                    s_axis_tlast <= (driverIdx + 4'd1 == blockCount - 4'd1);
                end
            end
        end
        else if (!driverGo) begin
            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
            driverDone <= 1'b0;
            driverIdx <= 4'd0;
        end
    end

    // output capture
    always @(posedge clk) begin
        if (rst || captureRst) begin
            outCount <= 0;
        end
        else if (m_axis_tvalid && m_axis_tready) begin
            outBlocks[outCount] <= m_axis_tdata;
            outCount <= outCount + 1;
        end
    end

    // tag capture
    always @(posedge clk) begin
        if (rst || captureRst) begin
            sawTagValid <= 1'b0;
            capturedTag <= 128'd0;
            capturedTagMatch <= 1'b0;
            capturedAuthFail <= 1'b0;
        end
        else if (tagValid) begin
            sawTagValid <= 1'b1;
            capturedTag <= tagOut;
            capturedTagMatch <= tagMatch;
            capturedAuthFail <= authFail;
        end
    end

    task do_reset;
    begin
        rst = 1'b1;
        driverGo = 1'b0;
        captureRst = 1'b0;
        m_axis_tready = 1'b1;
        mode = 1'b0;
        tagIn = 128'd0;
        key = 256'd0;
        iv = 96'd0;
        repeat (5) @(posedge clk);
        #1; rst = 1'b0;
        repeat (3) @(posedge clk);
        #1;
    end
    endtask

    task run_and_wait;
        integer timeout;
    begin
        captureRst = 1'b1;
        @(posedge clk); #1;
        captureRst = 1'b0;
        @(posedge clk); #1;
        driverGo = 1'b1;

        // wait for tag valid (end of operation)
        timeout = 0;
        while (!sawTagValid && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 200000) begin
            $display("  ERROR: timeout waiting for tag");
            $stop;
        end
        repeat (5) @(posedge clk);
        #1;
        driverGo = 1'b0;
        repeat (5) @(posedge clk);
        #1;
    end
    endtask

    initial begin
        $display("");
        $display("tb_aes_gcm_core_adapter_decrypt, stage d2 verification");
        $display("");

        passCount = 0;
        failCount = 0;
        totalTests = 0;

        do_reset();

        // test 1: encrypt regression (nist tc14)
        // key=0, iv=0, pt=0 -> ct=cea7...18, tag=d0d1...19
        $display("test 1: encrypt regression (nist tc14)");
        key = 256'h0;
        iv = 96'h0;
        mode = 1'b0;
        tagIn = 128'd0;
        inBlocks[0] = 128'h00000000000000000000000000000000;
        inKeep[0] = 16'hFFFF;
        blockCount = 4'd1;

        run_and_wait();

        totalTests = totalTests + 1;
        if (outCount == 1 && outBlocks[0] == 128'hcea7403d4d606b6e074ec5d3baf39d18) begin
            $display("    PASS: ct matches nist tc14");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: ct=%h (count=%0d)", outBlocks[0], outCount);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (capturedTag == 128'hd0d1c8a799996bf0265b98b5d48ab919) begin
            $display("    PASS: tag matches nist tc14");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tag=%h", capturedTag);
            failCount = failCount + 1;
        end

        $display("    test 1 complete");
        do_reset();

        // test 2: decrypt nist tc14
        // feed ct, expect pt=0, tag match
        $display("");
        $display("test 2: decrypt nist tc14 (single block)");
        key = 256'h0;
        iv = 96'h0;
        mode = 1'b1;
        tagIn = 128'hd0d1c8a799996bf0265b98b5d48ab919;
        inBlocks[0] = 128'hcea7403d4d606b6e074ec5d3baf39d18;
        inKeep[0] = 16'hFFFF;
        blockCount = 4'd1;

        run_and_wait();

        totalTests = totalTests + 1;
        if (outCount == 1 && outBlocks[0] == 128'h00000000000000000000000000000000) begin
            $display("    PASS: pt = 0 (correct)");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: pt=%h (count=%0d)", outBlocks[0], outCount);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (capturedTagMatch && !capturedAuthFail) begin
            $display("    PASS: tag authenticated");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: match=%b fail=%b", capturedTagMatch, capturedAuthFail);
            failCount = failCount + 1;
        end

        $display("    test 2 complete");
        do_reset();

        // test 3: decrypt nist tc15 (4 blocks)
        $display("");
        $display("test 3: decrypt nist tc15 (4 blocks)");
        key = 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308;
        iv = 96'hcafebabefacedbaddecaf888;
        mode = 1'b1;
        tagIn = 128'hb094dac5d93471bdec1a502270e3cc6c;

        inBlocks[0] = 128'h522dc1f099567d07f47f37a32a84427d;
        inBlocks[1] = 128'h643a8cdcbfe5c0c97598a2bd2555d1aa;
        inBlocks[2] = 128'h8cb08e48590dbb3da7b08b1056828838;
        inBlocks[3] = 128'hc5f61e6393ba7a0abcc9f662898015ad;
        inKeep[0] = 16'hFFFF;
        inKeep[1] = 16'hFFFF;
        inKeep[2] = 16'hFFFF;
        inKeep[3] = 16'hFFFF;
        blockCount = 4'd4;

        run_and_wait();

        totalTests = totalTests + 1;
        if (outCount == 4) begin
            $display("    PASS: 4 output blocks");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d output blocks (expected 4)", outCount);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (outBlocks[0] == 128'hd9313225f88406e5a55909c5aff5269a) begin
            $display("    PASS: pt block 0");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: pt block 0 = %h", outBlocks[0]);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (outBlocks[1] == 128'h86a7a9531534f7da2e4c303d8a318a72) begin
            $display("    PASS: pt block 1");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: pt block 1 = %h", outBlocks[1]);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (outBlocks[2] == 128'h1c3c0c95956809532fcf0e2449a6b525) begin
            $display("    PASS: pt block 2");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: pt block 2 = %h", outBlocks[2]);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (outBlocks[3] == 128'hb16aedf5aa0de657ba637b391aafd255) begin
            $display("    PASS: pt block 3");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: pt block 3 = %h", outBlocks[3]);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (capturedTagMatch && !capturedAuthFail) begin
            $display("    PASS: tag authenticated");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: match=%b fail=%b", capturedTagMatch, capturedAuthFail);
            failCount = failCount + 1;
        end

        $display("    test 3 complete");
        do_reset();

        // test 4: decrypt with corrupted tag (auth fail)
        $display("");
        $display("test 4: decrypt with corrupted tag");
        key = 256'h0;
        iv = 96'h0;
        mode = 1'b1;
        tagIn = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // wrong tag
        inBlocks[0] = 128'hcea7403d4d606b6e074ec5d3baf39d18;
        inKeep[0] = 16'hFFFF;
        blockCount = 4'd1;

        run_and_wait();

        totalTests = totalTests + 1;
        if (!capturedTagMatch && capturedAuthFail) begin
            $display("    PASS: auth failure detected");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: match=%b fail=%b (expected 0/1)",
                     capturedTagMatch, capturedAuthFail);
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
