`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: tb_gcm_axi_top
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: End-to-end testbench for gcm_axi_top. Feeds individual
//              plaintext bytes on the 8-bit RX payload interface (simulating
//              the Ethernet stack) and verifies the TX byte stream against
//              NIST test vectors. Exercises the full pipeline:
//              rx_payload → width converter → shim → encrypt → tx_payload.
//
// Dependencies: gcm_axi_top, axis_dwidth_converter_0 (Vivado IP),
//               gcm_rx_shim, gcm_axi_encrypt, gcm_axi_config,
//               gcm_tx_serializer, aes_gcm_256 and all crypto submodules.
//
// Notes: Must be run in Vivado (requires Vivado IP for width converter).
//
//////////////////////////////////////////////////////////////////////////////////

module tb_gcm_axi_top;

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

    // Key AXI-Stream
    reg [7:0]   key_axis_tdata;
    reg         key_axis_tvalid;
    wire        key_axis_tready;
    reg         key_axis_tlast;

    // IV AXI-Stream
    reg [7:0]   iv_axis_tdata;
    reg         iv_axis_tvalid;
    wire        iv_axis_tready;
    reg         iv_axis_tlast;

    // RX header
    reg         rx_hdr_valid;
    reg [15:0]  rx_payload_len;
    wire        rx_hdr_ready;

    // RX payload (8-bit byte stream)
    reg [7:0]   rx_payload_tdata;
    reg         rx_payload_tvalid;
    wire        rx_payload_tready;
    reg         rx_payload_tlast;

    // TX header
    wire        tx_hdr_valid;
    wire [15:0] tx_payload_len;
    reg         tx_hdr_ready;

    // TX payload (8-bit byte stream)
    wire [7:0]  tx_payload_tdata;
    wire        tx_payload_tvalid;
    reg         tx_payload_tready;
    wire        tx_payload_tlast;

    // Status
    wire        keyError;
    wire        ivError;
    wire        encBusy;
    wire        encDone;

    // =========================================================================
    // TX Byte Capture Monitor
    // =========================================================================
    reg [7:0]   capturedBytes [0:1599];
    reg         capturedTlast [0:1599];
    integer     captureCount;

    always @(posedge clk) begin
        if (rst) begin
            captureCount <= 0;
        end
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
    // DUT Instantiation
    // =========================================================================
    gcm_axi_top u_dut (
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
        .ivError          (ivError),
        .encBusy          (encBusy),
        .encDone          (encDone)
    );

    // =========================================================================
    // Plaintext Storage (for byte-serial feeding)
    // =========================================================================
    reg [7:0] ptBytes [0:255];
    integer   ptByteCount;

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    task init;
    begin
        key_axis_tdata    = 8'd0;
        key_axis_tvalid   = 1'b0;
        key_axis_tlast    = 1'b0;
        iv_axis_tdata     = 8'd0;
        iv_axis_tvalid    = 1'b0;
        iv_axis_tlast     = 1'b0;
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

    // Send a 32-byte key via AXI-Stream
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

    // Send a 12-byte IV seed via AXI-Stream
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
        repeat (3) @(posedge clk);
    end
    endtask

    // Load plaintext bytes into ptBytes array from a 128-bit block (MSB-first)
    task loadPtBlock;
        input [127:0] block;
        input integer  numBytes;
        integer i;
    begin
        for (i = 0; i < numBytes; i = i + 1) begin
            ptBytes[ptByteCount] = block[127 - i*8 -: 8];
            ptByteCount = ptByteCount + 1;
        end
    end
    endtask

    // Start packet and feed all plaintext bytes with AXI-Stream handshaking.
    // Waits for rx_hdr_ready before sending header.
    // Feeds bytes one per cycle, respecting rx_payload_tready backpressure.
    task feedPacket;
        input [15:0] ptLen;
        integer i;
    begin
        // Phase 1: header handshake
        // FSM is in ST_IDLE at this point, so rx_hdr_ready is high.
        // Handshake completes on the first posedge.
        rx_payload_len = ptLen;
        rx_hdr_valid   = 1'b1;
        @(posedge clk);
        rx_hdr_valid   = 1'b0;

        // Phase 2: feed bytes one at a time
        if (ptLen > 0) begin
            for (i = 0; i < ptLen; i = i + 1) begin
                rx_payload_tdata  = ptBytes[i];
                rx_payload_tvalid = 1'b1;
                rx_payload_tlast  = (i == ptLen - 1) ? 1'b1 : 1'b0;
                @(posedge clk);
                while (!rx_payload_tready) @(posedge clk);
            end
            rx_payload_tvalid = 1'b0;
            rx_payload_tlast  = 1'b0;
        end
    end
    endtask

    // Wait for DUT FSM to return to idle
    task waitForDone;
        integer timeout;
    begin
        timeout = 0;
        while (encBusy && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 200000)
            $display("  ERROR: Timeout waiting for encBusy to deassert");
        repeat (5) @(posedge clk);
    end
    endtask

    // Check a range of captured bytes against expected 128-bit value (MSB-first)
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

    // Check IV bytes (first 12 of captured output)
    task checkIvBytes;
        input [95:0]  expectedIv;
        input [399:0] label;
    begin
        checkBlock128(0, {expectedIv, 32'd0}, 12, label);
    end
    endtask

    // Check that tlast is asserted only on the final byte
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
    // NIST Test Vectors
    // =========================================================================

    // All-zero key/IV, 16-byte zero plaintext
    localparam [127:0] CT_T2   = 128'hcea7403d4d606b6e074ec5d3baf39d18;
    localparam [127:0] TAG_T2  = 128'hd0d1c8a799996bf0265b98b5d48ab919;

    // All-zero key/IV, empty plaintext (GMAC)
    localparam [127:0] TAG_T1  = 128'h530f8afbc74536b9a963b4f1c4cb738b;

    // Test Case 15: K=feffe9..., IV=cafebabe..., 64-byte PT
    localparam [255:0] KEY_TC15  = 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308;
    localparam [95:0]  IV_TC15   = 96'hcafebabefacedbaddecaf888;
    localparam [127:0] PT_TC15_0 = 128'hd9313225f88406e5a55909c5aff5269a;
    localparam [127:0] PT_TC15_1 = 128'h86a7a9531534f7da2e4c303d8a318a72;
    localparam [127:0] PT_TC15_2 = 128'h1c3c0c95956809532fcf0e2449a6b525;
    localparam [127:0] PT_TC15_3 = 128'hb16aedf5aa0de657ba637b391aafd255;
    localparam [127:0] CT_TC15_0 = 128'h522dc1f099567d07f47f37a32a84427d;
    localparam [127:0] CT_TC15_1 = 128'h643a8cdcbfe5c0c97598a2bd2555d1aa;
    localparam [127:0] CT_TC15_2 = 128'h8cb08e48590dbb3da7b08b1056828838;
    localparam [127:0] CT_TC15_3 = 128'hc5f61e6393ba7a0abcc9f662898015ad;
    localparam [127:0] TAG_TC15  = 128'hb094dac5d93471bdec1a502270e3cc6c;

    // Test Case 16: same key/IV, 60-byte PT (partial final block)
    localparam [127:0] PT_TC16_3 = 128'hb16aedf5aa0de657ba637b3900000000; // 12 bytes valid
    localparam [127:0] CT_TC16_0 = 128'h522dc1f099567d07f47f37a32a84427d;
    localparam [127:0] CT_TC16_1 = 128'h643a8cdcbfe5c0c97598a2bd2555d1aa;
    localparam [127:0] CT_TC16_2 = 128'h8cb08e48590dbb3da7b08b1056828838;
    localparam [127:0] CT_TC16_3 = 128'hc5f61e6393ba7a0abcc9f66200000000; // 12 bytes valid
    localparam [127:0] TAG_TC16  = 128'hb094dac5d93471bdec1a502270e3cc6c;

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
        // TEST 1: 16-byte zero PT, default key/IV (all zeros)
        //         Byte-in to byte-out through full pipeline.
        //         TX output: IV(12) + CT(16) + Tag(16) = 44 bytes
        // =================================================================
        testNum = 1;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 16B zero PT, default key/IV (end-to-end)", testNum);
        $display("  Expected CT:  cea7403d4d606b6e074ec5d3baf39d18");
        $display("  Expected Tag: d0d1c8a799996bf0265b98b5d48ab919");
        $display("==========================================================");

        ptByteCount = 0;
        loadPtBlock(128'h00000000000000000000000000000000, 16);

        feedPacket(16'd16);
        waitForDone();

        checkPass("tx_payload_len == 44", tx_payload_len == 16'd44);
        checkPass("captureCount == 44",   captureCount == 44);
        checkIvBytes(96'h000000000000000000000000, "IV (all zeros)");
        checkBlock128(12, CT_T2,  16, "CT block (NIST)");
        checkBlock128(28, TAG_T2, 16, "Tag (NIST)");
        checkTlast(44, "tlast position");
        checkPass("No key error", keyError == 1'b0);
        checkPass("No IV error",  ivError  == 1'b0);

        init();
        resetDut();

        // =================================================================
        // TEST 2: Empty PT (GMAC mode), default key/IV
        //         TX output: IV(12) + Tag(16) = 28 bytes
        // =================================================================
        testNum = 2;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Empty PT (GMAC), default key/IV", testNum);
        $display("  Expected Tag: 530f8afbc74536b9a963b4f1c4cb738b");
        $display("==========================================================");

        ptByteCount = 0;
        // No loadPtBlock — zero length

        feedPacket(16'd0);
        waitForDone();

        checkPass("tx_payload_len == 28", tx_payload_len == 16'd28);
        checkPass("captureCount == 28",   captureCount == 28);
        checkIvBytes(96'h000000000000000000000000, "IV (all zeros)");
        checkBlock128(12, TAG_T1, 16, "Tag (NIST GMAC)");
        checkTlast(28, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 3: 64-byte PT (4 full blocks), TC15 key/IV
        //         Full pipeline with key/IV loading via AXI-Stream.
        //         TX output: IV(12) + CT(64) + Tag(16) = 92 bytes
        // =================================================================
        testNum = 3;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 64B PT (4 blocks), TC15 key/IV", testNum);
        $display("  Expected Tag: b094dac5d93471bdec1a502270e3cc6c");
        $display("==========================================================");

        sendKey(KEY_TC15);
        sendIv(IV_TC15);

        ptByteCount = 0;
        loadPtBlock(PT_TC15_0, 16);
        loadPtBlock(PT_TC15_1, 16);
        loadPtBlock(PT_TC15_2, 16);
        loadPtBlock(PT_TC15_3, 16);

        feedPacket(16'd64);
        waitForDone();

        checkPass("tx_payload_len == 92", tx_payload_len == 16'd92);
        checkPass("captureCount == 92",   captureCount == 92);
        checkIvBytes(IV_TC15, "IV (cafebabe...)");
        checkBlock128(12, CT_TC15_0, 16, "CT block 0 (NIST)");
        checkBlock128(28, CT_TC15_1, 16, "CT block 1 (NIST)");
        checkBlock128(44, CT_TC15_2, 16, "CT block 2 (NIST)");
        checkBlock128(60, CT_TC15_3, 16, "CT block 3 (NIST)");
        checkBlock128(76, TAG_TC15,  16, "Tag (NIST TC15)");
        checkTlast(92, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 4: 60-byte PT (3 full + 12-byte partial), TC15 key/IV
        //         Tests partial final block through width converter.
        //         CT blocks 0-2 and first 12 bytes of block 3 match TC15
        //         (same counter sequence, same key). Tag differs from TC15
        //         because the GHASH length field changes (60 vs 64 bytes),
        //         so it is not checked here — no NIST reference exists for
        //         60B PT without AAD.
        //         TX output: IV(12) + CT(60) + Tag(16) = 88 bytes
        // =================================================================
        testNum = 4;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 60B PT (partial last block), TC15 key/IV", testNum);
        $display("==========================================================");

        sendKey(KEY_TC15);
        sendIv(IV_TC15);

        ptByteCount = 0;
        loadPtBlock(PT_TC15_0, 16);
        loadPtBlock(PT_TC15_1, 16);
        loadPtBlock(PT_TC15_2, 16);
        loadPtBlock(PT_TC16_3, 12); // Only 12 bytes

        feedPacket(16'd60);
        waitForDone();

        checkPass("tx_payload_len == 88", tx_payload_len == 16'd88);
        checkPass("captureCount == 88",   captureCount == 88);
        checkIvBytes(IV_TC15, "IV (cafebabe...)");
        checkBlock128(12, CT_TC15_0, 16, "CT block 0 (matches TC15)");
        checkBlock128(28, CT_TC15_1, 16, "CT block 1 (matches TC15)");
        checkBlock128(44, CT_TC15_2, 16, "CT block 2 (matches TC15)");
        checkBlock128(60, CT_TC16_3, 12, "CT block 3 (12B, matches TC15)");
        // Tag not checked — no NIST reference for 60B PT without AAD
        checkTlast(88, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 5: Back-to-back packets — IV auto-increment
        //         Packet 1 uses default IV (00...00)
        //         Packet 2 should use auto-incremented IV (00...01)
        // =================================================================
        testNum = 5;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Back-to-back packets, IV auto-increment", testNum);
        $display("==========================================================");

        // Packet 1
        ptByteCount = 0;
        loadPtBlock(128'h00000000000000000000000000000000, 16);
        feedPacket(16'd16);
        waitForDone();

        checkPass("Pkt1 captureCount == 44", captureCount == 44);
        checkIvBytes(96'h000000000000000000000000, "Pkt1 IV (00..00)");
        $display("  Packet 1 done. IV byte[11] = %h (expect 00)", capturedBytes[11]);

        // Packet 2 — capture starts at offset 44
        begin : pkt2_block
            integer pkt2Start;
            pkt2Start = captureCount;

            ptByteCount = 0;
            loadPtBlock(128'h00000000000000000000000000000000, 16);
            feedPacket(16'd16);
            waitForDone();

            checkPass("Pkt2 byte count == 44", (captureCount - pkt2Start) == 44);
            checkBlock128(pkt2Start, {96'h000000000000000000000001, 32'd0}, 12, "Pkt2 IV (00..01)");
            $display("  Packet 2 done. IV byte[%0d] = %h (expect 01)",
                     pkt2Start + 11, capturedBytes[pkt2Start + 11]);
        end

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
