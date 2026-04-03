`timescale 1ns / 1ps
//
// module: tb_aes_gcm_256_axis_decrypt_top
// project: aes-gcm-256 for arty a7-100t
//
// system-level testbench for the decrypt pipeline with hold-off
// mechanism (stage d3). all dut-facing signals driven from clocked
// always blocks.
//
// test 1: decrypt nist tc14 (default key/iv)
//   44 bytes in -> 16 bytes pt out, auth ok
// test 2: decrypt nist tc15 (loaded key)
//   92 bytes in -> 64 bytes pt out, auth ok
// test 3: decrypt with corrupted tag
//   44 bytes in -> 0 bytes pt out (fifo flushed), auth_fail = 1
//
// dependencies: aes_gcm_256_axis_decrypt_top and all sub-modules
//

module tb_aes_gcm_256_axis_decrypt_top;

    reg clk;
    reg rst;

    // key axi-stream
    reg [7:0] key_axis_tdata;
    reg key_axis_tvalid;
    wire key_axis_tready;
    reg key_axis_tlast;

    // rx header
    reg rx_hdr_valid;
    reg [15:0] rx_payload_len;
    wire rx_hdr_ready;

    // rx payload (encrypted)
    reg [7:0] rx_payload_tdata;
    reg rx_payload_tvalid;
    wire rx_payload_tready;
    reg rx_payload_tlast;

    // tx header
    wire tx_hdr_valid;
    reg tx_hdr_ready;
    wire [15:0] tx_payload_len;

    // tx payload (plaintext)
    wire [7:0] tx_payload_tdata;
    wire tx_payload_tvalid;
    reg tx_payload_tready;
    wire tx_payload_tlast;

    // status
    wire decBusy;
    wire keyLoadErr;
    wire authFail;

    // test infrastructure
    integer passCount;
    integer failCount;
    integer totalTests;

    // tx capture
    reg [7:0] txBytes [0:255];
    reg txTlast [0:255];
    integer txCount;
    reg txDone;
    reg captureRst;

    // tx header capture
    reg hdrSeen;
    reg [15:0] hdrLen;

    // encrypted packet data
    reg [7:0] pktData [0:255];

    // expected plaintext
    reg [7:0] expected [0:255];

    // key data
    reg [7:0] keyData [0:31];

    // driver control
    reg rxGo;
    reg rxDone;
    reg [15:0] rxLen;

    reg keyGo;
    reg keyDone;

    reg ethGo;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    aes_gcm_256_axis_decrypt_top u_dut (
        .clk(clk),
        .rst(rst),
        .key_axis_tdata(key_axis_tdata),
        .key_axis_tvalid(key_axis_tvalid),
        .key_axis_tready(key_axis_tready),
        .key_axis_tlast(key_axis_tlast),
        .rx_hdr_valid(rx_hdr_valid),
        .rx_payload_len(rx_payload_len),
        .rx_hdr_ready(rx_hdr_ready),
        .rx_payload_tdata(rx_payload_tdata),
        .rx_payload_tvalid(rx_payload_tvalid),
        .rx_payload_tready(rx_payload_tready),
        .rx_payload_tlast(rx_payload_tlast),
        .tx_hdr_valid(tx_hdr_valid),
        .tx_hdr_ready(tx_hdr_ready),
        .tx_payload_len(tx_payload_len),
        .tx_payload_tdata(tx_payload_tdata),
        .tx_payload_tvalid(tx_payload_tvalid),
        .tx_payload_tready(tx_payload_tready),
        .tx_payload_tlast(tx_payload_tlast),
        .decBusy(decBusy),
        .keyLoadErr(keyLoadErr),
        .authFail(authFail)
    );

    // rx packet driver (clocked, nb, race-free)
    localparam RX_IDLE = 2'd0;
    localparam RX_HDR = 2'd1;
    localparam RX_STREAM = 2'd2;
    localparam RX_DONE = 2'd3;

    reg [1:0] rxState;
    reg [15:0] rxIdx;

    always @(posedge clk) begin
        if (rst) begin
            rx_hdr_valid <= 1'b0;
            rx_payload_len <= 16'd0;
            rx_payload_tdata <= 8'd0;
            rx_payload_tvalid <= 1'b0;
            rx_payload_tlast <= 1'b0;
            rxState <= RX_IDLE;
            rxIdx <= 16'd0;
            rxDone <= 1'b0;
        end
        else begin
            case (rxState)
                RX_IDLE: begin
                    rxDone <= 1'b0;
                    if (rxGo) begin
                        rx_hdr_valid <= 1'b1;
                        rx_payload_len <= rxLen;
                        rxState <= RX_HDR;
                    end
                end

                RX_HDR: begin
                    if (rx_hdr_ready) begin
                        rx_hdr_valid <= 1'b0;
                        rx_payload_tdata <= pktData[0];
                        rx_payload_tvalid <= 1'b1;
                        rx_payload_tlast <= (rxLen == 16'd1);
                        rxIdx <= 16'd0;
                        rxState <= RX_STREAM;
                    end
                end

                RX_STREAM: begin
                    if (rx_payload_tready) begin
                        if (rx_payload_tlast) begin
                            rx_payload_tvalid <= 1'b0;
                            rx_payload_tlast <= 1'b0;
                            rxDone <= 1'b1;
                            rxState <= RX_DONE;
                        end
                        else begin
                            rxIdx <= rxIdx + 16'd1;
                            rx_payload_tdata <= pktData[rxIdx + 16'd1];
                            rx_payload_tlast <= (rxIdx + 16'd1 == rxLen - 16'd1);
                        end
                    end
                end

                RX_DONE: begin
                    if (!rxGo) begin
                        rxDone <= 1'b0;
                        rxState <= RX_IDLE;
                    end
                end
            endcase
        end
    end

    // key loader driver (clocked, nb, race-free)
    reg [5:0] keyIdx;

    always @(posedge clk) begin
        if (rst) begin
            key_axis_tdata <= 8'd0;
            key_axis_tvalid <= 1'b0;
            key_axis_tlast <= 1'b0;
            keyIdx <= 6'd0;
            keyDone <= 1'b0;
        end
        else if (keyGo && !keyDone) begin
            if (!key_axis_tvalid) begin
                key_axis_tdata <= keyData[0];
                key_axis_tvalid <= 1'b1;
                key_axis_tlast <= 1'b0;
                keyIdx <= 6'd0;
            end
            else if (key_axis_tready) begin
                if (keyIdx == 6'd31) begin
                    key_axis_tvalid <= 1'b0;
                    key_axis_tlast <= 1'b0;
                    keyDone <= 1'b1;
                end
                else begin
                    keyIdx <= keyIdx + 6'd1;
                    key_axis_tdata <= keyData[keyIdx + 6'd1];
                    key_axis_tlast <= (keyIdx + 6'd1 == 6'd31);
                end
            end
        end
        else if (!keyGo) begin
            key_axis_tvalid <= 1'b0;
            key_axis_tlast <= 1'b0;
            keyDone <= 1'b0;
            keyIdx <= 6'd0;
        end
    end

    // tx ethernet stack model (clocked, nb, race-free)
    localparam ETH_IDLE = 2'd0;
    localparam ETH_WAIT = 2'd1;
    localparam ETH_ACK = 2'd2;
    localparam ETH_PAYLOAD = 2'd3;

    reg [1:0] ethState;

    always @(posedge clk) begin
        if (rst) begin
            tx_hdr_ready <= 1'b0;
            tx_payload_tready <= 1'b0;
            ethState <= ETH_IDLE;
        end
        else begin
            case (ethState)
                ETH_IDLE: begin
                    tx_hdr_ready <= 1'b0;
                    tx_payload_tready <= 1'b0;
                    if (ethGo) ethState <= ETH_WAIT;
                end

                ETH_WAIT: begin
                    if (tx_hdr_valid) begin
                        tx_hdr_ready <= 1'b1;
                        ethState <= ETH_ACK;
                    end
                end

                ETH_ACK: begin
                    tx_hdr_ready <= 1'b0;
                    tx_payload_tready <= 1'b1;
                    ethState <= ETH_PAYLOAD;
                end

                ETH_PAYLOAD: begin
                    if (!ethGo) ethState <= ETH_IDLE;
                end
            endcase
        end
    end

    // tx byte capture
    always @(posedge clk) begin
        if (rst || captureRst) begin
            txCount <= 0;
            txDone <= 1'b0;
        end
        else if (tx_payload_tvalid && tx_payload_tready) begin
            txBytes[txCount] <= tx_payload_tdata;
            txTlast[txCount] <= tx_payload_tlast;
            txCount <= txCount + 1;
            if (tx_payload_tlast) txDone <= 1'b1;
        end
    end

    // tx header capture
    always @(posedge clk) begin
        if (rst || captureRst) begin
            hdrSeen <= 1'b0;
            hdrLen <= 16'd0;
        end
        else if (tx_hdr_valid && tx_hdr_ready) begin
            hdrSeen <= 1'b1;
            hdrLen <= tx_payload_len;
        end
    end

    // helpers
    task fill_pkt_96;
        input integer base;
        input [95:0] val;
        integer b;
    begin
        for (b = 0; b < 12; b = b + 1)
            pktData[base + b] = val[(11-b)*8 +: 8];
    end
    endtask

    task fill_pkt_128;
        input integer base;
        input [127:0] val;
        integer b;
    begin
        for (b = 0; b < 16; b = b + 1)
            pktData[base + b] = val[(15-b)*8 +: 8];
    end
    endtask

    task fill_expected_128;
        input integer base;
        input [127:0] val;
        integer b;
    begin
        for (b = 0; b < 16; b = b + 1)
            expected[base + b] = val[(15-b)*8 +: 8];
    end
    endtask

    task fill_key;
        input [255:0] val;
        integer b;
    begin
        for (b = 0; b < 32; b = b + 1)
            keyData[b] = val[(31-b)*8 +: 8];
    end
    endtask

    // wait for pt output to complete (auth pass case)
    task wait_tx_done;
        integer timeout;
    begin
        timeout = 0;
        while (!txDone && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 200000) begin
            $display("  ERROR: tx output timeout");
            $stop;
        end
        // also wait for dec_busy to drop (tag verification)
        while (decBusy && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat (5) @(posedge clk);
        #1;
    end
    endtask

    // wait for decryption to finish (auth fail case: no tx output)
    task wait_dec_done;
        integer timeout;
    begin
        timeout = 0;
        // first wait for decryption to start
        while (!decBusy && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        // then wait for it to finish
        while (decBusy && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 200000) begin
            $display("  ERROR: dec_busy timeout");
            $stop;
        end
        repeat (20) @(posedge clk);
        #1;
    end
    endtask

    task check_bytes;
        input integer startIdx;
        input integer count;
        integer b;
    begin
        for (b = 0; b < count; b = b + 1) begin
            totalTests = totalTests + 1;
            if (txBytes[startIdx + b] == expected[startIdx + b]) begin
                passCount = passCount + 1;
            end
            else begin
                $display("    FAIL: byte[%0d] expected=%h got=%h",
                         startIdx + b, expected[startIdx + b],
                         txBytes[startIdx + b]);
                failCount = failCount + 1;
            end
        end
    end
    endtask

    integer i;

    initial begin
        $display("");
        $display("tb_aes_gcm_256_axis_decrypt_top, stage d3 system verification");
        $display("(with plaintext hold-off for nist sp 800-38d compliance)");
        $display("");

        passCount = 0;
        failCount = 0;
        totalTests = 0;

        rxGo = 1'b0;
        keyGo = 1'b0;
        ethGo = 1'b0;
        captureRst = 1'b0;

        rst = 1'b1;
        repeat (10) @(posedge clk);
        #1; rst = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        // test 1: decrypt nist tc14 (default key=0, iv from packet)
        $display("test 1: decrypt nist tc14 (default key)");

        fill_pkt_96(0, 96'h000000000000000000000000);
        fill_pkt_128(12, 128'hcea7403d4d606b6e074ec5d3baf39d18);
        fill_pkt_128(28, 128'hd0d1c8a799996bf0265b98b5d48ab919);
        rxLen = 16'd44;

        for (i = 0; i < 16; i = i + 1) expected[i] = 8'h00;

        captureRst = 1'b1;
        @(posedge clk); #1;
        captureRst = 1'b0;
        @(posedge clk); #1;

        rxGo = 1'b1;
        ethGo = 1'b1;

        wait_tx_done();

        rxGo = 1'b0;
        ethGo = 1'b0;
        repeat (5) @(posedge clk); #1;

        totalTests = totalTests + 1;
        if (hdrSeen && hdrLen == 16'd16) begin
            $display("    PASS: header len=%0d", hdrLen);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: header seen=%b len=%0d (expected 16)", hdrSeen, hdrLen);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (txCount == 16) begin
            $display("    PASS: %0d bytes output", txCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d bytes output (expected 16)", txCount);
            failCount = failCount + 1;
        end

        check_bytes(0, 16);

        totalTests = totalTests + 1;
        if (!authFail) begin
            $display("    PASS: auth ok");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: auth_fail asserted");
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (txCount >= 16 && txTlast[15]) begin
            $display("    PASS: tlast on byte 15");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tlast missing");
            failCount = failCount + 1;
        end

        $display("    test 1 complete");

        // test 2: decrypt nist tc15 (loaded key)
        $display("");
        $display("test 2: decrypt nist tc15 (loaded key)");

        fill_key(256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308);
        keyGo = 1'b1;
        while (!keyDone) @(posedge clk);
        repeat (10) @(posedge clk); #1;
        keyGo = 1'b0;
        repeat (5) @(posedge clk); #1;

        while (decBusy) @(posedge clk);
        repeat (5) @(posedge clk); #1;

        fill_pkt_96(0, 96'hcafebabefacedbaddecaf888);
        fill_pkt_128(12, 128'h522dc1f099567d07f47f37a32a84427d);
        fill_pkt_128(28, 128'h643a8cdcbfe5c0c97598a2bd2555d1aa);
        fill_pkt_128(44, 128'h8cb08e48590dbb3da7b08b1056828838);
        fill_pkt_128(60, 128'hc5f61e6393ba7a0abcc9f662898015ad);
        fill_pkt_128(76, 128'hb094dac5d93471bdec1a502270e3cc6c);
        rxLen = 16'd92;

        fill_expected_128(0, 128'hd9313225f88406e5a55909c5aff5269a);
        fill_expected_128(16, 128'h86a7a9531534f7da2e4c303d8a318a72);
        fill_expected_128(32, 128'h1c3c0c95956809532fcf0e2449a6b525);
        fill_expected_128(48, 128'hb16aedf5aa0de657ba637b391aafd255);

        captureRst = 1'b1;
        @(posedge clk); #1;
        captureRst = 1'b0;
        @(posedge clk); #1;

        rxGo = 1'b1;
        ethGo = 1'b1;

        wait_tx_done();

        rxGo = 1'b0;
        ethGo = 1'b0;
        repeat (5) @(posedge clk); #1;

        totalTests = totalTests + 1;
        if (hdrSeen && hdrLen == 16'd64) begin
            $display("    PASS: header len=%0d", hdrLen);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: header len=%0d (expected 64)", hdrLen);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (txCount == 64) begin
            $display("    PASS: %0d bytes output", txCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d bytes output (expected 64)", txCount);
            failCount = failCount + 1;
        end

        check_bytes(0, 64);

        totalTests = totalTests + 1;
        if (!authFail) begin
            $display("    PASS: auth ok");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: auth_fail asserted");
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (txCount >= 64 && txTlast[63]) begin
            $display("    PASS: tlast on byte 63");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tlast missing");
            failCount = failCount + 1;
        end

        $display("    test 2 complete");

        // test 3: decrypt with corrupted tag (auth fail)
        // with hold-off: zero pt bytes should reach tx interface
        $display("");
        $display("test 3: decrypt with corrupted tag (hold-off)");

        rst = 1'b1;
        repeat (5) @(posedge clk);
        #1; rst = 1'b0;
        repeat (5) @(posedge clk); #1;

        fill_pkt_96(0, 96'h000000000000000000000000);
        fill_pkt_128(12, 128'hcea7403d4d606b6e074ec5d3baf39d18);
        fill_pkt_128(28, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        rxLen = 16'd44;

        captureRst = 1'b1;
        @(posedge clk); #1;
        captureRst = 1'b0;
        @(posedge clk); #1;

        rxGo = 1'b1;
        ethGo = 1'b1;

        // wait for decryption to complete (no tx output expected)
        wait_dec_done();

        rxGo = 1'b0;
        ethGo = 1'b0;
        repeat (5) @(posedge clk); #1;

        totalTests = totalTests + 1;
        if (authFail) begin
            $display("    PASS: auth_fail asserted");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: auth_fail not asserted");
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (txCount == 0) begin
            $display("    PASS: zero pt bytes output (fifo flushed)");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d pt bytes leaked (expected 0)", txCount);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (!hdrSeen) begin
            $display("    PASS: no tx header sent");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tx header sent (should be suppressed)");
            failCount = failCount + 1;
        end

        $display("    test 3 complete");

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
