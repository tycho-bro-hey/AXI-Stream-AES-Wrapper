`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: tb_gcm_tx_serializer
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Testbench for gcm_tx_serializer. Verifies byte-serial TX output
//              for IV + ciphertext + tag, header handshake, backpressure
//              handling, tlast generation, and zero-length plaintext.
//
// Dependencies: gcm_tx_serializer
//
//////////////////////////////////////////////////////////////////////////////////

module tb_gcm_tx_serializer;

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    reg clk;
    reg rst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 100 MHz
    end

    // =========================================================================
    // DUT Signals
    // =========================================================================
    reg         txStart;
    reg [95:0]  txIv;
    reg [15:0]  txPtLen;

    reg [127:0] txCtBlock;
    reg         txCtValid;
    reg [4:0]   txCtBytes;
    reg         txCtLast;

    reg [127:0] txTag;
    reg         txTagValid;

    wire        txBusy;
    wire        txDone;

    wire        tx_hdr_valid;
    wire [15:0] tx_payload_len;
    reg         hdrReady;

    wire [7:0]  tx_payload_tdata;
    wire        tx_payload_tvalid;
    wire        tx_payload_tlast;

    // Backpressure control: bpMode=0 → always ready, bpMode=1 → alternating
    reg         bpMode;
    reg         bpState;

    always @(posedge clk) begin
        if (rst)
            bpState <= 1'b0;
        else
            bpState <= ~bpState;
    end

    wire payloadReady = bpMode ? bpState : 1'b1;

    // =========================================================================
    // Byte Capture Monitor
    // =========================================================================
    reg [7:0]   capturedBytes [0:1599];
    reg         capturedTlast [0:1599];
    integer     captureCount;

    always @(posedge clk) begin
        if (rst) begin
            captureCount <= 0;
        end
        else if (tx_payload_tvalid && payloadReady) begin
            capturedBytes[captureCount] <= tx_payload_tdata;
            capturedTlast[captureCount] <= tx_payload_tlast;
            captureCount <= captureCount + 1;
        end
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
    gcm_tx_serializer u_dut (
        .clk              (clk),
        .rst              (rst),
        .txStart          (txStart),
        .txIv             (txIv),
        .txPtLen          (txPtLen),
        .txCtBlock        (txCtBlock),
        .txCtValid        (txCtValid),
        .txCtBytes        (txCtBytes),
        .txCtLast         (txCtLast),
        .txTag            (txTag),
        .txTagValid       (txTagValid),
        .txBusy           (txBusy),
        .txDone           (txDone),
        .tx_hdr_valid     (tx_hdr_valid),
        .tx_payload_len   (tx_payload_len),
        .tx_hdr_ready     (hdrReady),
        .tx_payload_tdata (tx_payload_tdata),
        .tx_payload_tvalid(tx_payload_tvalid),
        .tx_payload_tready(payloadReady),
        .tx_payload_tlast (tx_payload_tlast)
    );

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    task init;
    begin
        txStart    = 1'b0;
        txIv       = 96'd0;
        txPtLen    = 16'd0;
        txCtBlock  = 128'd0;
        txCtValid  = 1'b0;
        txCtBytes  = 5'd0;
        txCtLast   = 1'b0;
        txTag      = 128'd0;
        txTagValid = 1'b0;
        hdrReady   = 1'b1;
        bpMode     = 1'b0;
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

    task startPacket;
        input [95:0]  iv;
        input [15:0]  ptLen;
    begin
        txIv    = iv;
        txPtLen = ptLen;
        txStart = 1'b1;
        @(posedge clk);
        txStart = 1'b0;
    end
    endtask

    task sendCtBlock;
        input [127:0] block;
        input [4:0]   numBytes;
        input         last;
    begin
        // Wait until serializer is in CT_WAIT
        while (!(u_dut.state == 3'd3)) @(posedge clk);
        txCtBlock = block;
        txCtBytes = numBytes;
        txCtLast  = last;
        txCtValid = 1'b1;
        @(posedge clk);
        txCtValid = 1'b0;
        txCtLast  = 1'b0;
    end
    endtask

    task sendTag;
        input [127:0] tagVal;
    begin
        // Wait until serializer is in TAG_WAIT
        while (!(u_dut.state == 3'd5)) @(posedge clk);
        txTag      = tagVal;
        txTagValid = 1'b1;
        @(posedge clk);
        txTagValid = 1'b0;
    end
    endtask

    task waitForTxDone;
        integer timeout;
    begin
        timeout = 0;
        while (!txDone && timeout < 50000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 50000)
            $display("  ERROR: Timeout waiting for txDone");
        @(posedge clk);
        #1; // Ensure NBAs settled
    end
    endtask

    // Check a block of captured bytes against expected 128-bit value (MSB-first)
    task checkBlock128;
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
            if (capturedBytes[startIdx + i] !== expByte)
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
                if (capturedBytes[startIdx + i] !== expByte)
                    $display("    byte[%0d] expected=%h got=%h",
                             startIdx + i, expByte, capturedBytes[startIdx + i]);
            end
            failCount = failCount + 1;
        end
    end
    endtask

    // Check tlast: must be 0 on all bytes except the very last
    task checkTlast;
        input integer totalBytes;
        input [399:0] label;
        integer i;
        reg anyBad;
    begin
        anyBad = 1'b0;
        for (i = 0; i < totalBytes - 1; i = i + 1) begin
            if (capturedTlast[i] === 1'b1) begin
                anyBad = 1'b1;
                $display("  FAIL: %0s — spurious tlast at byte[%0d]", label, i);
            end
        end
        if (capturedTlast[totalBytes - 1] !== 1'b1) begin
            anyBad = 1'b1;
            $display("  FAIL: %0s — tlast NOT set on final byte[%0d]", label, totalBytes - 1);
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

    // =========================================================================
    // Test Data Constants (from NIST Test Case 15 / McGrew-Viega AES-256)
    // =========================================================================
    localparam [95:0]  TEST_IV   = 96'hcafebabefacedbaddecaf888;
    localparam [127:0] TEST_CT0  = 128'h522dc1f099567d07f47f37a32a84427d;
    localparam [127:0] TEST_CT1  = 128'h643a8cdcbfe5c0c97598a2bd2555d1aa;
    localparam [127:0] TEST_CT2  = 128'h8cb08e48590dbb3da7b08b1056828838;
    localparam [127:0] TEST_CT3P = 128'hc5f61e6393ba7a0abcc9f66200000000; // 12 bytes valid
    localparam [127:0] TEST_TAG  = 128'hb094dac5d93471bdec1a502270e3cc6c;
    localparam [127:0] TEST_TAG2 = 128'h76fc6ece0f4e1768cddf8853bb2d551b;

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
        // TEST 1: Single 16-byte CT block, tready always high
        //         Output: IV(12) + CT(16) + Tag(16) = 44 bytes
        // =================================================================
        testNum = 1;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Single 16B CT block, no backpressure", testNum);
        $display("==========================================================");

        startPacket(TEST_IV, 16'd16);
        sendCtBlock(TEST_CT0, 5'd16, 1'b1); // single block, last
        sendTag(TEST_TAG);
        waitForTxDone();

        checkPass("tx_payload_len == 44", tx_payload_len == 16'd44);
        checkPass("captureCount == 44", captureCount == 44);
        checkBlock128(0,  {TEST_IV, 32'd0}, 12, "IV bytes");
        checkBlock128(12, TEST_CT0,         16, "CT block 0");
        checkBlock128(28, TEST_TAG,         16, "Tag bytes");
        checkTlast(44, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 2: Two full 16-byte CT blocks (32B PT)
        //         Output: IV(12) + CT(32) + Tag(16) = 60 bytes
        // =================================================================
        testNum = 2;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Two 16B CT blocks (32B PT)", testNum);
        $display("==========================================================");

        startPacket(TEST_IV, 16'd32);
        sendCtBlock(TEST_CT0, 5'd16, 1'b0); // block 0, not last
        sendCtBlock(TEST_CT1, 5'd16, 1'b1); // block 1, last
        sendTag(TEST_TAG);
        waitForTxDone();

        checkPass("tx_payload_len == 60", tx_payload_len == 16'd60);
        checkPass("captureCount == 60", captureCount == 60);
        checkBlock128(0,  {TEST_IV, 32'd0}, 12, "IV bytes");
        checkBlock128(12, TEST_CT0,         16, "CT block 0");
        checkBlock128(28, TEST_CT1,         16, "CT block 1");
        checkBlock128(44, TEST_TAG,         16, "Tag bytes");
        checkTlast(60, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 3: Partial last block (16 + 4 = 20B PT)
        //         Output: IV(12) + CT(20) + Tag(16) = 48 bytes
        // =================================================================
        testNum = 3;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Partial last block (16B + 4B = 20B PT)", testNum);
        $display("==========================================================");

        startPacket(TEST_IV, 16'd20);
        sendCtBlock(TEST_CT0,  5'd16, 1'b0); // block 0: 16 bytes
        sendCtBlock(TEST_CT3P, 5'd4,  1'b1); // block 1: 4 bytes, last
        sendTag(TEST_TAG2);
        waitForTxDone();

        checkPass("tx_payload_len == 48", tx_payload_len == 16'd48);
        checkPass("captureCount == 48", captureCount == 48);
        checkBlock128(0,  {TEST_IV, 32'd0}, 12, "IV bytes");
        checkBlock128(12, TEST_CT0,         16, "CT block 0 (full)");
        checkBlock128(28, TEST_CT3P,         4, "CT block 1 (4B partial)");
        checkBlock128(32, TEST_TAG2,        16, "Tag bytes");
        checkTlast(48, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 4: Zero-length plaintext (GMAC mode)
        //         Output: IV(12) + Tag(16) = 28 bytes
        // =================================================================
        testNum = 4;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Zero-length PT (GMAC mode)", testNum);
        $display("==========================================================");

        startPacket(TEST_IV, 16'd0);
        // No CT blocks — go straight to tag
        sendTag(TEST_TAG);
        waitForTxDone();

        checkPass("tx_payload_len == 28", tx_payload_len == 16'd28);
        checkPass("captureCount == 28", captureCount == 28);
        checkBlock128(0,  {TEST_IV, 32'd0}, 12, "IV bytes");
        checkBlock128(12, TEST_TAG,         16, "Tag bytes");
        checkTlast(28, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 5: Backpressure — alternating tready (single block)
        //         Same data as Test 1 but with 50% duty cycle on tready.
        //         Output content must be identical to Test 1.
        // =================================================================
        testNum = 5;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Backpressure (alternating tready)", testNum);
        $display("==========================================================");

        bpMode = 1'b1; // Enable alternating backpressure
        startPacket(TEST_IV, 16'd16);
        sendCtBlock(TEST_CT0, 5'd16, 1'b1);
        sendTag(TEST_TAG);
        waitForTxDone();

        checkPass("captureCount == 44 (with backpressure)", captureCount == 44);
        checkBlock128(0,  {TEST_IV, 32'd0}, 12, "IV bytes (BP)");
        checkBlock128(12, TEST_CT0,         16, "CT block 0 (BP)");
        checkBlock128(28, TEST_TAG,         16, "Tag bytes (BP)");
        checkTlast(44, "tlast position (BP)");

        bpMode = 1'b0;
        init();
        resetDut();

        // =================================================================
        // TEST 6: Delayed header ready
        //         tx_hdr_ready held low for 10 cycles after tx_hdr_valid
        // =================================================================
        testNum = 6;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Delayed header ready (10 cycle delay)", testNum);
        $display("==========================================================");

        hdrReady = 1'b0; // Hold header not ready

        txIv    = TEST_IV;
        txPtLen = 16'd16;
        txStart = 1'b1;
        @(posedge clk);
        txStart = 1'b0;

        // Verify tx_hdr_valid stays high while waiting
        repeat (5) @(posedge clk);
        checkPass("tx_hdr_valid held during wait", tx_hdr_valid == 1'b1);
        checkPass("tx_payload_tvalid low during header wait", tx_payload_tvalid == 1'b0);

        // Release header ready after 10 cycles total
        repeat (5) @(posedge clk);
        hdrReady = 1'b1;
        @(posedge clk);

        // Continue with CT and tag
        sendCtBlock(TEST_CT0, 5'd16, 1'b1);
        sendTag(TEST_TAG);
        waitForTxDone();

        checkPass("captureCount == 44 (delayed hdr)", captureCount == 44);
        checkBlock128(0,  {TEST_IV, 32'd0}, 12, "IV bytes (delayed hdr)");
        checkBlock128(12, TEST_CT0,         16, "CT block 0 (delayed hdr)");
        checkBlock128(28, TEST_TAG,         16, "Tag bytes (delayed hdr)");
        checkTlast(44, "tlast position (delayed hdr)");

        init();
        resetDut();

        // =================================================================
        // TEST 7: Four full CT blocks (64B PT, Test Case 15 data)
        //         Output: IV(12) + CT(64) + Tag(16) = 92 bytes
        // =================================================================
        testNum = 7;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Four 16B CT blocks (64B PT)", testNum);
        $display("==========================================================");

        startPacket(TEST_IV, 16'd64);
        sendCtBlock(TEST_CT0, 5'd16, 1'b0);
        sendCtBlock(TEST_CT1, 5'd16, 1'b0);
        sendCtBlock(TEST_CT2, 5'd16, 1'b0);
        sendCtBlock(TEST_CT0, 5'd16, 1'b1); // reuse CT0 as 4th block
        sendTag(TEST_TAG);
        waitForTxDone();

        checkPass("tx_payload_len == 92", tx_payload_len == 16'd92);
        checkPass("captureCount == 92", captureCount == 92);
        checkBlock128(0,  {TEST_IV, 32'd0}, 12, "IV bytes");
        checkBlock128(12, TEST_CT0,         16, "CT block 0");
        checkBlock128(28, TEST_CT1,         16, "CT block 1");
        checkBlock128(44, TEST_CT2,         16, "CT block 2");
        checkBlock128(60, TEST_CT0,         16, "CT block 3");
        checkBlock128(76, TEST_TAG,         16, "Tag bytes");
        checkTlast(92, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 8: txBusy and txDone behavior
        // =================================================================
        testNum = 8;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: txBusy / txDone behavior", testNum);
        $display("==========================================================");

        checkPass("txBusy low in idle", txBusy == 1'b0);

        txIv    = TEST_IV;
        txPtLen = 16'd0;
        txStart = 1'b1;
        @(posedge clk);
        txStart = 1'b0;
        @(posedge clk);
        #1;

        checkPass("txBusy high after start", txBusy == 1'b1);

        sendTag(TEST_TAG);
        waitForTxDone();

        // txDone was captured by waitForTxDone — DUT is back in IDLE
        @(posedge clk);
        #1;
        checkPass("txBusy low after done", txBusy == 1'b0);

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
