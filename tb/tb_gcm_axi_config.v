`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: tb_gcm_axi_config
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Testbench for gcm_axi_config. Validates key and IV AXI-Stream
//              loading, default values, IV auto-increment, tlast error
//              detection, and coreIdle commit gating.
//
// Dependencies: gcm_axi_config
//
//////////////////////////////////////////////////////////////////////////////////

module tb_gcm_axi_config;

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
    reg [7:0]   key_axis_tdata;
    reg         key_axis_tvalid;
    wire        key_axis_tready;
    reg         key_axis_tlast;

    reg [7:0]   iv_axis_tdata;
    reg         iv_axis_tvalid;
    wire        iv_axis_tready;
    reg         iv_axis_tlast;

    reg         coreIdle;
    reg         pktDone;

    wire [255:0] keyOut;
    wire [95:0]  ivOut;
    wire         keyUpdated;
    wire         ivUpdated;
    wire         keyError;
    wire         ivError;

    // =========================================================================
    // Test Tracking
    // =========================================================================
    integer testNum;
    integer passCount;
    integer failCount;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    gcm_axi_config u_dut (
        .clk              (clk),
        .rst              (rst),
        .key_axis_tdata   (key_axis_tdata),
        .key_axis_tvalid  (key_axis_tvalid),
        .key_axis_tready  (key_axis_tready),
        .key_axis_tlast   (key_axis_tlast),
        .iv_axis_tdata    (iv_axis_tdata),
        .iv_axis_tvalid   (iv_axis_tvalid),
        .iv_axis_tready   (iv_axis_tready),
        .iv_axis_tlast    (iv_axis_tlast),
        .coreIdle         (coreIdle),
        .pktDone          (pktDone),
        .keyOut           (keyOut),
        .ivOut            (ivOut),
        .keyUpdated       (keyUpdated),
        .ivUpdated        (ivUpdated),
        .keyError         (keyError),
        .ivError          (ivError)
    );

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    task init;
    begin
        key_axis_tdata  = 8'd0;
        key_axis_tvalid = 1'b0;
        key_axis_tlast  = 1'b0;
        iv_axis_tdata   = 8'd0;
        iv_axis_tvalid  = 1'b0;
        iv_axis_tlast   = 1'b0;
        coreIdle        = 1'b1;
        pktDone         = 1'b0;
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

    // Send a full key (32 bytes). Byte 0 = MSB of key.
    // tready is always high during byte accumulation (keyPending
    // only goes high after byte 31 is accepted), so no backpressure
    // handling is needed within the 32-byte window.
    task sendKey;
        input [255:0] keyVal;
        integer i;
    begin
        for (i = 0; i < 32; i = i + 1) begin
            key_axis_tdata  = keyVal[255 - i*8 -: 8];
            key_axis_tvalid = 1'b1;
            key_axis_tlast  = (i == 31) ? 1'b1 : 1'b0;
            @(posedge clk);
        end
        key_axis_tvalid = 1'b0;
        key_axis_tlast  = 1'b0;
        @(posedge clk);
    end
    endtask

    // Send a full IV seed (12 bytes). Byte 0 = MSB of IV.
    // Same rationale as sendKey — tready is always high during
    // byte accumulation.
    task sendIv;
        input [95:0] ivVal;
        integer i;
    begin
        for (i = 0; i < 12; i = i + 1) begin
            iv_axis_tdata  = ivVal[95 - i*8 -: 8];
            iv_axis_tvalid = 1'b1;
            iv_axis_tlast  = (i == 11) ? 1'b1 : 1'b0;
            @(posedge clk);
        end
        iv_axis_tvalid = 1'b0;
        iv_axis_tlast  = 1'b0;
        @(posedge clk);
    end
    endtask

    // Send partial key bytes with premature tlast
    task sendKeyPartial;
        input [7:0] byte0;
        input [7:0] byte1;
    begin
        // Byte 0
        key_axis_tdata  = byte0;
        key_axis_tvalid = 1'b1;
        key_axis_tlast  = 1'b0;
        @(posedge clk);
        // Byte 1 with early tlast
        key_axis_tdata  = byte1;
        key_axis_tvalid = 1'b1;
        key_axis_tlast  = 1'b1;
        @(posedge clk);
        key_axis_tvalid = 1'b0;
        key_axis_tlast  = 1'b0;
        @(posedge clk);
    end
    endtask

    // Send partial IV bytes with premature tlast
    task sendIvPartial;
        input [7:0] byte0;
        input [7:0] byte1;
    begin
        iv_axis_tdata  = byte0;
        iv_axis_tvalid = 1'b1;
        iv_axis_tlast  = 1'b0;
        @(posedge clk);
        iv_axis_tdata  = byte1;
        iv_axis_tvalid = 1'b1;
        iv_axis_tlast  = 1'b1;
        @(posedge clk);
        iv_axis_tvalid = 1'b0;
        iv_axis_tlast  = 1'b0;
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
        // TEST 1: Default values after reset
        // =================================================================
        testNum = 1;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Default values after reset", testNum);
        $display("==========================================================");

        checkPass("keyOut == DEFAULT_KEY (all zeros)",
                  keyOut == 256'h0000000000000000000000000000000000000000000000000000000000000000);
        checkPass("ivOut == DEFAULT_IV (all zeros)",
                  ivOut == 96'h000000000000000000000000);
        checkPass("keyError == 0", keyError == 1'b0);
        checkPass("ivError == 0",  ivError  == 1'b0);
        checkPass("keyUpdated == 0", keyUpdated == 1'b0);
        checkPass("ivUpdated == 0",  ivUpdated  == 1'b0);

        // =================================================================
        // TEST 2: Load a known key via AXI-Stream (coreIdle = 1)
        // =================================================================
        testNum = 2;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Load key via AXI-Stream", testNum);
        $display("==========================================================");

        coreIdle = 1'b1;
        sendKey(256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308);

        // Allow 1 cycle for commit (coreIdle is already high)
        repeat (2) @(posedge clk);

        checkPass("keyOut matches loaded key",
                  keyOut == 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308);
        checkPass("keyError == 0", keyError == 1'b0);

        $display("  keyOut = %h", keyOut);

        // =================================================================
        // TEST 3: Load a known IV via AXI-Stream (coreIdle = 1)
        // =================================================================
        testNum = 3;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Load IV seed via AXI-Stream", testNum);
        $display("==========================================================");

        sendIv(96'hcafebabefacedbaddecaf888);

        repeat (2) @(posedge clk);

        checkPass("ivOut matches loaded IV",
                  ivOut == 96'hcafebabefacedbaddecaf888);
        checkPass("ivError == 0", ivError == 1'b0);

        $display("  ivOut = %h", ivOut);

        // =================================================================
        // TEST 4: IV auto-increment (lower 64 bits)
        // =================================================================
        testNum = 4;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: IV auto-increment on pktDone", testNum);
        $display("==========================================================");

        $display("  IV before increment: %h", ivOut);

        // Pulse pktDone
        pktDone = 1'b1;
        @(posedge clk);
        pktDone = 1'b0;
        @(posedge clk);

        $display("  IV after 1st increment: %h", ivOut);
        checkPass("IV lower 64 incremented by 1",
                  ivOut == 96'hcafebabefacedbaddecaf889);
        checkPass("IV upper 32 unchanged",
                  ivOut[95:64] == 32'hcafebabe);

        // Increment again
        pktDone = 1'b1;
        @(posedge clk);
        pktDone = 1'b0;
        @(posedge clk);

        $display("  IV after 2nd increment: %h", ivOut);
        checkPass("IV lower 64 incremented by 2 total",
                  ivOut == 96'hcafebabefacedbaddecaf88a);

        // =================================================================
        // TEST 5: Key load gated by coreIdle
        // =================================================================
        testNum = 5;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Key commit gated by coreIdle", testNum);
        $display("==========================================================");

        // Set coreIdle low (core is busy)
        coreIdle = 1'b0;

        sendKey(256'h1111111111111111111111111111111111111111111111111111111111111111);

        repeat (3) @(posedge clk);

        // Key should NOT have changed yet
        checkPass("Key NOT committed while core busy",
                  keyOut == 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308);

        // Now release coreIdle
        coreIdle = 1'b1;
        repeat (3) @(posedge clk);

        checkPass("Key committed after coreIdle goes high",
                  keyOut == 256'h1111111111111111111111111111111111111111111111111111111111111111);

        $display("  keyOut = %h", keyOut);

        // =================================================================
        // TEST 6: IV load gated by coreIdle
        // =================================================================
        testNum = 6;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: IV commit gated by coreIdle", testNum);
        $display("==========================================================");

        coreIdle = 1'b0;

        sendIv(96'hAABBCCDDEEFF00112233AABB);

        repeat (3) @(posedge clk);

        // IV should NOT have changed yet (still the auto-incremented value)
        checkPass("IV NOT committed while core busy",
                  ivOut == 96'hcafebabefacedbaddecaf88a);

        coreIdle = 1'b1;
        repeat (3) @(posedge clk);

        checkPass("IV committed after coreIdle goes high",
                  ivOut == 96'hAABBCCDDEEFF00112233AABB);

        $display("  ivOut = %h", ivOut);

        // =================================================================
        // TEST 7: Key tlast early error
        // =================================================================
        testNum = 7;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Key tlast early error", testNum);
        $display("==========================================================");

        // Reset to clear any prior errors
        resetDut();
        coreIdle = 1'b1;

        // Send 2 bytes with tlast on byte 1 (too early)
        sendKeyPartial(8'hAA, 8'hBB);

        repeat (3) @(posedge clk);

        checkPass("keyError asserted on early tlast", keyError == 1'b1);
        checkPass("keyOut still has default (partial discarded)",
                  keyOut == 256'h0000000000000000000000000000000000000000000000000000000000000000);

        // =================================================================
        // TEST 8: IV tlast early error
        // =================================================================
        testNum = 8;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: IV tlast early error", testNum);
        $display("==========================================================");

        resetDut();
        coreIdle = 1'b1;

        sendIvPartial(8'hCC, 8'hDD);

        repeat (3) @(posedge clk);

        checkPass("ivError asserted on early tlast", ivError == 1'b1);
        checkPass("ivOut still has default (partial discarded)",
                  ivOut == 96'h000000000000000000000000);

        // =================================================================
        // TEST 9: Key tlast late error (missing tlast on byte 31)
        // =================================================================
        testNum = 9;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Key tlast late error (no tlast on byte 31)", testNum);
        $display("==========================================================");

        resetDut();
        coreIdle = 1'b1;

        // Send 32 bytes but never assert tlast
        begin : sendKeyNoTlast
            integer i;
            for (i = 0; i < 32; i = i + 1) begin
                key_axis_tdata  = i[7:0];
                key_axis_tvalid = 1'b1;
                key_axis_tlast  = 1'b0; // Never assert tlast
                @(posedge clk);
            end
            key_axis_tvalid = 1'b0;
        end

        repeat (3) @(posedge clk);

        checkPass("keyError asserted on missing tlast at byte 31", keyError == 1'b1);

        // =================================================================
        // TEST 10: IV tlast late error (no tlast on byte 11)
        // =================================================================
        testNum = 10;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: IV tlast late error (no tlast on byte 11)", testNum);
        $display("==========================================================");

        resetDut();
        coreIdle = 1'b1;

        begin : sendIvNoTlast
            integer i;
            for (i = 0; i < 12; i = i + 1) begin
                iv_axis_tdata  = i[7:0];
                iv_axis_tvalid = 1'b1;
                iv_axis_tlast  = 1'b0;
                @(posedge clk);
            end
            iv_axis_tvalid = 1'b0;
        end

        repeat (3) @(posedge clk);

        checkPass("ivError asserted on missing tlast at byte 11", ivError == 1'b1);

        // =================================================================
        // TEST 11: Back-to-back key loads
        // =================================================================
        testNum = 11;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Back-to-back key loads", testNum);
        $display("==========================================================");

        resetDut();
        coreIdle = 1'b1;

        // First key
        sendKey(256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA);
        repeat (3) @(posedge clk);
        checkPass("First key committed",
                  keyOut == 256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA);

        // Second key immediately
        sendKey(256'hBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB);
        repeat (3) @(posedge clk);
        checkPass("Second key committed",
                  keyOut == 256'hBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB);

        // =================================================================
        // TEST 12: IV auto-increment preserves upper 32 bits
        // =================================================================
        testNum = 12;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: IV auto-increment preserves upper 32 bits", testNum);
        $display("==========================================================");

        resetDut();
        coreIdle = 1'b1;

        // Load IV with distinct upper/lower fields
        sendIv(96'hDEADBEEF_FFFFFFFF_FFFFFFFE);

        repeat (2) @(posedge clk);

        $display("  IV loaded: %h", ivOut);
        checkPass("IV loaded correctly",
                  ivOut == 96'hDEADBEEF_FFFFFFFF_FFFFFFFE);

        // Increment — lower 64 should wrap from FFFFFFFFFFFFFFFE to FFFFFFFFFFFFFFFF
        pktDone = 1'b1;
        @(posedge clk);
        pktDone = 1'b0;
        @(posedge clk);

        $display("  IV after increment: %h", ivOut);
        checkPass("Lower 64 incremented",
                  ivOut[63:0] == 64'hFFFFFFFFFFFFFFFF);
        checkPass("Upper 32 preserved",
                  ivOut[95:64] == 32'hDEADBEEF);

        // Increment again — lower 64 wraps to 0
        pktDone = 1'b1;
        @(posedge clk);
        pktDone = 1'b0;
        @(posedge clk);

        $display("  IV after wrap: %h", ivOut);
        checkPass("Lower 64 wrapped to 0",
                  ivOut[63:0] == 64'h0000000000000000);
        checkPass("Upper 32 still preserved after wrap",
                  ivOut[95:64] == 32'hDEADBEEF);

        // =================================================================
        // TEST 13: IV not auto-incremented while pending commit
        // =================================================================
        testNum = 13;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: IV auto-increment blocked while pending", testNum);
        $display("==========================================================");

        resetDut();
        coreIdle = 1'b0; // Core busy

        sendIv(96'h112233445566778899AABBCC);

        // IV is pending — pktDone should not increment the *old* ivReg
        // in a way that conflicts with pending commit
        pktDone = 1'b1;
        @(posedge clk);
        pktDone = 1'b0;
        repeat (2) @(posedge clk);

        // Release core
        coreIdle = 1'b1;
        repeat (3) @(posedge clk);

        checkPass("IV committed to loaded seed (no spurious increment)",
                  ivOut == 96'h112233445566778899AABBCC);

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
