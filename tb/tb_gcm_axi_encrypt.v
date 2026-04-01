`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: tb_gcm_axi_encrypt
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: End-to-end testbench for gcm_axi_encrypt. Feeds plaintext
//              blocks (simulating the width converter output) and verifies
//              the TX byte stream against NIST test vectors.
//
// Dependencies: gcm_axi_encrypt, gcm_axi_config, gcm_tx_serializer,
//               aes_gcm_256 and all crypto core submodules.
//
// Required source files (add to Vivado simulation project):
//   gcm_axi_config.v, gcm_tx_serializer.v, gcm_axi_encrypt.v,
//   aes_gcm_256.v, aes256.v, aesKeySchedule.v, aesRound_comb.v,
//   subByte.v, mixColumn.v, gfMult.v, ghash.v, gf128_mult.v,
//   gfInverse_canright.v
//
//////////////////////////////////////////////////////////////////////////////////

module tb_gcm_axi_encrypt;

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

    // RX data blocks (128-bit, big-endian)
    reg [127:0] rxBlk_tdata;
    reg         rxBlk_tvalid;
    wire        rxBlk_tready;
    reg         rxBlk_tlast;
    reg [4:0]   rxBlk_byteCount;

    // TX to Ethernet stack
    wire        tx_hdr_valid;
    wire [15:0] tx_payload_len;
    reg         tx_hdr_ready;
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
    // Byte Capture Monitor
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
    gcm_axi_encrypt u_dut (
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
        .rxBlk_tdata      (rxBlk_tdata),
        .rxBlk_tvalid     (rxBlk_tvalid),
        .rxBlk_tready     (rxBlk_tready),
        .rxBlk_tlast      (rxBlk_tlast),
        .rxBlk_byteCount  (rxBlk_byteCount),
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
        rx_hdr_valid    = 1'b0;
        rx_payload_len  = 16'd0;
        rxBlk_tdata     = 128'd0;
        rxBlk_tvalid    = 1'b0;
        rxBlk_tlast     = 1'b0;
        rxBlk_byteCount = 5'd0;
        tx_hdr_ready    = 1'b1;
        tx_payload_tready = 1'b1;
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

    // Start packet: assert rx_hdr_valid with payload length.
    // Assumes FSM is in ST_IDLE and rx_hdr_ready is high.
    task startPacket;
        input [15:0] ptLen;
    begin
        rx_payload_len = ptLen;
        rx_hdr_valid   = 1'b1;
        @(posedge clk);
        rx_hdr_valid   = 1'b0;
    end
    endtask

    // Feed a 128-bit block to the encrypt wrapper.
    // Waits for the FSM to reach ST_PULL_DATA before presenting data.
    task feedBlock;
        input [127:0] data;
        input [4:0]   byteCount;
        input         last;
    begin
        rxBlk_tdata     = data;
        rxBlk_byteCount = byteCount;
        rxBlk_tlast     = last;
        rxBlk_tvalid    = 1'b1;
        // Wait for FSM to enter ST_PULL_DATA (state 3)
        while (u_dut.fsmState !== 4'd3) @(posedge clk);
        // FSM is in ST_PULL_DATA. Next posedge, it latches our data.
        @(posedge clk);
        rxBlk_tvalid = 1'b0;
        rxBlk_tlast  = 1'b0;
    end
    endtask

    // Wait for packet to complete (FSM returns to ST_IDLE)
    task waitForPktDone;
        integer timeout;
    begin
        timeout = 0;
        while (u_dut.fsmState !== 4'd0 && timeout < 100000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 100000)
            $display("  ERROR: Timeout waiting for packet done");
        repeat (2) @(posedge clk);
    end
    endtask

    // Send a full 32-byte key via AXI-Stream (MSB-first)
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

    // Send a full 12-byte IV seed via AXI-Stream (MSB-first)
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

    // Check captured IV bytes (first 12) against expected 96-bit value
    task checkIvBytes;
        input [95:0] expectedIv;
        input [399:0] label;
    begin
        checkBlock128(0, {expectedIv, 32'd0}, 12, label);
    end
    endtask

    // =========================================================================
    // NIST Test Vectors
    // =========================================================================
    // All-zero key/IV, 16-byte zero plaintext (tb_aes_gcm_256 TEST 2)
    localparam [255:0] KEY_ZERO  = 256'h0;
    localparam [95:0]  IV_ZERO   = 96'h0;
    localparam [127:0] PT_ZERO   = 128'h0;
    localparam [127:0] CT_T2     = 128'hcea7403d4d606b6e074ec5d3baf39d18;
    localparam [127:0] TAG_T2    = 128'hd0d1c8a799996bf0265b98b5d48ab919;

    // All-zero key/IV, empty plaintext (tb_aes_gcm_256 TEST 1 — GMAC)
    localparam [127:0] TAG_T1    = 128'h530f8afbc74536b9a963b4f1c4cb738b;

    // Test Case 15: 64-byte PT (McGrew-Viega AES-256)
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
        // TEST 1: Single 16-byte block, default key/IV (all zeros)
        //         TX output: IV(12) + CT(16) + Tag(16) = 44 bytes
        // =================================================================
        testNum = 1;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 16B zero PT, default key/IV", testNum);
        $display("  Expected CT:  cea7403d4d606b6e074ec5d3baf39d18");
        $display("  Expected Tag: d0d1c8a799996bf0265b98b5d48ab919");
        $display("==========================================================");

        startPacket(16'd16);
        feedBlock(PT_ZERO, 5'd0, 1'b1);  // 16 bytes (0 encodes 16), last
        waitForPktDone();

        checkPass("tx_payload_len == 44", tx_payload_len == 16'd44);
        checkPass("captureCount == 44",   captureCount == 44);
        checkIvBytes(IV_ZERO, "IV bytes (all zeros)");
        checkBlock128(12, CT_T2,  16, "CT block (NIST)");
        checkBlock128(28, TAG_T2, 16, "Tag (NIST)");
        checkTlast(44, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 2: Empty plaintext (GMAC mode), default key/IV
        //         TX output: IV(12) + Tag(16) = 28 bytes
        // =================================================================
        testNum = 2;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Empty PT (GMAC), default key/IV", testNum);
        $display("  Expected Tag: 530f8afbc74536b9a963b4f1c4cb738b");
        $display("==========================================================");

        startPacket(16'd0);
        // No feedBlock — zero-length PT triggers finalize path
        waitForPktDone();

        checkPass("tx_payload_len == 28", tx_payload_len == 16'd28);
        checkPass("captureCount == 28",   captureCount == 28);
        checkIvBytes(IV_ZERO, "IV bytes (all zeros)");
        checkBlock128(12, TAG_T1, 16, "Tag (NIST GMAC)");
        checkTlast(28, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 3: 64-byte PT (4 blocks), Test Case 15 key/IV
        //         TX output: IV(12) + CT(64) + Tag(16) = 92 bytes
        // =================================================================
        testNum = 3;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: 64B PT (4 blocks), TC15 key/IV", testNum);
        $display("  Expected Tag: b094dac5d93471bdec1a502270e3cc6c");
        $display("==========================================================");

        // Load Test Case 15 key and IV via AXI-Stream
        sendKey(KEY_TC15);
        sendIv(IV_TC15);

        startPacket(16'd64);
        feedBlock(PT_TC15_0, 5'd0, 1'b0);  // Block 0: 16 bytes, not last
        feedBlock(PT_TC15_1, 5'd0, 1'b0);  // Block 1: 16 bytes, not last
        feedBlock(PT_TC15_2, 5'd0, 1'b0);  // Block 2: 16 bytes, not last
        feedBlock(PT_TC15_3, 5'd0, 1'b1);  // Block 3: 16 bytes, last
        waitForPktDone();

        checkPass("tx_payload_len == 92", tx_payload_len == 16'd92);
        checkPass("captureCount == 92",   captureCount == 92);
        checkIvBytes(IV_TC15, "IV bytes (cafebabe...)");
        checkBlock128(12, CT_TC15_0, 16, "CT block 0 (NIST)");
        checkBlock128(28, CT_TC15_1, 16, "CT block 1 (NIST)");
        checkBlock128(44, CT_TC15_2, 16, "CT block 2 (NIST)");
        checkBlock128(60, CT_TC15_3, 16, "CT block 3 (NIST)");
        checkBlock128(76, TAG_TC15,  16, "Tag (NIST TC15)");
        checkTlast(92, "tlast position");

        init();
        resetDut();

        // =================================================================
        // TEST 4: Back-to-back packets — verify IV auto-increment
        //         Packet 1: default IV (00...00) → CT/tag for IV=0
        //         Packet 2: auto-incremented IV (00...01)
        //         Only verify IV bytes in TX output
        // =================================================================
        testNum = 4;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Back-to-back packets, IV auto-increment", testNum);
        $display("==========================================================");

        // Packet 1: default IV
        startPacket(16'd16);
        feedBlock(PT_ZERO, 5'd0, 1'b1);
        waitForPktDone();

        checkPass("Pkt1 captureCount == 44", captureCount == 44);
        checkIvBytes(96'h000000000000000000000000, "Pkt1 IV (00..00)");
        $display("  Packet 1: IV byte[11] = %h (expect 00)", capturedBytes[11]);

        // Packet 2: IV should have auto-incremented to 00...01
        // captureCount is still running — Packet 2 bytes start at index 44
        begin : pkt2_check
            integer pkt2Start;
            pkt2Start = captureCount; // 44

            startPacket(16'd16);
            feedBlock(PT_ZERO, 5'd0, 1'b1);
            waitForPktDone();

            checkPass("Pkt2 byte count == 44", (captureCount - pkt2Start) == 44);
            // Check IV at offset pkt2Start
            checkBlock128(pkt2Start, {96'h000000000000000000000001, 32'd0}, 12, "Pkt2 IV (00..01)");
            $display("  Packet 2: IV byte[%0d] = %h (expect 01)", pkt2Start + 11, capturedBytes[pkt2Start + 11]);
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
