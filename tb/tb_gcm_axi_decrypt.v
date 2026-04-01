`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: tb_gcm_axi_decrypt
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: End-to-end testbench for gcm_axi_decrypt. Constructs
//              encrypted packets from NIST test vectors, feeds them
//              as byte streams, and verifies plaintext output and
//              authentication results.
//
// Dependencies: gcm_axi_decrypt, gcm_axi_config, gcm_rx_parser,
//               axis_dwidth_converter_0 (Vivado IP), gcm_rx_shim,
//               gcm_pt_serializer, aes_gcm_256 + all crypto submodules.
//
//////////////////////////////////////////////////////////////////////////////////

module tb_gcm_axi_decrypt;

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
    reg [7:0]   key_axis_tdata;
    reg         key_axis_tvalid;
    wire        key_axis_tready;
    reg         key_axis_tlast;

    reg         rx_hdr_valid;
    reg [15:0]  rx_payload_len;
    wire        rx_hdr_ready;

    reg [7:0]   rx_payload_tdata;
    reg         rx_payload_tvalid;
    wire        rx_payload_tready;
    reg         rx_payload_tlast;

    wire        tx_hdr_valid;
    wire [15:0] tx_payload_len;
    reg         tx_hdr_ready;

    wire [7:0]  tx_payload_tdata;
    wire        tx_payload_tvalid;
    reg         tx_payload_tready;
    wire        tx_payload_tlast;

    wire        keyError;
    wire        decBusy;
    wire        decDone;
    wire        authOk;
    wire        authFail;

    // =========================================================================
    // TX Byte Capture
    // =========================================================================
    reg [7:0]   capturedBytes [0:1599];
    reg         capturedTlast [0:1599];
    integer     captureCount;

    always @(posedge clk) begin
        if (rst)
            captureCount <= 0;
        else if (tx_payload_tvalid && tx_payload_tready) begin
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
    // Registered transfer detect (for backpressure handling)
    // =========================================================================
    reg rxXfer;
    always @(posedge clk) begin
        if (rst) rxXfer <= 1'b0;
        else     rxXfer <= rx_payload_tvalid && rx_payload_tready;
    end

    // =========================================================================
    // DUT
    // =========================================================================
    gcm_axi_decrypt u_dut (
        .clk              (clk),
        .rst              (rst),
        .key_axis_tdata   (key_axis_tdata),
        .key_axis_tvalid  (key_axis_tvalid),
        .key_axis_tready  (key_axis_tready),
        .key_axis_tlast   (key_axis_tlast),
        .rx_hdr_valid     (rx_hdr_valid),
        .rx_payload_len   (rx_payload_len),
        .rx_hdr_ready     (rx_hdr_ready),
        .rx_payload_tdata (rx_payload_tdata),
        .rx_payload_tvalid(rx_payload_tvalid),
        .rx_payload_tready(rx_payload_tready),
        .rx_payload_tlast (rx_payload_tlast),
        .tx_hdr_valid     (tx_hdr_valid),
        .tx_payload_len   (tx_payload_len),
        .tx_hdr_ready     (tx_hdr_ready),
        .tx_payload_tdata (tx_payload_tdata),
        .tx_payload_tvalid(tx_payload_tvalid),
        .tx_payload_tready(tx_payload_tready),
        .tx_payload_tlast (tx_payload_tlast),
        .keyError         (keyError),
        .decBusy          (decBusy),
        .decDone          (decDone),
        .authOk           (authOk),
        .authFail         (authFail)
    );

    // =========================================================================
    // Packet Builder
    // =========================================================================
    reg [7:0] pktBytes [0:1599];
    integer   pktByteCount;

    task buildStart;
        input [95:0] iv;
        integer i;
    begin
        pktByteCount = 0;
        for (i = 0; i < 12; i = i + 1) begin
            pktBytes[pktByteCount] = iv[95 - i*8 -: 8];
            pktByteCount = pktByteCount + 1;
        end
    end
    endtask

    task buildAddBlock;
        input [127:0] block;
        input integer  numBytes;
        integer i;
    begin
        for (i = 0; i < numBytes; i = i + 1) begin
            pktBytes[pktByteCount] = block[127 - i*8 -: 8];
            pktByteCount = pktByteCount + 1;
        end
    end
    endtask

    task buildAddTag;
        input [127:0] tag;
        integer i;
    begin
        for (i = 0; i < 16; i = i + 1) begin
            pktBytes[pktByteCount] = tag[127 - i*8 -: 8];
            pktByteCount = pktByteCount + 1;
        end
    end
    endtask

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    task init;
    begin
        key_axis_tdata    = 8'd0;
        key_axis_tvalid   = 1'b0;
        key_axis_tlast    = 1'b0;
        rx_hdr_valid      = 1'b0;
        rx_payload_len    = 16'd0;
        rx_payload_tdata  = 8'd0;
        rx_payload_tvalid = 1'b0;
        rx_payload_tlast  = 1'b0;
        tx_hdr_ready      = 1'b1;
        tx_payload_tready = 1'b1;
    end
    endtask

    task resetDut;
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
            key_axis_tdata  = keyVal[255 - i*8 -: 8];
            key_axis_tvalid = 1'b1;
            key_axis_tlast  = (i == 31) ? 1'b1 : 1'b0;
            @(posedge clk);
        end
        key_axis_tvalid = 1'b0;
        key_axis_tlast  = 1'b0;
        repeat (3) @(posedge clk);
    end
    endtask

    // Feed encrypted packet bytes.
    // Uses #1 to break active-region race and rxXfer for backpressure.
    task feedPacket;
        input [15:0] totalLen;
        integer i;
    begin
        rx_payload_len = totalLen;
        rx_hdr_valid   = 1'b1;
        @(posedge clk);
        #1;
        rx_hdr_valid   = 1'b0;

        for (i = 0; i < totalLen; i = i + 1) begin
            rx_payload_tdata  = pktBytes[i];
            rx_payload_tvalid = 1'b1;
            rx_payload_tlast  = (i == totalLen - 1) ? 1'b1 : 1'b0;
            @(posedge clk);
            #1;
            while (!rxXfer) begin
                @(posedge clk);
                #1;
            end
        end
        rx_payload_tvalid = 1'b0;
        rx_payload_tlast  = 1'b0;
    end
    endtask

    task waitForDecDone;
        integer timeout;
    begin
        timeout = 0;
        while (!decDone && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 200000)
            $display("  ERROR: Timeout waiting for decDone");
        // Do NOT advance another cycle — decDone, authOk, authFail
        // are valid right now (from the previous posedge's NBA).
        // The next posedge would clear them via FSM defaults.
    end
    endtask

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
            $display("  FAIL: %0s — tlast NOT set on byte[%0d]", label, totalBytes - 1);
        end
        if (!anyBad) begin
            $display("  PASS: %0s", label);
            passCount = passCount + 1;
        end
        else
            failCount = failCount + 1;
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
    // NIST Test Vectors
    // =========================================================================
    // TC14: all-zero key/IV, 16B PT = all zeros
    localparam [255:0] KEY_ZERO  = 256'h0;
    localparam [95:0]  IV_ZERO   = 96'h0;
    localparam [127:0] CT_T14    = 128'hcea7403d4d606b6e074ec5d3baf39d18;
    localparam [127:0] TAG_T14   = 128'hd0d1c8a799996bf0265b98b5d48ab919;
    localparam [127:0] PT_T14    = 128'h00000000000000000000000000000000;

    // TC15: 64B PT
    localparam [255:0] KEY_TC15  = 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308;
    localparam [95:0]  IV_TC15   = 96'hcafebabefacedbaddecaf888;
    localparam [127:0] CT_TC15_0 = 128'h522dc1f099567d07f47f37a32a84427d;
    localparam [127:0] CT_TC15_1 = 128'h643a8cdcbfe5c0c97598a2bd2555d1aa;
    localparam [127:0] CT_TC15_2 = 128'h8cb08e48590dbb3da7b08b1056828838;
    localparam [127:0] CT_TC15_3 = 128'hc5f61e6393ba7a0abcc9f662898015ad;
    localparam [127:0] TAG_TC15  = 128'hb094dac5d93471bdec1a502270e3cc6c;
    localparam [127:0] PT_TC15_0 = 128'hd9313225f88406e5a55909c5aff5269a;
    localparam [127:0] PT_TC15_1 = 128'h86a7a9531534f7da2e4c303d8a318a72;
    localparam [127:0] PT_TC15_2 = 128'h1c3c0c95956809532fcf0e2449a6b525;
    localparam [127:0] PT_TC15_3 = 128'hb16aedf5aa0de657ba637b391aafd255;

    // TC13: empty PT (GMAC), all-zero key/IV
    localparam [127:0] TAG_T13   = 128'h530f8afbc74536b9a963b4f1c4cb738b;

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
        // TEST 1: TC14 — 16B CT, all-zero key/IV, auth pass
        //         Encrypted packet: IV(12) + CT(16) + Tag(16) = 44 bytes
        //         Expected plaintext: 16 bytes of zeros
        // =================================================================
        testNum = 1;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: TC14 — 16B decrypt, auth pass", testNum);
        $display("  Expected PT:  00000000000000000000000000000000");
        $display("==========================================================");

        buildStart(IV_ZERO);
        buildAddBlock(CT_T14, 16);
        buildAddTag(TAG_T14);

        feedPacket(16'd44);
        waitForDecDone();

        checkPass("tx_payload_len == 16", tx_payload_len == 16'd16);
        checkPass("captureCount == 16",   captureCount == 16);
        checkBlock128(0, PT_T14, 16, "PT block (NIST TC14)");
        checkTlast(16, "tlast position");
        checkPass("authOk == 1",   authOk   == 1'b1);
        checkPass("authFail == 0", authFail == 1'b0);

        init();
        resetDut();

        // =================================================================
        // TEST 2: TC15 — 64B CT, auth pass
        //         Encrypted packet: IV(12) + CT(64) + Tag(16) = 92 bytes
        //         Expected: 4 plaintext blocks
        // =================================================================
        testNum = 2;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: TC15 — 64B decrypt, auth pass", testNum);
        $display("==========================================================");

        sendKey(KEY_TC15);

        buildStart(IV_TC15);
        buildAddBlock(CT_TC15_0, 16);
        buildAddBlock(CT_TC15_1, 16);
        buildAddBlock(CT_TC15_2, 16);
        buildAddBlock(CT_TC15_3, 16);
        buildAddTag(TAG_TC15);

        feedPacket(16'd92);
        waitForDecDone();

        checkPass("tx_payload_len == 64", tx_payload_len == 16'd64);
        checkPass("captureCount == 64",   captureCount == 64);
        checkBlock128(0,  PT_TC15_0, 16, "PT block 0 (NIST TC15)");
        checkBlock128(16, PT_TC15_1, 16, "PT block 1 (NIST TC15)");
        checkBlock128(32, PT_TC15_2, 16, "PT block 2 (NIST TC15)");
        checkBlock128(48, PT_TC15_3, 16, "PT block 3 (NIST TC15)");
        checkTlast(64, "tlast position");
        checkPass("authOk == 1",   authOk   == 1'b1);
        checkPass("authFail == 0", authFail == 1'b0);

        init();
        resetDut();

        // =================================================================
        // TEST 3: TC14 with corrupted tag — auth fail
        //         Same CT as Test 1 but LSB of tag flipped.
        //         PT should still be computed (GCM decrypts before auth).
        // =================================================================
        testNum = 3;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: TC14 — corrupted tag, auth fail", testNum);
        $display("==========================================================");

        buildStart(IV_ZERO);
        buildAddBlock(CT_T14, 16);
        buildAddTag(128'hd0d1c8a799996bf0265b98b5d48ab918); // LSB flipped

        feedPacket(16'd44);
        waitForDecDone();

        checkPass("captureCount == 16",   captureCount == 16);
        checkBlock128(0, PT_T14, 16, "PT still correct (GCM decrypts before auth)");
        checkPass("authOk == 0",   authOk   == 1'b0);
        checkPass("authFail == 1", authFail == 1'b1);

        init();
        resetDut();

        // =================================================================
        // TEST 4: Zero CT (GMAC) — tag only, auth pass
        //         Encrypted packet: IV(12) + Tag(16) = 28 bytes
        //         No plaintext output expected.
        // =================================================================
        testNum = 4;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Zero CT (GMAC), auth pass", testNum);
        $display("==========================================================");

        buildStart(IV_ZERO);
        buildAddTag(TAG_T13);

        feedPacket(16'd28);
        waitForDecDone();

        checkPass("tx_payload_len == 0", tx_payload_len == 16'd0);
        checkPass("captureCount == 0",   captureCount == 0);
        checkPass("authOk == 1",   authOk   == 1'b1);
        checkPass("authFail == 0", authFail == 1'b0);

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
