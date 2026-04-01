`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: tb_roundtrip
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Roundtrip verification testbench. Wires gcm_axi_top (encrypt)
//              TX output directly to gcm_axi_decrypt RX input. Feeds plaintext
//              bytes into the encrypt path and verifies that the decrypt path
//              recovers the identical plaintext with authentication passing.
//
//              This is the single strongest correctness test for the system:
//              it proves encrypt and decrypt are wire-compatible and that the
//              IV prepend/extract and tag append/verify work end-to-end.
//
// Dependencies: gcm_axi_top, gcm_axi_decrypt, and all their submodules.
//               Two instances of axis_dwidth_converter_0 (Vivado IP).
//
//////////////////////////////////////////////////////////////////////////////////

module tb_roundtrip;

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
    // Key Loading (shared bus, AND tready)
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
    // Encrypt TX ↔ Decrypt RX (direct wiring)
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
    // Decrypt Status
    // =========================================================================
    wire        dec_busy;
    wire        dec_done;
    wire        dec_authOk;
    wire        dec_authFail;
    wire        enc_busy;
    wire        enc_done;

    // =========================================================================
    // Encrypt Instance (gcm_axi_top)
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
        // TX output → bridge → decrypt RX
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
    // Decrypt Instance (gcm_axi_decrypt)
    // =========================================================================
    gcm_axi_decrypt u_decrypt (
        .clk              (clk),
        .rst              (rst),
        .key_axis_tdata   (key_tdata),
        .key_axis_tvalid  (key_tvalid),
        .key_axis_tready  (dec_key_tready),
        .key_axis_tlast   (key_tlast),
        // RX input ← bridge ← encrypt TX
        .rx_hdr_valid     (bridge_hdr_valid),
        .rx_payload_len   (bridge_payload_len),
        .rx_hdr_ready     (bridge_hdr_ready),
        .rx_payload_tdata (bridge_tdata),
        .rx_payload_tvalid(bridge_tvalid),
        .rx_payload_tready(bridge_tready),
        .rx_payload_tlast (bridge_tlast),
        // TX output → testbench capture
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
    // Plaintext Input Storage
    // =========================================================================
    reg [7:0] ptInBytes [0:1599];
    integer   ptInCount;

    // =========================================================================
    // Decrypt Output Capture
    // =========================================================================
    reg [7:0]   ptOutBytes [0:1599];
    reg         ptOutTlast [0:1599];
    integer     ptOutCount;

    always @(posedge clk) begin
        if (rst)
            ptOutCount <= 0;
        else if (dec_tx_tvalid) begin
            ptOutBytes[ptOutCount] <= dec_tx_tdata;
            ptOutTlast[ptOutCount] <= dec_tx_tlast;
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

    // Load key into BOTH encrypt and decrypt simultaneously
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

    // Load plaintext bytes from a 128-bit block
    task loadPtBlock;
        input [127:0] block;
        input integer  numBytes;
        integer i;
    begin
        for (i = 0; i < numBytes; i = i + 1) begin
            ptInBytes[ptInCount] = block[127 - i*8 -: 8];
            ptInCount = ptInCount + 1;
        end
    end
    endtask

    // Feed plaintext into the encrypt path
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
            enc_rx_tdata  = ptInBytes[i];
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
        while (!dec_done && timeout < 500000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 500000)
            $display("  ERROR: Timeout waiting for decrypt done");
    end
    endtask

    // Compare input plaintext with output plaintext byte-by-byte
    task verifyRoundtrip;
        input integer ptLen;
        input [399:0] label;
        integer i;
        reg allMatch;
    begin
        allMatch = 1'b1;
        for (i = 0; i < ptLen; i = i + 1) begin
            if (ptOutBytes[i] !== ptInBytes[i])
                allMatch = 1'b0;
        end
        if (allMatch) begin
            $display("  PASS: %0s (%0d bytes)", label, ptLen);
            passCount = passCount + 1;
        end
        else begin
            $display("  FAIL: %0s", label);
            for (i = 0; i < ptLen; i = i + 1) begin
                if (ptOutBytes[i] !== ptInBytes[i])
                    $display("    byte[%0d] sent=%h recovered=%h",
                             i, ptInBytes[i], ptOutBytes[i]);
            end
            failCount = failCount + 1;
        end
    end
    endtask

    task checkTlast;
        input integer totalBytes;
        input [399:0] label;
        integer i;
        reg anyBad;
    begin
        if (totalBytes == 0) begin
            $display("  PASS: %0s (no bytes)", label);
            passCount = passCount + 1;
        end
        else begin
            anyBad = 1'b0;
            for (i = 0; i < totalBytes - 1; i = i + 1) begin
                if (ptOutTlast[i] === 1'b1) begin
                    anyBad = 1'b1;
                    $display("  FAIL: %0s — spurious tlast at byte[%0d]", label, i);
                end
            end
            if (ptOutTlast[totalBytes - 1] !== 1'b1) begin
                anyBad = 1'b1;
                $display("  FAIL: %0s — tlast NOT set on byte[%0d]", label, totalBytes - 1);
            end
            if (!anyBad) begin
                $display("  PASS: %0s", label);
                passCount = passCount + 1;
            end
            else
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
    // Test Data
    // =========================================================================
    localparam [255:0] KEY_TC15  = 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308;
    localparam [127:0] PT_TC15_0 = 128'hd9313225f88406e5a55909c5aff5269a;
    localparam [127:0] PT_TC15_1 = 128'h86a7a9531534f7da2e4c303d8a318a72;
    localparam [127:0] PT_TC15_2 = 128'h1c3c0c95956809532fcf0e2449a6b525;
    localparam [127:0] PT_TC15_3 = 128'hb16aedf5aa0de657ba637b391aafd255;

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        testNum   = 0;
        passCount = 0;
        failCount = 0;

        init();
        resetAll();

        // =================================================================
        // TEST 1: 16-byte plaintext, default key (all zeros)
        //         Simplest possible roundtrip.
        // =================================================================
        testNum = 1;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 16B roundtrip, default key", testNum);
        $display("==========================================================");

        ptInCount = 0;
        loadPtBlock(128'hDEADBEEFCAFEBABE1234567890ABCDEF, 16);

        feedEncrypt(16'd16);
        waitForDecrypt();

        checkPass("dec_tx_payload_len == 16", dec_tx_payload_len == 16'd16);
        checkPass("ptOutCount == 16",         ptOutCount == 16);
        verifyRoundtrip(16, "Plaintext recovered");
        checkTlast(16, "tlast position");
        checkPass("authOk == 1",   dec_authOk   == 1'b1);
        checkPass("authFail == 0", dec_authFail == 1'b0);

        init();
        resetAll();

        // =================================================================
        // TEST 2: 64-byte plaintext, TC15 key
        //         Multi-block roundtrip with non-default key.
        // =================================================================
        testNum = 2;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 64B roundtrip, TC15 key", testNum);
        $display("==========================================================");

        sendKey(KEY_TC15);

        ptInCount = 0;
        loadPtBlock(PT_TC15_0, 16);
        loadPtBlock(PT_TC15_1, 16);
        loadPtBlock(PT_TC15_2, 16);
        loadPtBlock(PT_TC15_3, 16);

        feedEncrypt(16'd64);
        waitForDecrypt();

        checkPass("dec_tx_payload_len == 64", dec_tx_payload_len == 16'd64);
        checkPass("ptOutCount == 64",         ptOutCount == 64);
        verifyRoundtrip(64, "Plaintext recovered (64B)");
        checkTlast(64, "tlast position");
        checkPass("authOk == 1",   dec_authOk   == 1'b1);
        checkPass("authFail == 0", dec_authFail == 1'b0);

        init();
        resetAll();

        // =================================================================
        // TEST 3: Back-to-back packets (IV auto-increment)
        //         Two 16B packets with same key. Encrypt auto-increments
        //         the IV. Decrypt extracts the IV from each packet.
        //         Both must roundtrip correctly.
        // =================================================================
        testNum = 3;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Back-to-back 16B packets (IV increment)", testNum);
        $display("==========================================================");

        // Packet 1
        ptInCount = 0;
        loadPtBlock(128'h11111111111111111111111111111111, 16);

        feedEncrypt(16'd16);
        waitForDecrypt();

        checkPass("Pkt1 ptOutCount == 16",  ptOutCount == 16);
        verifyRoundtrip(16, "Pkt1 plaintext recovered");
        checkPass("Pkt1 authOk == 1", dec_authOk == 1'b1);

        // Allow both FSMs to return to idle
        repeat (10) @(posedge clk);

        // Packet 2 (different plaintext, auto-incremented IV)
        begin : pkt2_block
            integer pkt2Start;
            pkt2Start = ptOutCount; // Should be 16

            ptInCount = 0;
            loadPtBlock(128'h22222222222222222222222222222222, 16);

            feedEncrypt(16'd16);
            waitForDecrypt();

            checkPass("Pkt2 byte count == 16", (ptOutCount - pkt2Start) == 16);

            // Verify packet 2 plaintext
            begin : verify2
                integer i;
                reg allMatch;
                allMatch = 1'b1;
                for (i = 0; i < 16; i = i + 1) begin
                    if (ptOutBytes[pkt2Start + i] !== ptInBytes[i])
                        allMatch = 1'b0;
                end
                if (allMatch) begin
                    $display("  PASS: Pkt2 plaintext recovered (16 bytes)");
                    passCount = passCount + 1;
                end
                else begin
                    $display("  FAIL: Pkt2 plaintext recovered");
                    failCount = failCount + 1;
                end
            end

            checkPass("Pkt2 authOk == 1", dec_authOk == 1'b1);
        end

        init();
        resetAll();

        // =================================================================
        // TEST 4: 1-byte plaintext (minimum size)
        //         Tests partial-block handling end-to-end.
        // =================================================================
        testNum = 4;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 1-byte roundtrip (minimum size)", testNum);
        $display("==========================================================");

        ptInCount = 0;
        ptInBytes[0] = 8'hA5;
        ptInCount = 1;

        feedEncrypt(16'd1);
        waitForDecrypt();

        checkPass("dec_tx_payload_len == 1", dec_tx_payload_len == 16'd1);
        checkPass("ptOutCount == 1",         ptOutCount == 1);
        checkPass("Byte recovered",          ptOutBytes[0] == 8'hA5);
        checkTlast(1, "tlast position");
        checkPass("authOk == 1",   dec_authOk   == 1'b1);
        checkPass("authFail == 0", dec_authFail == 1'b0);

        init();
        resetAll();

        // =================================================================
        // TEST 5: 33-byte plaintext (2 full blocks + 1 byte)
        //         Non-aligned size crossing block boundary.
        // =================================================================
        testNum = 5;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 33-byte roundtrip (non-aligned)", testNum);
        $display("==========================================================");

        ptInCount = 0;
        loadPtBlock(128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA, 16);
        loadPtBlock(128'hBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB, 16);
        ptInBytes[32] = 8'hCC;
        ptInCount = 33;

        feedEncrypt(16'd33);
        waitForDecrypt();

        checkPass("dec_tx_payload_len == 33", dec_tx_payload_len == 16'd33);
        checkPass("ptOutCount == 33",         ptOutCount == 33);
        verifyRoundtrip(33, "Plaintext recovered (33B)");
        checkTlast(33, "tlast position");
        checkPass("authOk == 1",   dec_authOk   == 1'b1);
        checkPass("authFail == 0", dec_authFail == 1'b0);

        // =================================================================
        // Summary
        // =================================================================
        $display("");
        $display("==========================================================");
        $display("ROUNDTRIP SUMMARY: %0d passed, %0d failed out of %0d",
                 passCount, failCount, passCount + failCount);
        $display("==========================================================");

        if (failCount == 0)
            $display("ALL ROUNDTRIP TESTS PASSED");
        else
            $display("SOME ROUNDTRIP TESTS FAILED");

        $finish;
    end

endmodule
