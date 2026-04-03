`timescale 1ns / 1ps
//
// module: tb_aes_gcm_256_axis_top
// project: aes-gcm-256 for arty a7-100t
//
// system-level testbench for the complete encrypt pipeline (stage 6).
// all dut-facing signals driven from clocked always blocks using
// non-blocking assignments (zero active-region races).
//
// test 1: nist tc14 - single block, default key/iv (zero)
//         16 bytes pt -> 44 bytes out (12 iv + 16 ct + 16 tag)
// test 2: nist tc15 - 4 blocks, loaded key/iv
//         64 bytes pt -> 92 bytes out
// test 3: iv auto-increment after tc15
//         16 bytes pt -> 44 bytes out, verify iv = ...f889
//
// dependencies: aes_gcm_256_axis_top and all sub-modules
//

module tb_aes_gcm_256_axis_top;

    reg clk;
    reg rst;

    // key axi-stream
    reg [7:0] key_axis_tdata;
    reg key_axis_tvalid;
    wire key_axis_tready;
    reg key_axis_tlast;

    // iv axi-stream
    reg [7:0] iv_axis_tdata;
    reg iv_axis_tvalid;
    wire iv_axis_tready;
    reg iv_axis_tlast;

    // rx header
    reg rx_hdr_valid;
    reg [15:0] rx_payload_len;
    wire rx_hdr_ready;

    // rx payload
    reg [7:0] rx_payload_tdata;
    reg rx_payload_tvalid;
    wire rx_payload_tready;
    reg rx_payload_tlast;

    // tx header
    wire tx_hdr_valid;
    reg tx_hdr_ready;
    wire [15:0] tx_payload_len;

    // tx payload
    wire [7:0] tx_payload_tdata;
    wire tx_payload_tvalid;
    reg tx_payload_tready;
    wire tx_payload_tlast;

    // status
    wire encBusy;
    wire keyLoadErr;
    wire ivLoadErr;

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

    // expected output
    reg [7:0] expected [0:255];
    integer expectedLen;

    // rx plaintext data
    reg [7:0] rxData [0:255];

    // key data
    reg [7:0] keyData [0:31];

    // iv data
    reg [7:0] ivData [0:11];

    // driver control flags
    reg rxGo;
    reg rxDone;
    reg [15:0] rxLen;

    reg keyGo;
    reg keyDone;

    reg ivGo;
    reg ivDone;

    reg ethGo;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    aes_gcm_256_axis_top u_dut (
        .clk(clk),
        .rst(rst),
        .key_axis_tdata(key_axis_tdata),
        .key_axis_tvalid(key_axis_tvalid),
        .key_axis_tready(key_axis_tready),
        .key_axis_tlast(key_axis_tlast),
        .iv_axis_tdata(iv_axis_tdata),
        .iv_axis_tvalid(iv_axis_tvalid),
        .iv_axis_tready(iv_axis_tready),
        .iv_axis_tlast(iv_axis_tlast),
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
        .encBusy(encBusy),
        .keyLoadErr(keyLoadErr),
        .ivLoadErr(ivLoadErr)
    );

    // rx plaintext driver (clocked, nb, race-free)
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
                        rx_payload_tdata <= rxData[0];
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
                            rx_payload_tdata <= rxData[rxIdx + 16'd1];
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

    // iv loader driver (clocked, nb, race-free)
    reg [3:0] ivIdx;

    always @(posedge clk) begin
        if (rst) begin
            iv_axis_tdata <= 8'd0;
            iv_axis_tvalid <= 1'b0;
            iv_axis_tlast <= 1'b0;
            ivIdx <= 4'd0;
            ivDone <= 1'b0;
        end
        else if (ivGo && !ivDone) begin
            if (!iv_axis_tvalid) begin
                iv_axis_tdata <= ivData[0];
                iv_axis_tvalid <= 1'b1;
                iv_axis_tlast <= 1'b0;
                ivIdx <= 4'd0;
            end
            else if (iv_axis_tready) begin
                if (ivIdx == 4'd11) begin
                    iv_axis_tvalid <= 1'b0;
                    iv_axis_tlast <= 1'b0;
                    ivDone <= 1'b1;
                end
                else begin
                    ivIdx <= ivIdx + 4'd1;
                    iv_axis_tdata <= ivData[ivIdx + 4'd1];
                    iv_axis_tlast <= (ivIdx + 4'd1 == 4'd11);
                end
            end
        end
        else if (!ivGo) begin
            iv_axis_tvalid <= 1'b0;
            iv_axis_tlast <= 1'b0;
            ivDone <= 1'b0;
            ivIdx <= 4'd0;
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

    // helper: fill 16 bytes from 128-bit value at base index (msb-first)
    task fill_128;
        input integer base;
        input [127:0] val;
        integer b;
    begin
        for (b = 0; b < 16; b = b + 1)
            expected[base + b] = val[(15-b)*8 +: 8];
    end
    endtask

    // helper: fill 12 bytes from 96-bit value at base index (msb-first)
    task fill_96;
        input integer base;
        input [95:0] val;
        integer b;
    begin
        for (b = 0; b < 12; b = b + 1)
            expected[base + b] = val[(11-b)*8 +: 8];
    end
    endtask

    // helper: fill rx plaintext from 128-bit value at base index (msb-first)
    task fill_pt;
        input integer base;
        input [127:0] val;
        integer b;
    begin
        for (b = 0; b < 16; b = b + 1)
            rxData[base + b] = val[(15-b)*8 +: 8];
    end
    endtask

    // helper: fill 32-byte key from 256-bit value (msb-first)
    task fill_key;
        input [255:0] val;
        integer b;
    begin
        for (b = 0; b < 32; b = b + 1)
            keyData[b] = val[(31-b)*8 +: 8];
    end
    endtask

    // helper: fill 12-byte iv from 96-bit value (msb-first)
    task fill_iv;
        input [95:0] val;
        integer b;
    begin
        for (b = 0; b < 12; b = b + 1)
            ivData[b] = val[(11-b)*8 +: 8];
    end
    endtask

    // helper: wait for tx done with timeout
    task wait_tx_done;
        integer timeout;
    begin
        timeout = 0;
        while (!txDone && timeout < 100000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 100000) begin
            $display("  ERROR: tx output timeout after %0d cycles", timeout);
            $stop;
        end
        repeat (10) @(posedge clk);
        #1;
    end
    endtask

    // helper: check a range of output bytes
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
        $display("tb_aes_gcm_256_axis_top, stage 6 system verification");
        $display("");

        passCount = 0;
        failCount = 0;
        totalTests = 0;

        // init control flags
        rxGo = 1'b0;
        keyGo = 1'b0;
        ivGo = 1'b0;
        ethGo = 1'b0;
        captureRst = 1'b0;

        // reset
        rst = 1'b1;
        repeat (10) @(posedge clk);
        #1; rst = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        // test 1: nist tc14 - single block, default key/iv (zero)
        //   pt  = 16 bytes of 0x00
        //   key = 256'h0 (default)
        //   iv  = 96'h0 (default)
        //   expected ct  = cea7403d4d606b6e074ec5d3baf39d18
        //   expected tag = d0d1c8a799996bf0265b98b5d48ab919
        //   output: iv(12b) + ct(16b) + tag(16b) = 44 bytes
        $display("test 1: nist tc14 - single block, default key/iv");

        // fill plaintext (16 zero bytes)
        for (i = 0; i < 16; i = i + 1) rxData[i] = 8'h00;
        rxLen = 16'd16;

        // fill expected output
        fill_96(0, 96'h000000000000000000000000);
        fill_128(12, 128'hcea7403d4d606b6e074ec5d3baf39d18);
        fill_128(28, 128'hd0d1c8a799996bf0265b98b5d48ab919);
        expectedLen = 44;

        // reset capture
        captureRst = 1'b1;
        @(posedge clk); #1;
        captureRst = 1'b0;
        @(posedge clk); #1;

        // start rx driver and ethernet model
        rxGo = 1'b1;
        ethGo = 1'b1;

        wait_tx_done();

        // stop drivers
        rxGo = 1'b0;
        ethGo = 1'b0;
        repeat (5) @(posedge clk); #1;

        // check header
        totalTests = totalTests + 1;
        if (hdrSeen && hdrLen == 16'd44) begin
            $display("    PASS: header len=%0d", hdrLen);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: header seen=%b len=%0d (expected 44)", hdrSeen, hdrLen);
            failCount = failCount + 1;
        end

        // check byte count
        totalTests = totalTests + 1;
        if (txCount == 44) begin
            $display("    PASS: %0d bytes output", txCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d bytes output (expected 44)", txCount);
            failCount = failCount + 1;
        end

        // check iv bytes
        check_bytes(0, 12);

        // check ct bytes
        check_bytes(12, 16);

        // check tag bytes
        check_bytes(28, 16);

        // check tlast on last byte
        totalTests = totalTests + 1;
        if (txCount >= 44 && txTlast[43]) begin
            $display("    PASS: tlast on byte 43");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tlast not on byte 43");
            failCount = failCount + 1;
        end

        $display("    test 1 complete");

        // test 2: nist tc15 - 4 blocks, loaded key and iv
        //   key = feffe9928665731c6d6a8f9467308308
        //         feffe9928665731c6d6a8f9467308308
        //   iv  = cafebabefacedbaddecaf888
        //   pt  = d9313225f88406e5a55909c5aff5269a
        //         86a7a9531534f7da2e4c303d8a318a72
        //         1c3c0c95956809532fcf0e2449a6b525
        //         b16aedf5aa0de657ba637b391aafd255
        //   expected ct  = 522dc1f0...898015ad (64 bytes)
        //   expected tag = b094dac5d93471bdec1a502270e3cc6c
        //   output: iv(12b) + ct(64b) + tag(16b) = 92 bytes
        $display("");
        $display("test 2: nist tc15 - 4 blocks, loaded key/iv");

        // load key
        fill_key(256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308);
        keyGo = 1'b1;
        while (!keyDone) @(posedge clk);
        repeat (10) @(posedge clk); #1;
        keyGo = 1'b0;
        repeat (5) @(posedge clk); #1;

        // load iv
        fill_iv(96'hcafebabefacedbaddecaf888);
        ivGo = 1'b1;
        while (!ivDone) @(posedge clk);
        repeat (10) @(posedge clk); #1;
        ivGo = 1'b0;
        repeat (5) @(posedge clk); #1;

        // wait for idle
        while (encBusy) @(posedge clk);
        repeat (5) @(posedge clk); #1;

        // fill plaintext (64 bytes, 4 blocks)
        fill_pt(0, 128'hd9313225f88406e5a55909c5aff5269a);
        fill_pt(16, 128'h86a7a9531534f7da2e4c303d8a318a72);
        fill_pt(32, 128'h1c3c0c95956809532fcf0e2449a6b525);
        fill_pt(48, 128'hb16aedf5aa0de657ba637b391aafd255);
        rxLen = 16'd64;

        // fill expected output
        fill_96(0, 96'hcafebabefacedbaddecaf888);
        fill_128(12, 128'h522dc1f099567d07f47f37a32a84427d);
        fill_128(28, 128'h643a8cdcbfe5c0c97598a2bd2555d1aa);
        fill_128(44, 128'h8cb08e48590dbb3da7b08b1056828838);
        fill_128(60, 128'hc5f61e6393ba7a0abcc9f662898015ad);
        fill_128(76, 128'hb094dac5d93471bdec1a502270e3cc6c);
        expectedLen = 92;

        // reset capture
        captureRst = 1'b1;
        @(posedge clk); #1;
        captureRst = 1'b0;
        @(posedge clk); #1;

        // start
        rxGo = 1'b1;
        ethGo = 1'b1;

        wait_tx_done();

        rxGo = 1'b0;
        ethGo = 1'b0;
        repeat (5) @(posedge clk); #1;

        // check header
        totalTests = totalTests + 1;
        if (hdrSeen && hdrLen == 16'd92) begin
            $display("    PASS: header len=%0d", hdrLen);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: header seen=%b len=%0d (expected 92)", hdrSeen, hdrLen);
            failCount = failCount + 1;
        end

        // check byte count
        totalTests = totalTests + 1;
        if (txCount == 92) begin
            $display("    PASS: %0d bytes output", txCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d bytes output (expected 92)", txCount);
            failCount = failCount + 1;
        end

        // check all 92 bytes
        check_bytes(0, 92);

        // check tlast
        totalTests = totalTests + 1;
        if (txCount >= 92 && txTlast[91]) begin
            $display("    PASS: tlast on byte 91");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tlast not on byte 91");
            failCount = failCount + 1;
        end

        $display("    test 2 complete");

        // test 3: iv auto-increment after tc15
        //   no key/iv load (reuses tc15 key, iv auto-incremented)
        //   after tc15: iv should be cafebabefacedbaddecaf889
        //   pt  = 16 bytes of 0x00
        //   output: iv(12b) + ct(16b) + tag(16b) = 44 bytes
        //   verify: iv bytes, total byte count, header length
        //   ct/tag not verified (no reference vectors for this iv)
        $display("");
        $display("test 3: iv auto-increment verification");

        // wait for idle
        while (encBusy) @(posedge clk);
        repeat (5) @(posedge clk); #1;

        // fill plaintext (16 zero bytes)
        for (i = 0; i < 16; i = i + 1) rxData[i] = 8'h00;
        rxLen = 16'd16;

        // expected iv bytes only (auto-incremented from tc15)
        fill_96(0, 96'hcafebabefacedbaddecaf889);

        // reset capture
        captureRst = 1'b1;
        @(posedge clk); #1;
        captureRst = 1'b0;
        @(posedge clk); #1;

        // start
        rxGo = 1'b1;
        ethGo = 1'b1;

        wait_tx_done();

        rxGo = 1'b0;
        ethGo = 1'b0;
        repeat (5) @(posedge clk); #1;

        // check header
        totalTests = totalTests + 1;
        if (hdrSeen && hdrLen == 16'd44) begin
            $display("    PASS: header len=%0d", hdrLen);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: header len=%0d (expected 44)", hdrLen);
            failCount = failCount + 1;
        end

        // check byte count
        totalTests = totalTests + 1;
        if (txCount == 44) begin
            $display("    PASS: %0d bytes output", txCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d bytes output (expected 44)", txCount);
            failCount = failCount + 1;
        end

        // check iv bytes (auto-incremented)
        check_bytes(0, 12);

        // check tlast
        totalTests = totalTests + 1;
        if (txCount >= 44 && txTlast[43]) begin
            $display("    PASS: tlast on byte 43");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: tlast not on byte 43");
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
