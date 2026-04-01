`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: tb_cavp_wrapper
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: NIST CAVP vector verification through the full AXI-Stream
//              encrypt pipeline (gcm_axi_top). For each vector, feeds
//              plaintext bytes and verifies the TX byte stream matches
//              the expected IV + ciphertext + tag byte-for-byte.
//
//              Vectors are drawn from the same CAVP source files used
//              by tb_aes_gcm_256_encrypt_cavp.v, filtered to AADlen=0
//              (no AAD) which is the wrapper's initial configuration.
//
//              Covers: McGrew-Viega TC13-TC15, CAVP Sections 1/6/11/16
//                PTlen: 0, 104(13B), 128(16B), 256(32B), 512(64B)
//
// Dependencies: gcm_axi_top and all encrypt submodules.
//
//////////////////////////////////////////////////////////////////////////////////

module tb_cavp_wrapper;

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

    reg [7:0]   iv_axis_tdata;
    reg         iv_axis_tvalid;
    wire        iv_axis_tready;
    reg         iv_axis_tlast;

    reg         rx_hdr_valid;
    reg [15:0]  rx_payload_len;
    wire        rx_hdr_ready;

    reg [7:0]   rx_payload_tdata;
    reg         rx_payload_tvalid;
    wire        rx_payload_tready;
    reg         rx_payload_tlast;

    wire        tx_hdr_valid;
    wire [15:0] tx_payload_len;
    wire [7:0]  tx_payload_tdata;
    wire        tx_payload_tvalid;
    wire        tx_payload_tlast;

    wire        encBusy;
    wire        encDone;

    // =========================================================================
    // TX Byte Capture
    // =========================================================================
    reg [7:0]   capBytes [0:1599];
    integer     capCount;

    always @(posedge clk) begin
        if (rst)
            capCount <= 0;
        else if (tx_payload_tvalid) begin
            capBytes[capCount] <= tx_payload_tdata;
            capCount <= capCount + 1;
        end
    end

    // =========================================================================
    // Transfer detect
    // =========================================================================
    reg rxXfer;
    always @(posedge clk) begin
        if (rst) rxXfer <= 1'b0;
        else     rxXfer <= rx_payload_tvalid && rx_payload_tready;
    end

    // =========================================================================
    // Test Tracking
    // =========================================================================
    integer testNum;
    integer passCount;
    integer failCount;

    // =========================================================================
    // DUT
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
        .tx_hdr_ready     (1'b1),
        .tx_payload_tdata (tx_payload_tdata),
        .tx_payload_tvalid(tx_payload_tvalid),
        .tx_payload_tready(1'b1),
        .tx_payload_tlast (tx_payload_tlast),
        .keyError         (),
        .ivError          (),
        .encBusy          (encBusy),
        .encDone          (encDone)
    );

    // =========================================================================
    // Plaintext Buffer
    // =========================================================================
    reg [7:0] ptBytes [0:255];
    integer   ptCount;

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

    task loadPtBlock;
        input [127:0] block;
        input integer numBytes;
        integer i;
    begin
        for (i = 0; i < numBytes; i = i + 1) begin
            ptBytes[ptCount] = block[127 - i*8 -: 8];
            ptCount = ptCount + 1;
        end
    end
    endtask

    task feedPacket;
        input [15:0] ptLen;
        integer i;
    begin
        rx_payload_len = ptLen;
        rx_hdr_valid   = 1'b1;
        @(posedge clk);
        #1;
        rx_hdr_valid   = 1'b0;

        for (i = 0; i < ptLen; i = i + 1) begin
            rx_payload_tdata  = ptBytes[i];
            rx_payload_tvalid = 1'b1;
            rx_payload_tlast  = (i == ptLen - 1) ? 1'b1 : 1'b0;
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

    task waitDone;
        integer timeout;
    begin
        timeout = 0;
        while (encBusy && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 200000)
            $display("  ERROR: Timeout");
        repeat (5) @(posedge clk);
    end
    endtask

    // Verify IV bytes (first 12 of captured output)
    task checkIv;
        input [95:0] expected;
        input [399:0] label;
        integer i;
        reg [7:0] expByte;
        reg allMatch;
    begin
        allMatch = 1'b1;
        for (i = 0; i < 12; i = i + 1) begin
            expByte = expected[95 - i*8 -: 8];
            if (capBytes[i] !== expByte)
                allMatch = 1'b0;
        end
        if (allMatch) begin
            $display("  PASS: %0s", label);
            passCount = passCount + 1;
        end
        else begin
            $display("  FAIL: %0s", label);
            for (i = 0; i < 12; i = i + 1) begin
                expByte = expected[95 - i*8 -: 8];
                if (capBytes[i] !== expByte)
                    $display("    iv[%0d] exp=%h got=%h", i, expByte, capBytes[i]);
            end
            failCount = failCount + 1;
        end
    end
    endtask

    // Verify CT bytes (starting at offset 12)
    task checkCt;
        input integer startIdx;
        input [127:0] expected;
        input integer numBytes;
        input [399:0] label;
        integer i;
        reg [7:0] expByte;
        reg allMatch;
    begin
        allMatch = 1'b1;
        for (i = 0; i < numBytes; i = i + 1) begin
            expByte = expected[127 - i*8 -: 8];
            if (capBytes[startIdx + i] !== expByte)
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
                if (capBytes[startIdx + i] !== expByte)
                    $display("    [%0d] exp=%h got=%h", startIdx + i, expByte, capBytes[startIdx + i]);
            end
            failCount = failCount + 1;
        end
    end
    endtask

    // Verify Tag bytes (16 bytes at given offset)
    task checkTag;
        input integer startIdx;
        input [127:0] expected;
        input [399:0] label;
    begin
        checkCt(startIdx, expected, 16, label);
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

    // Combined vector test: load key+IV, feed PT, verify IV+CT+Tag in TX stream
    // For zero-PT tests, call with ptLen=0 and skip CT check.
    // tagOffset = 12 + ptLen (where tag starts in captured bytes)

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        testNum   = 0;
        passCount = 0;
        failCount = 0;

        $display("");
        $display("##### NIST CAVP Vectors — AXI-Stream Encrypt Wrapper #####");
        $display("");

        init();
        resetDut();

        // =================================================================
        // SECTION A: McGrew-Viega Test Vectors (TC13-TC15)
        // =================================================================
        $display("==========================================================");
        $display("SECTION A: McGrew-Viega Test Vectors");
        $display("==========================================================");

        // ----- TC13: Empty PT, zero key/IV -----
        testNum = 1;
        $display("");
        $display("TC13: Empty PT, zero key (GMAC)");

        sendKey(256'h0);
        sendIv(96'h0);
        ptCount = 0;
        feedPacket(16'd0);
        waitDone();

        checkPass("capCount == 28", capCount == 28);
        checkIv(96'h0, "IV");
        checkTag(12, 128'h530f8afbc74536b9a963b4f1c4cb738b, "Tag");

        init(); resetDut();

        // ----- TC14: 16B zero PT, zero key/IV -----
        testNum = 2;
        $display("");
        $display("TC14: 16B zero PT, zero key");

        sendKey(256'h0);
        sendIv(96'h0);
        ptCount = 0;
        loadPtBlock(128'h0, 16);
        feedPacket(16'd16);
        waitDone();

        checkPass("capCount == 44", capCount == 44);
        checkIv(96'h0, "IV");
        checkCt(12, 128'hcea7403d4d606b6e074ec5d3baf39d18, 16, "CT");
        checkTag(28, 128'hd0d1c8a799996bf0265b98b5d48ab919, "Tag");

        init(); resetDut();

        // ----- TC15: 64B PT, feffe992... key -----
        testNum = 3;
        $display("");
        $display("TC15: 64B PT, TC15 key");

        sendKey(256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308);
        sendIv(96'hcafebabefacedbaddecaf888);
        ptCount = 0;
        loadPtBlock(128'hd9313225f88406e5a55909c5aff5269a, 16);
        loadPtBlock(128'h86a7a9531534f7da2e4c303d8a318a72, 16);
        loadPtBlock(128'h1c3c0c95956809532fcf0e2449a6b525, 16);
        loadPtBlock(128'hb16aedf5aa0de657ba637b391aafd255, 16);
        feedPacket(16'd64);
        waitDone();

        checkPass("capCount == 92", capCount == 92);
        checkIv(96'hcafebabefacedbaddecaf888, "IV");
        checkCt(12, 128'h522dc1f099567d07f47f37a32a84427d, 16, "CT[0]");
        checkCt(28, 128'h643a8cdcbfe5c0c97598a2bd2555d1aa, 16, "CT[1]");
        checkCt(44, 128'h8cb08e48590dbb3da7b08b1056828838, 16, "CT[2]");
        checkCt(60, 128'hc5f61e6393ba7a0abcc9f662898015ad, 16, "CT[3]");
        checkTag(76, 128'hb094dac5d93471bdec1a502270e3cc6c, "Tag");

        init(); resetDut();

        // =================================================================
        // SECTION B: CAVP Section 1 — PTlen=0, AADlen=0 (GMAC)
        // =================================================================
        $display("");
        $display("==========================================================");
        $display("SECTION B: CAVP PTlen=0, AADlen=0");
        $display("==========================================================");

        // ----- CAVP S1-TC1 -----
        testNum = 4;
        $display("");
        $display("S1-TC1: GMAC");

        sendKey(256'hb52c505a37d78eda5dd34f20c22540ea1b58963cf8e5bf8ffa85f9f2492505b4);
        sendIv(96'h516c33929df5a3284ff463d7);
        ptCount = 0;
        feedPacket(16'd0);
        waitDone();

        checkPass("capCount == 28", capCount == 28);
        checkIv(96'h516c33929df5a3284ff463d7, "IV");
        checkTag(12, 128'hbdc1ac884d332457a1d2664f168c76f0, "Tag");

        init(); resetDut();

        // ----- CAVP S1-TC2 -----
        testNum = 5;
        $display("");
        $display("S1-TC2: GMAC");

        sendKey(256'h5fe0861cdc2690ce69b3658c7f26f8458eec1c9243c5ba0845305d897e96ca0f);
        sendIv(96'h770ac1a5a3d476d5d96944a1);
        ptCount = 0;
        feedPacket(16'd0);
        waitDone();

        checkPass("capCount == 28", capCount == 28);
        checkIv(96'h770ac1a5a3d476d5d96944a1, "IV");
        checkTag(12, 128'h196d691e1047093ca4b3d2ef4baba216, "Tag");

        init(); resetDut();

        // ----- CAVP S1-TC3 -----
        testNum = 6;
        $display("");
        $display("S1-TC3: GMAC");

        sendKey(256'h7620b79b17b21b06d97019aa70e1ca105e1c03d2a0cf8b20b5a0ce5c3903e548);
        sendIv(96'h60f56eb7a4b38d4f03395511);
        ptCount = 0;
        feedPacket(16'd0);
        waitDone();

        checkPass("capCount == 28", capCount == 28);
        checkIv(96'h60f56eb7a4b38d4f03395511, "IV");
        checkTag(12, 128'hf570c38202d94564bab39f75617bc87a, "Tag");

        init(); resetDut();

        // =================================================================
        // SECTION C: CAVP Section 6 — PTlen=128 (16B), AADlen=0
        // =================================================================
        $display("");
        $display("==========================================================");
        $display("SECTION C: CAVP PTlen=128, AADlen=0");
        $display("==========================================================");

        // ----- CAVP S6-TC9 -----
        testNum = 7;
        $display("");
        $display("S6-TC9: 16B PT");

        sendKey(256'h56690798978c154ff250ba78e463765f2f0ce69709a4551bd8cb3addeda087b6);
        sendIv(96'hcf37c286c18ad4ea3d0ba6a0);
        ptCount = 0;
        loadPtBlock(128'h2d328124a8d58d56d0775eed93de1a88, 16);
        feedPacket(16'd16);
        waitDone();

        checkPass("capCount == 44", capCount == 44);
        checkIv(96'hcf37c286c18ad4ea3d0ba6a0, "IV");
        checkCt(12, 128'h3b0a0267f6ecde3a78b30903ebd4ca6e, 16, "CT");
        checkTag(28, 128'h1fd2006409fc636379f3d4067eca0988, "Tag");

        init(); resetDut();

        // ----- CAVP S6-TC10 -----
        testNum = 8;
        $display("");
        $display("S6-TC10: 16B PT");

        sendKey(256'h8a02a33bdf87e7845d7a8ae3c8727e704f4fd08c1f2083282d8cb3a5d3cedee9);
        sendIv(96'h599f5896851c968ed808323b);
        ptCount = 0;
        loadPtBlock(128'h4ade8b32d56723fb8f65ce40825e27c9, 16);
        feedPacket(16'd16);
        waitDone();

        checkPass("capCount == 44", capCount == 44);
        checkIv(96'h599f5896851c968ed808323b, "IV");
        checkCt(12, 128'hcb9133796b9075657840421a46022b63, 16, "CT");
        checkTag(28, 128'ha79e453c6fad8a5a4c2a8e87821c7f88, "Tag");

        init(); resetDut();

        // ----- CAVP S6-TC11 -----
        testNum = 9;
        $display("");
        $display("S6-TC11: 16B PT");

        sendKey(256'h23aaa78a5915b14f00cf285f38ee275a2db97cb4ab14d1aac8b9a73ff1e66467);
        sendIv(96'h4a675ec9be1aab9632dd9f59);
        ptCount = 0;
        loadPtBlock(128'h56659c06a00a2e8ed1ac60572eee3ef7, 16);
        feedPacket(16'd16);
        waitDone();

        checkPass("capCount == 44", capCount == 44);
        checkIv(96'h4a675ec9be1aab9632dd9f59, "IV");
        checkCt(12, 128'he6c01723bfbfa398d9c9aac8c683bb12, 16, "CT");
        checkTag(28, 128'h4a2f78a9975d4a1b5f503a4a2cb71553, "Tag");

        init(); resetDut();

        // =================================================================
        // SECTION D: CAVP Section 11 — PTlen=104 (13B), AADlen=0
        // =================================================================
        $display("");
        $display("==========================================================");
        $display("SECTION D: CAVP PTlen=104 (13B partial), AADlen=0");
        $display("==========================================================");

        // ----- CAVP S11-TC1 -----
        testNum = 10;
        $display("");
        $display("S11-TC1: 13B PT (partial block)");

        sendKey(256'h82c4f12eeec3b2d3d157b0f992d292b237478d2cecc1d5f161389b97f999057a);
        sendIv(96'h7b40b20f5f397177990ef2d1);
        ptCount = 0;
        loadPtBlock(128'h982a296ee1cd7086afad976945000000, 13);
        feedPacket(16'd13);
        waitDone();

        // TX: IV(12) + CT(13) + Tag(16) = 41 bytes
        checkPass("capCount == 41", capCount == 41);
        checkIv(96'h7b40b20f5f397177990ef2d1, "IV");
        checkCt(12, 128'hec8e05a0471d6b43a59ca5335f000000, 13, "CT (13B)");
        checkTag(25, 128'h113ddeafc62373cac2f5951bb9165249, "Tag");

        init(); resetDut();

        // ----- CAVP S11-TC2 -----
        testNum = 11;
        $display("");
        $display("S11-TC2: 13B PT (partial block)");

        sendKey(256'hdb4340af2f835a6c6d7ea0ca9d83ca81ba02c29b7410f221cb6071114e393240);
        sendIv(96'h40e438357dd80a85cac3349e);
        ptCount = 0;
        loadPtBlock(128'h8ddb3397bd42853193cb0f80c9000000, 13);
        feedPacket(16'd13);
        waitDone();

        checkPass("capCount == 41", capCount == 41);
        checkIv(96'h40e438357dd80a85cac3349e, "IV");
        checkCt(12, 128'hb694118c85c41abf69e229cb0f000000, 13, "CT (13B)");
        checkTag(25, 128'hc07f1b8aafbd152f697eb67f2a85fe45, "Tag");

        init(); resetDut();

        // =================================================================
        // SECTION E: CAVP Section 16 — PTlen=256 (32B), AADlen=0
        // =================================================================
        $display("");
        $display("==========================================================");
        $display("SECTION E: CAVP PTlen=256 (32B), AADlen=0");
        $display("==========================================================");

        // ----- CAVP S16-TC8 -----
        testNum = 12;
        $display("");
        $display("S16-TC8: 32B PT (2 blocks)");

        sendKey(256'ha2ef619054164073c06a191b6431c4c0bc2690508dcb6e88a8396a1391291483);
        sendIv(96'h16c6d20224b556a8ad7e6007);
        ptCount = 0;
        loadPtBlock(128'h949a9f85966f4a317cf592e70c5fb59c, 16);
        loadPtBlock(128'h4cacbd08140c8169ba10b2e8791ae57b, 16);
        feedPacket(16'd32);
        waitDone();

        // TX: IV(12) + CT(32) + Tag(16) = 60 bytes
        checkPass("capCount == 60", capCount == 60);
        checkIv(96'h16c6d20224b556a8ad7e6007, "IV");
        checkCt(12, 128'hb5054a392e5f0672e7922ac243b93b43, 16, "CT[0]");
        checkCt(28, 128'h2e8c58274ff4a6d3aa8cb654e494e2f2, 16, "CT[1]");
        checkTag(44, 128'hcf2bbdb740369c140e93e251e6f5c875, "Tag");

        init(); resetDut();

        // ----- CAVP S16-TC9 -----
        testNum = 13;
        $display("");
        $display("S16-TC9: 32B PT (2 blocks)");

        sendKey(256'h76f386bc8b93831903901b5eda1f7795af8adcecffa8aef004b754a353c62d8e);
        sendIv(96'h96618b357c41f41a2c48343b);
        ptCount = 0;
        loadPtBlock(128'h36108edad5de3bfb0258df7709fbbb1a, 16);
        loadPtBlock(128'h157c36321f8de72eb8320e9aa1794933, 16);
        feedPacket(16'd32);
        waitDone();

        checkPass("capCount == 60", capCount == 60);
        checkIv(96'h96618b357c41f41a2c48343b, "IV");
        checkCt(12, 128'hb2093a4fc8ff0daefc1c786b6b04324a, 16, "CT[0]");
        checkCt(28, 128'h80d77941a88e0a7a6ef0a62beb8ed283, 16, "CT[1]");
        checkTag(44, 128'he55ea0456af9cdff2cad4eebbf00da1b, "Tag");

        init(); resetDut();

        // =================================================================
        // Summary
        // =================================================================
        $display("");
        $display("==========================================================");
        $display("CAVP WRAPPER SUMMARY: %0d passed, %0d failed out of %0d",
                 passCount, failCount, passCount + failCount);
        $display("==========================================================");
        $display("  Vectors tested: 13 (3 McGrew-Viega + 10 CAVP)");
        $display("  PTlen coverage: 0B, 13B, 16B, 32B, 64B");
        $display("  All vectors AADlen=0, IVlen=96, Taglen=128");

        if (failCount == 0)
            $display("ALL CAVP TESTS PASSED");
        else
            $display("SOME CAVP TESTS FAILED");

        $finish;
    end

endmodule
