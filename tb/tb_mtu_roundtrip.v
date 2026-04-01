`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: tb_mtu_roundtrip
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Maximum Transmission Unit (MTU) roundtrip test. Wires
//              gcm_axi_top (encrypt) directly to gcm_axi_decrypt (decrypt)
//              and verifies plaintext recovery at Ethernet-scale payloads.
//
//              Test sizes:
//                1500 bytes — Full Ethernet MTU (93 full + 12B partial)
//                1488 bytes — 93 exact 16-byte blocks (no partial block)
//                 256 bytes — 16 full blocks (medium scale)
//
//              Each test uses a deterministic byte pattern so failures
//              pinpoint the exact byte offset. Pattern: ptBytes[i] = i[7:0]
//              (wrapping modulo 256).
//
// Dependencies: gcm_axi_top, gcm_axi_decrypt, and all submodules.
//               Two instances of axis_dwidth_converter_0 (Vivado IP).
//
//////////////////////////////////////////////////////////////////////////////////

module tb_mtu_roundtrip;

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
    // Key Loading (shared bus)
    // =========================================================================
    reg [7:0]   key_tdata;
    reg         key_tvalid;
    reg         key_tlast;
    wire        enc_key_tready;
    wire        dec_key_tready;
    wire        key_tready;
    assign key_tready = enc_key_tready && dec_key_tready;

    // =========================================================================
    // Encrypt RX Input (testbench → encrypt)
    // =========================================================================
    reg         enc_rx_hdr_valid;
    reg [15:0]  enc_rx_payload_len;
    wire        enc_rx_hdr_ready;
    reg [7:0]   enc_rx_tdata;
    reg         enc_rx_tvalid;
    wire        enc_rx_tready;
    reg         enc_rx_tlast;

    // =========================================================================
    // Bridge: encrypt TX → decrypt RX (direct wiring)
    // =========================================================================
    wire        bridge_hdr_valid;
    wire [15:0] bridge_payload_len;
    wire        bridge_hdr_ready;
    wire [7:0]  bridge_tdata;
    wire        bridge_tvalid;
    wire        bridge_tready;
    wire        bridge_tlast;

    // =========================================================================
    // Decrypt TX Output (decrypt → testbench)
    // =========================================================================
    wire        dec_tx_hdr_valid;
    wire [15:0] dec_tx_payload_len;
    wire [7:0]  dec_tx_tdata;
    wire        dec_tx_tvalid;
    wire        dec_tx_tlast;

    // =========================================================================
    // Status
    // =========================================================================
    wire        enc_busy, enc_done;
    wire        dec_busy, dec_done;
    wire        dec_authOk, dec_authFail;

    // =========================================================================
    // Encrypt Instance
    // =========================================================================
    gcm_axi_top u_encrypt (
        .clk              (clk),
        .rst              (rst),
        .key_axis_tdata   (key_tdata),
        .key_axis_tvalid  (key_tvalid),
        .key_axis_tready  (enc_key_tready),
        .key_axis_tlast   (key_tlast),
        .iv_axis_tdata    (8'd0),
        .iv_axis_tvalid   (1'b0),
        .iv_axis_tready   (),
        .iv_axis_tlast    (1'b0),
        .rx_hdr_valid     (enc_rx_hdr_valid),
        .rx_payload_len   (enc_rx_payload_len),
        .rx_hdr_ready     (enc_rx_hdr_ready),
        .rx_payload_tdata (enc_rx_tdata),
        .rx_payload_tvalid(enc_rx_tvalid),
        .rx_payload_tready(enc_rx_tready),
        .rx_payload_tlast (enc_rx_tlast),
        .tx_hdr_valid     (bridge_hdr_valid),
        .tx_payload_len   (bridge_payload_len),
        .tx_hdr_ready     (bridge_hdr_ready),
        .tx_payload_tdata (bridge_tdata),
        .tx_payload_tvalid(bridge_tvalid),
        .tx_payload_tready(bridge_tready),
        .tx_payload_tlast (bridge_tlast),
        .keyError         (),
        .ivError          (),
        .encBusy          (enc_busy),
        .encDone          (enc_done)
    );

    // =========================================================================
    // Decrypt Instance
    // =========================================================================
    gcm_axi_decrypt u_decrypt (
        .clk              (clk),
        .rst              (rst),
        .key_axis_tdata   (key_tdata),
        .key_axis_tvalid  (key_tvalid),
        .key_axis_tready  (dec_key_tready),
        .key_axis_tlast   (key_tlast),
        .rx_hdr_valid     (bridge_hdr_valid),
        .rx_payload_len   (bridge_payload_len),
        .rx_hdr_ready     (bridge_hdr_ready),
        .rx_payload_tdata (bridge_tdata),
        .rx_payload_tvalid(bridge_tvalid),
        .rx_payload_tready(bridge_tready),
        .rx_payload_tlast (bridge_tlast),
        .tx_hdr_valid     (dec_tx_hdr_valid),
        .tx_payload_len   (dec_tx_payload_len),
        .tx_hdr_ready     (1'b1),
        .tx_payload_tdata (dec_tx_tdata),
        .tx_payload_tvalid(dec_tx_tvalid),
        .tx_payload_tready(1'b1),
        .tx_payload_tlast (dec_tx_tlast),
        .keyError         (),
        .decBusy          (dec_busy),
        .decDone          (dec_done),
        .authOk           (dec_authOk),
        .authFail         (dec_authFail)
    );

    // =========================================================================
    // Plaintext Storage (input and output capture)
    // =========================================================================
    reg [7:0]   ptIn  [0:1599];
    reg [7:0]   ptOut [0:1599];
    integer     ptOutCount;

    always @(posedge clk) begin
        if (rst)
            ptOutCount <= 0;
        else if (dec_tx_tvalid) begin
            ptOut[ptOutCount] <= dec_tx_tdata;
            ptOutCount <= ptOutCount + 1;
        end
    end

    // =========================================================================
    // Encrypt RX transfer detect (for backpressure)
    // =========================================================================
    reg encRxXfer;
    always @(posedge clk) begin
        if (rst) encRxXfer <= 1'b0;
        else     encRxXfer <= enc_rx_tvalid && enc_rx_tready;
    end

    // =========================================================================
    // Test Tracking
    // =========================================================================
    integer testNum;
    integer passCount;
    integer failCount;

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    task init;
    begin
        key_tdata         = 8'd0;
        key_tvalid        = 1'b0;
        key_tlast         = 1'b0;
        enc_rx_hdr_valid  = 1'b0;
        enc_rx_payload_len = 16'd0;
        enc_rx_tdata      = 8'd0;
        enc_rx_tvalid     = 1'b0;
        enc_rx_tlast      = 1'b0;
    end
    endtask

    task resetAll;
    begin
        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);
    end
    endtask

    task sendKey;
        input [255:0] keyVal;
        integer i;
    begin
        for (i = 0; i < 32; i = i + 1) begin
            key_tdata  = keyVal[255 - i*8 -: 8];
            key_tvalid = 1'b1;
            key_tlast  = (i == 31) ? 1'b1 : 1'b0;
            @(posedge clk);
            while (!key_tready) @(posedge clk);
        end
        key_tvalid = 1'b0;
        key_tlast  = 1'b0;
        repeat (3) @(posedge clk);
    end
    endtask

    // Generate deterministic plaintext pattern: ptIn[i] = i mod 256
    task generatePt;
        input integer ptLen;
        integer i;
    begin
        for (i = 0; i < ptLen; i = i + 1)
            ptIn[i] = i[7:0];
    end
    endtask

    // Feed plaintext into encrypt path
    task feedEncrypt;
        input [15:0] ptLen;
        integer i;
    begin
        enc_rx_payload_len = ptLen;
        enc_rx_hdr_valid   = 1'b1;
        @(posedge clk);
        #1;
        enc_rx_hdr_valid   = 1'b0;

        for (i = 0; i < ptLen; i = i + 1) begin
            enc_rx_tdata  = ptIn[i];
            enc_rx_tvalid = 1'b1;
            enc_rx_tlast  = (i == ptLen - 1) ? 1'b1 : 1'b0;
            @(posedge clk);
            #1;
            while (!encRxXfer) begin
                @(posedge clk);
                #1;
            end
        end
        enc_rx_tvalid = 1'b0;
        enc_rx_tlast  = 1'b0;
    end
    endtask

    // Wait for decrypt to complete
    task waitForDecrypt;
        integer timeout;
    begin
        timeout = 0;
        while (!dec_done && timeout < 2000000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 2000000)
            $display("  ERROR: Timeout waiting for decrypt done (%0d cycles)", timeout);
    end
    endtask

    // Compare input and output plaintext
    task verifyRoundtrip;
        input integer ptLen;
        input [399:0] label;
        integer i;
        integer mismatchCount;
        integer firstMismatch;
    begin
        mismatchCount = 0;
        firstMismatch = -1;
        for (i = 0; i < ptLen; i = i + 1) begin
            if (ptOut[i] !== ptIn[i]) begin
                mismatchCount = mismatchCount + 1;
                if (firstMismatch == -1)
                    firstMismatch = i;
            end
        end
        if (mismatchCount == 0) begin
            $display("  PASS: %0s (%0d bytes)", label, ptLen);
            passCount = passCount + 1;
        end
        else begin
            $display("  FAIL: %0s — %0d mismatches starting at byte %0d", label, mismatchCount, firstMismatch);
            // Show first 5 mismatches
            begin : showMismatch
                integer j;
                integer shown;
                shown = 0;
                for (j = 0; j < ptLen && shown < 5; j = j + 1) begin
                    if (ptOut[j] !== ptIn[j]) begin
                        $display("    byte[%0d] sent=%h recovered=%h", j, ptIn[j], ptOut[j]);
                        shown = shown + 1;
                    end
                end
                if (mismatchCount > 5)
                    $display("    ... and %0d more", mismatchCount - 5);
            end
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
    // Test Sequence
    // =========================================================================
    initial begin
        testNum   = 0;
        passCount = 0;
        failCount = 0;

        $display("");
        $display("##### MTU Roundtrip Test #####");
        $display("");

        init();
        resetAll();

        // Load a non-trivial key for all tests
        sendKey(256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308);

        // =================================================================
        // TEST 1: 256 bytes (16 full blocks)
        //         Warm-up at medium scale before full MTU.
        // =================================================================
        testNum = 1;
        $display("==========================================================");
        $display("TEST %0d: 256-byte roundtrip (16 blocks)", testNum);
        $display("==========================================================");

        generatePt(256);
        feedEncrypt(16'd256);
        waitForDecrypt();

        checkPass("dec_tx_payload_len == 256", dec_tx_payload_len == 16'd256);
        checkPass("ptOutCount == 256",         ptOutCount == 256);
        verifyRoundtrip(256, "Plaintext recovered");
        checkPass("authOk == 1",   dec_authOk   == 1'b1);
        checkPass("authFail == 0", dec_authFail == 1'b0);

        $display("  (256B: %0d output bytes captured)", ptOutCount);

        init();
        resetAll();
        sendKey(256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308);

        // =================================================================
        // TEST 2: 1488 bytes (93 full 16-byte blocks, no partial)
        //         Tests exact block boundary — no partial block handling.
        //         93 blocks × ~150 cycles = ~13,950 cycles of processing.
        // =================================================================
        testNum = 2;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 1488-byte roundtrip (93 blocks, no partial)", testNum);
        $display("==========================================================");

        generatePt(1488);
        feedEncrypt(16'd1488);
        waitForDecrypt();

        checkPass("dec_tx_payload_len == 1488", dec_tx_payload_len == 16'd1488);
        checkPass("ptOutCount == 1488",         ptOutCount == 1488);
        verifyRoundtrip(1488, "Plaintext recovered");
        checkPass("authOk == 1",   dec_authOk   == 1'b1);
        checkPass("authFail == 0", dec_authFail == 1'b0);

        $display("  (1488B: %0d output bytes captured)", ptOutCount);

        init();
        resetAll();
        sendKey(256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308);

        // =================================================================
        // TEST 3: 1500 bytes (Full Ethernet MTU)
        //         93 full blocks + 12-byte partial final block.
        //         This is the maximum payload the wrapper will handle
        //         in production on the bump-in-the-wire device.
        //
        //         Encrypted output: 12 + 1500 + 16 = 1528 bytes
        //         Processing: ~94 × 150 = ~14,100 clock cycles
        //         Time at 100 MHz: ~141 µs per packet
        // =================================================================
        testNum = 3;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 1500-byte roundtrip (FULL ETHERNET MTU)", testNum);
        $display("  93 full blocks + 12-byte partial block");
        $display("  Encrypted packet: 1528 bytes on the wire");
        $display("==========================================================");

        generatePt(1500);
        feedEncrypt(16'd1500);
        waitForDecrypt();

        checkPass("dec_tx_payload_len == 1500", dec_tx_payload_len == 16'd1500);
        checkPass("ptOutCount == 1500",         ptOutCount == 1500);
        verifyRoundtrip(1500, "Plaintext recovered (FULL MTU)");
        checkPass("authOk == 1",   dec_authOk   == 1'b1);
        checkPass("authFail == 0", dec_authFail == 1'b0);

        $display("  (1500B: %0d output bytes captured)", ptOutCount);

        // =================================================================
        // Summary
        // =================================================================
        $display("");
        $display("==========================================================");
        $display("MTU ROUNDTRIP SUMMARY: %0d passed, %0d failed out of %0d",
                 passCount, failCount, passCount + failCount);
        $display("==========================================================");
        $display("  Sizes tested: 256B (16 blocks), 1488B (93 blocks), 1500B (94 blocks)");
        $display("  Pattern: ptBytes[i] = i mod 256");

        if (failCount == 0)
            $display("ALL MTU TESTS PASSED");
        else
            $display("SOME MTU TESTS FAILED");

        $finish;
    end

endmodule
