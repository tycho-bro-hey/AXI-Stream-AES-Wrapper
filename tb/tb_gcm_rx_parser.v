`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: tb_gcm_rx_parser
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Testbench for gcm_rx_parser. Feeds encrypted packet byte
//              streams and verifies IV extraction, CT byte routing with
//              correct tlast, and tag accumulation.
//
// Dependencies: gcm_rx_parser
//
//////////////////////////////////////////////////////////////////////////////////

module tb_gcm_rx_parser;

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    reg clk;
    reg rst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // DUT Signals
    // =========================================================================
    reg         pktStart;
    reg [15:0]  totalLen;
    reg [7:0]   rx_tdata;
    reg         rx_tvalid;
    wire        rx_tready;

    wire [7:0]  ct_tdata;
    wire        ct_tvalid;
    reg         ct_tready;
    wire        ct_tlast;

    wire [95:0]  ivOut;
    wire         ivReady;
    wire [127:0] tagOut;
    wire         tagReady;
    wire [15:0]  ctLen;
    wire         parserBusy;
    wire         parserDone;

    // =========================================================================
    // CT Byte Capture
    // =========================================================================
    reg [7:0]   ctCaptured [0:1599];
    reg         ctTlastCap [0:1599];
    integer     ctCaptureCount;

    always @(posedge clk) begin
        if (rst) begin
            ctCaptureCount <= 0;
        end
        else if (ct_tvalid && ct_tready) begin
            ctCaptured[ctCaptureCount]  <= ct_tdata;
            ctTlastCap[ctCaptureCount]  <= ct_tlast;
            ctCaptureCount <= ctCaptureCount + 1;
        end
    end

    // =========================================================================
    // Registered transfer detect — captures whether rx handshake completed
    // at the previous posedge. Avoids checking combinational rx_tready
    // after the DUT has already changed state.
    // =========================================================================
    reg rxTransferred;
    always @(posedge clk) begin
        if (rst)
            rxTransferred <= 1'b0;
        else
            rxTransferred <= rx_tvalid && rx_tready;
    end

    // =========================================================================
    // Test Tracking
    // =========================================================================
    integer testNum;
    integer passCount;
    integer failCount;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    gcm_rx_parser u_dut (
        .clk        (clk),
        .rst        (rst),
        .pktStart   (pktStart),
        .totalLen   (totalLen),
        .rx_tdata   (rx_tdata),
        .rx_tvalid  (rx_tvalid),
        .rx_tready  (rx_tready),
        .ct_tdata   (ct_tdata),
        .ct_tvalid  (ct_tvalid),
        .ct_tready  (ct_tready),
        .ct_tlast   (ct_tlast),
        .ivOut      (ivOut),
        .ivReady    (ivReady),
        .tagOut     (tagOut),
        .tagReady   (tagReady),
        .ctLen      (ctLen),
        .parserBusy (parserBusy),
        .parserDone (parserDone)
    );

    // =========================================================================
    // Packet byte storage
    // =========================================================================
    reg [7:0] pktBytes [0:1599];
    integer   pktByteCount;

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    task init;
    begin
        pktStart   = 1'b0;
        totalLen   = 16'd0;
        rx_tdata   = 8'd0;
        rx_tvalid  = 1'b0;
        ct_tready  = 1'b1;
    end
    endtask

    task resetDut;
    begin
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
    end
    endtask

    // Build a packet: IV(12) + CT(N) + Tag(16)
    // ivVal: 96-bit IV, MSB-first
    // ctBlocks: loaded separately into pktBytes
    // tagVal: 128-bit tag, MSB-first
    task buildPacketStart;
        input [95:0]  ivVal;
        integer i;
    begin
        pktByteCount = 0;
        // IV bytes
        for (i = 0; i < 12; i = i + 1) begin
            pktBytes[pktByteCount] = ivVal[95 - i*8 -: 8];
            pktByteCount = pktByteCount + 1;
        end
    end
    endtask

    task buildPacketAddCt;
        input [127:0] block;
        input integer numBytes;
        integer i;
    begin
        for (i = 0; i < numBytes; i = i + 1) begin
            pktBytes[pktByteCount] = block[127 - i*8 -: 8];
            pktByteCount = pktByteCount + 1;
        end
    end
    endtask

    task buildPacketAddTag;
        input [127:0] tagVal;
        integer i;
    begin
        for (i = 0; i < 16; i = i + 1) begin
            pktBytes[pktByteCount] = tagVal[127 - i*8 -: 8];
            pktByteCount = pktByteCount + 1;
        end
    end
    endtask

    // Feed all packet bytes to parser
    task feedAllBytes;
        input [15:0] pktLen;
        integer i;
    begin
        // Start packet
        totalLen = pktLen;
        pktStart = 1'b1;
        @(posedge clk);
        pktStart = 1'b0;
        #1;

        // Feed bytes. The #1 after each @(posedge clk) ensures the
        // next iteration's blocking assignment to rx_tdata happens
        // AFTER the DUT and capture monitor have evaluated the
        // current byte at the posedge.
        for (i = 0; i < pktLen; i = i + 1) begin
            rx_tdata  = pktBytes[i];
            rx_tvalid = 1'b1;
            @(posedge clk);
            #1;
        end
        rx_tvalid = 1'b0;
    end
    endtask

    task waitForParserDone;
        integer timeout;
    begin
        timeout = 0;
        while (!parserDone && timeout < 50000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 50000)
            $display("  ERROR: Timeout waiting for parserDone");
        @(posedge clk);
    end
    endtask

    task checkPass;
        input [399:0] testName;
        input         condition;
    begin
        if (condition) begin
            $display("  PASS: %0s", testName);
            passCount = passCount + 1;
        end
        else begin
            $display("  FAIL: %0s", testName);
            failCount = failCount + 1;
        end
    end
    endtask

    // Check CT bytes against expected 128-bit block (MSB-first)
    task checkCtBytes;
        input integer   startIdx;
        input [127:0]   expected;
        input integer   numBytes;
        input [399:0]   label;
        integer i;
        reg [7:0] expByte;
        reg allMatch;
    begin
        allMatch = 1'b1;
        for (i = 0; i < numBytes; i = i + 1) begin
            expByte = expected[127 - i*8 -: 8];
            if (ctCaptured[startIdx + i] !== expByte)
                allMatch = 1'b0;
        end
        if (allMatch) begin
            $display("  PASS: %0s (%0d bytes)", label, numBytes);
            passCount = passCount + 1;
        end
        else begin
            $display("  FAIL: %0s", label);
            for (i = 0; i < numBytes; i = i + 1) begin
                expByte = expected[127 - i*8 -: 8];
                if (ctCaptured[startIdx + i] !== expByte)
                    $display("    ct[%0d] expected=%h got=%h",
                             startIdx + i, expByte, ctCaptured[startIdx + i]);
            end
            failCount = failCount + 1;
        end
    end
    endtask

    // Check tlast on CT output: only on last CT byte
    task checkCtTlast;
        input integer totalCtBytes;
        input [399:0] label;
        integer i;
        reg anyBad;
    begin
        anyBad = 1'b0;
        for (i = 0; i < totalCtBytes - 1; i = i + 1) begin
            if (ctTlastCap[i] === 1'b1) begin
                anyBad = 1'b1;
                $display("  FAIL: %0s — spurious ct_tlast at ct[%0d]", label, i);
            end
        end
        if (ctTlastCap[totalCtBytes - 1] !== 1'b1) begin
            anyBad = 1'b1;
            $display("  FAIL: %0s — ct_tlast NOT set on final ct byte[%0d]", label, totalCtBytes - 1);
        end
        if (!anyBad) begin
            $display("  PASS: %0s", label);
            passCount = passCount + 1;
        end
        else begin
            failCount = failCount + 1;
        end
    end
    endtask

    // =========================================================================
    // Test Data
    // =========================================================================
    localparam [95:0]  TEST_IV  = 96'hcafebabefacedbaddecaf888;
    localparam [127:0] TEST_CT0 = 128'h522dc1f099567d07f47f37a32a84427d;
    localparam [127:0] TEST_CT1 = 128'h643a8cdcbfe5c0c97598a2bd2555d1aa;
    localparam [127:0] TEST_CT2 = 128'h8cb08e48590dbb3da7b08b1056828838;
    localparam [127:0] TEST_CT3 = 128'hc5f61e6393ba7a0abcc9f662898015ad;
    localparam [127:0] TEST_TAG = 128'hb094dac5d93471bdec1a502270e3cc6c;

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        testNum   = 0;
        passCount = 0;
        failCount = 0;

        init();
        resetDut();

        // =================================================================
        // TEST 1: Single 16-byte CT block
        //         Packet: IV(12) + CT(16) + Tag(16) = 44 bytes
        // =================================================================
        testNum = 1;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Single 16B CT block (44-byte packet)", testNum);
        $display("==========================================================");

        buildPacketStart(TEST_IV);
        buildPacketAddCt(TEST_CT0, 16);
        buildPacketAddTag(TEST_TAG);

        feedAllBytes(16'd44);
        waitForParserDone();

        checkPass("ivOut matches",     ivOut  == TEST_IV);
        checkPass("tagOut matches",    tagOut == TEST_TAG);
        checkPass("ctLen == 16",       ctLen  == 16'd16);
        checkPass("ctCaptureCount == 16", ctCaptureCount == 16);
        checkCtBytes(0, TEST_CT0, 16, "CT block 0");
        checkCtTlast(16, "ct_tlast position");

        $display("  ivOut  = %h", ivOut);
        $display("  tagOut = %h", tagOut);

        init();
        resetDut();

        // =================================================================
        // TEST 2: Four 16-byte CT blocks (64B CT)
        //         Packet: IV(12) + CT(64) + Tag(16) = 92 bytes
        // =================================================================
        testNum = 2;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Four 16B CT blocks (92-byte packet)", testNum);
        $display("==========================================================");

        buildPacketStart(TEST_IV);
        buildPacketAddCt(TEST_CT0, 16);
        buildPacketAddCt(TEST_CT1, 16);
        buildPacketAddCt(TEST_CT2, 16);
        buildPacketAddCt(TEST_CT3, 16);
        buildPacketAddTag(TEST_TAG);

        feedAllBytes(16'd92);
        waitForParserDone();

        checkPass("ivOut matches",     ivOut  == TEST_IV);
        checkPass("tagOut matches",    tagOut == TEST_TAG);
        checkPass("ctLen == 64",       ctLen  == 16'd64);
        checkPass("ctCaptureCount == 64", ctCaptureCount == 64);
        checkCtBytes(0,  TEST_CT0, 16, "CT block 0");
        checkCtBytes(16, TEST_CT1, 16, "CT block 1");
        checkCtBytes(32, TEST_CT2, 16, "CT block 2");
        checkCtBytes(48, TEST_CT3, 16, "CT block 3");
        checkCtTlast(64, "ct_tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 3: Zero CT bytes (IV + tag only, 28-byte packet)
        //         Tests GMAC-like input parsing
        // =================================================================
        testNum = 3;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Zero CT bytes (28-byte packet)", testNum);
        $display("==========================================================");

        buildPacketStart(TEST_IV);
        // No CT bytes
        buildPacketAddTag(TEST_TAG);

        feedAllBytes(16'd28);
        waitForParserDone();

        checkPass("ivOut matches",     ivOut  == TEST_IV);
        checkPass("tagOut matches",    tagOut == TEST_TAG);
        checkPass("ctLen == 0",        ctLen  == 16'd0);
        checkPass("ctCaptureCount == 0", ctCaptureCount == 0);

        init();
        resetDut();

        // =================================================================
        // TEST 4: Partial CT block (12 bytes CT, non-block-aligned)
        //         Packet: IV(12) + CT(12) + Tag(16) = 40 bytes
        // =================================================================
        testNum = 4;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Partial CT block (12B CT, 40-byte packet)", testNum);
        $display("==========================================================");

        buildPacketStart(96'hAABBCCDDEEFF001122334455);
        buildPacketAddCt(128'hDEADBEEFCAFEBABE1234567800000000, 12);
        buildPacketAddTag(128'h11111111222222223333333344444444);

        feedAllBytes(16'd40);
        waitForParserDone();

        checkPass("ivOut matches",      ivOut == 96'hAABBCCDDEEFF001122334455);
        checkPass("tagOut matches",     tagOut == 128'h11111111222222223333333344444444);
        checkPass("ctLen == 12",        ctLen == 16'd12);
        checkPass("ctCaptureCount == 12", ctCaptureCount == 12);
        checkCtTlast(12, "ct_tlast at byte 11");

        init();
        resetDut();

        // =================================================================
        // TEST 5: Backpressure on CT output
        //         Width converter side (ct_tready) drops every other cycle
        // =================================================================
        testNum = 5;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Backpressure on CT output", testNum);
        $display("==========================================================");

        buildPacketStart(TEST_IV);
        buildPacketAddCt(TEST_CT0, 16);
        buildPacketAddTag(TEST_TAG);

        // Start packet
        totalLen = 16'd44;
        pktStart = 1'b1;
        @(posedge clk);
        pktStart = 1'b0;
        #1;

        // Feed bytes with alternating ct_tready during CT phase.
        // Uses rxTransferred (registered) to detect acceptance.
        begin : bpFeed
            integer i;
            integer bpCycle;
            bpCycle = 0;
            for (i = 0; i < 44; i = i + 1) begin
                rx_tdata  = pktBytes[i];
                rx_tvalid = 1'b1;
                if (i >= 12 && i < 28)
                    ct_tready = (bpCycle % 2 == 0) ? 1'b1 : 1'b0;
                else
                    ct_tready = 1'b1;
                @(posedge clk);
                #1;
                while (!rxTransferred) begin
                    bpCycle = bpCycle + 1;
                    if (i >= 12 && i < 28)
                        ct_tready = (bpCycle % 2 == 0) ? 1'b1 : 1'b0;
                    @(posedge clk);
                    #1;
                end
                bpCycle = bpCycle + 1;
            end
            rx_tvalid = 1'b0;
            ct_tready = 1'b1;
        end

        waitForParserDone();

        checkPass("ivOut matches (BP)",     ivOut  == TEST_IV);
        checkPass("tagOut matches (BP)",    tagOut == TEST_TAG);
        checkPass("ctCaptureCount == 16 (BP)", ctCaptureCount == 16);
        checkCtBytes(0, TEST_CT0, 16, "CT block 0 (BP)");

        init();
        resetDut();

        // =================================================================
        // TEST 6: All-zero IV and tag
        //         Ensures no byte gets mixed between fields
        // =================================================================
        testNum = 6;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: All-zero IV, distinct CT, all-FF tag", testNum);
        $display("==========================================================");

        buildPacketStart(96'h000000000000000000000000);
        buildPacketAddCt(128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA, 16);
        buildPacketAddTag(128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

        feedAllBytes(16'd44);
        waitForParserDone();

        checkPass("ivOut == all zeros", ivOut == 96'h000000000000000000000000);
        checkPass("tagOut == all FF",   tagOut == 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        checkCtBytes(0, 128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA, 16, "CT all-AA");

        init();
        resetDut();

        // =================================================================
        // TEST 7: ivReady and tagReady timing
        // =================================================================
        testNum = 7;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: ivReady and tagReady pulse timing", testNum);
        $display("==========================================================");

        buildPacketStart(TEST_IV);
        buildPacketAddCt(TEST_CT0, 16);
        buildPacketAddTag(TEST_TAG);

        // Start packet
        totalLen = 16'd44;
        pktStart = 1'b1;
        @(posedge clk);
        pktStart = 1'b0;
        #1;

        // Feed bytes, watching for pulses
        begin : timingCheck
            integer i;
            reg sawIvReady;
            reg sawTagReady;
            integer ivReadyCycle;
            integer tagReadyCycle;

            sawIvReady  = 1'b0;
            sawTagReady = 1'b0;
            ivReadyCycle  = -1;
            tagReadyCycle = -1;

            for (i = 0; i < 44; i = i + 1) begin
                rx_tdata  = pktBytes[i];
                rx_tvalid = 1'b1;
                @(posedge clk);
                #1;
                // Check pulse outputs after each transfer
                if (ivReady) begin
                    sawIvReady   = 1'b1;
                    ivReadyCycle = i;
                end
                if (tagReady) begin
                    sawTagReady   = 1'b1;
                    tagReadyCycle = i;
                end
            end
            rx_tvalid = 1'b0;
            // Check one more cycle for pulses
            @(posedge clk);
            if (ivReady)  begin sawIvReady = 1'b1; ivReadyCycle = 44; end
            if (tagReady) begin sawTagReady = 1'b1; tagReadyCycle = 44; end

            checkPass("ivReady pulsed",  sawIvReady  == 1'b1);
            checkPass("tagReady pulsed", sawTagReady == 1'b1);
            $display("  ivReady after byte %0d, tagReady after byte %0d",
                     ivReadyCycle, tagReadyCycle);
        end

        waitForParserDone();

        // =================================================================
        // Summary
        // =================================================================
        $display("");
        $display("==========================================================");
        $display("SUMMARY: %0d passed, %0d failed out of %0d",
                 passCount, failCount, passCount + failCount);
        $display("==========================================================");

        if (failCount == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

endmodule
