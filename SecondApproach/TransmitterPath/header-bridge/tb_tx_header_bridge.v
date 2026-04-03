`timescale 1ns / 1ps
//
// module: tb_tx_header_bridge
// project: aes-gcm-256 for arty a7-100t
//
// testbench for tx_header_bridge (stage 3).
//
// all dut-facing signals are driven from clocked always blocks
// using non-blocking assignments, eliminating all active-region
// races with the dut. the initial block only sets control flags
// between clock edges and checks results.
//
// test 1: 3-byte packet
// test 2: 44-byte packet
// test 3: delayed header ack (10 cycles)
// test 4: payload backpressure
// test 5: back-to-back packets
//
// dependencies: tx_header_bridge
//

module tb_tx_header_bridge;

    reg clk;
    reg rst;

    // dut signals (directly declared, no initial-block driving)
    wire s_axis_tready;
    wire tx_hdr_valid;
    wire [15:0] tx_payload_len;
    wire [7:0] tx_payload_tdata;
    wire tx_payload_tvalid;
    wire tx_payload_tlast;

    // driven by always blocks via nb
    reg [7:0] s_axis_tdata;
    reg s_axis_tvalid;
    reg s_axis_tlast;
    reg [15:0] payloadLen;
    reg tx_hdr_ready;
    reg tx_payload_tready;

    integer passCount;
    integer failCount;
    integer totalTests;

    reg [7:0] txBytes [0:255];
    integer txCount;
    reg txTlast [0:255];
    reg hdrSeen;
    reg [15:0] hdrLen;

    // stream data storage
    reg [7:0] streamData [0:255];

    // control flags (set by initial block between edges)
    reg streamGo;
    reg streamDone;
    reg [15:0] streamLen;
    reg [15:0] streamIdx;

    reg ethGo;
    reg ethDone;
    reg [31:0] ethDelay;
    reg ethBackpressure;
    reg captureRst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    tx_header_bridge u_dut (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .payloadLen(payloadLen),
        .tx_hdr_valid(tx_hdr_valid),
        .tx_hdr_ready(tx_hdr_ready),
        .tx_payload_len(tx_payload_len),
        .tx_payload_tdata(tx_payload_tdata),
        .tx_payload_tvalid(tx_payload_tvalid),
        .tx_payload_tready(tx_payload_tready),
        .tx_payload_tlast(tx_payload_tlast)
    );

    // stream driver (clocked, nb assignments, race-free)
    always @(posedge clk) begin
        if (rst) begin
            s_axis_tdata <= 8'd0;
            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
            streamIdx <= 16'd0;
            streamDone <= 1'b0;
        end
        else if (streamGo && !streamDone) begin
            if (!s_axis_tvalid) begin
                // start: present first byte
                s_axis_tdata <= streamData[0];
                s_axis_tvalid <= 1'b1;
                s_axis_tlast <= (streamLen == 16'd1);
                streamIdx <= 16'd0;
            end
            else if (s_axis_tready) begin
                if (s_axis_tlast) begin
                    // last byte accepted
                    s_axis_tvalid <= 1'b0;
                    s_axis_tlast <= 1'b0;
                    streamDone <= 1'b1;
                end
                else begin
                    // advance to next byte
                    s_axis_tdata <= streamData[streamIdx + 16'd1];
                    s_axis_tlast <= (streamIdx + 16'd1 == streamLen - 16'd1);
                    streamIdx <= streamIdx + 16'd1;
                end
            end
        end
        else if (!streamGo) begin
            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
            streamDone <= 1'b0;
            streamIdx <= 16'd0;
        end
    end

    // ethernet stack model (clocked, nb assignments, race-free)
    localparam ETH_IDLE = 3'd0;
    localparam ETH_WAIT = 3'd1;
    localparam ETH_DELAY = 3'd2;
    localparam ETH_ACK = 3'd3;
    localparam ETH_PAYLOAD = 3'd4;

    reg [2:0] ethState;
    reg [31:0] ethCnt;
    reg bpToggle;

    always @(posedge clk) begin
        if (rst) begin
            ethState <= ETH_IDLE;
            tx_hdr_ready <= 1'b0;
            tx_payload_tready <= 1'b0;
            ethCnt <= 32'd0;
            ethDone <= 1'b0;
            bpToggle <= 1'b0;
        end
        else begin
            case (ethState)
                ETH_IDLE: begin
                    tx_hdr_ready <= 1'b0;
                    tx_payload_tready <= 1'b0;
                    ethDone <= 1'b0;
                    ethCnt <= 32'd0;
                    bpToggle <= 1'b0;
                    if (ethGo)
                        ethState <= ETH_WAIT;
                end

                ETH_WAIT: begin
                    if (tx_hdr_valid) begin
                        if (ethDelay == 32'd0) begin
                            tx_hdr_ready <= 1'b1;
                            ethState <= ETH_ACK;
                        end
                        else begin
                            ethCnt <= 32'd1;
                            ethState <= ETH_DELAY;
                        end
                    end
                end

                ETH_DELAY: begin
                    if (ethCnt >= ethDelay) begin
                        tx_hdr_ready <= 1'b1;
                        ethState <= ETH_ACK;
                    end
                    else begin
                        ethCnt <= ethCnt + 32'd1;
                    end
                end

                ETH_ACK: begin
                    // deassert hdr_ready, enable payload
                    tx_hdr_ready <= 1'b0;
                    if (ethBackpressure)
                        tx_payload_tready <= 1'b0;
                    else
                        tx_payload_tready <= 1'b1;
                    ethDone <= 1'b1;
                    ethState <= ETH_PAYLOAD;
                end

                ETH_PAYLOAD: begin
                    if (ethBackpressure) begin
                        bpToggle <= ~bpToggle;
                        tx_payload_tready <= ~bpToggle;
                    end
                    if (!ethGo)
                        ethState <= ETH_IDLE;
                end

                default: ethState <= ETH_IDLE;
            endcase
        end
    end

    // capture tx payload bytes
    always @(posedge clk) begin
        if (rst || captureRst) begin
            txCount <= 0;
        end
        else if (tx_payload_tvalid && tx_payload_tready) begin
            txBytes[txCount] <= tx_payload_tdata;
            txTlast[txCount] <= tx_payload_tlast;
            txCount <= txCount + 1;
        end
    end

    // capture header handshake
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

    // helper: start a test (initial block, between edges)
    task start_test;
        input [15:0] pktLen;
        input [31:0] delay;
        input bp;
    begin
        captureRst = 1'b1;
        streamGo = 1'b0;
        ethGo = 1'b0;
        @(posedge clk); // let capture reset
        #1;
        captureRst = 1'b0;
        payloadLen = pktLen;
        streamLen = pktLen;
        ethDelay = delay;
        ethBackpressure = bp;
        // start both machines
        streamGo = 1'b1;
        ethGo = 1'b1;
    end
    endtask

    // helper: wait for stream to finish
    task wait_stream_done;
        integer timeout;
    begin
        timeout = 0;
        while (!streamDone && timeout < 50000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 50000) begin
            $display("  ERROR: stream timeout");
            $stop;
        end
        // let things settle
        repeat (5) @(posedge clk);
        #1;
        // stop machines
        streamGo = 1'b0;
        ethGo = 1'b0;
        repeat (3) @(posedge clk);
        #1;
    end
    endtask

    task check_tx_byte;
        input integer idx;
        input [7:0] expected;
    begin
        totalTests = totalTests + 1;
        if (txBytes[idx] == expected) begin
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: byte[%0d] expected=%h got=%h",
                     idx, expected, txBytes[idx]);
            failCount = failCount + 1;
        end
    end
    endtask

    task check_tx_tlast;
        input integer idx;
        input expectedTlast;
    begin
        totalTests = totalTests + 1;
        if (txTlast[idx] == expectedTlast) begin
            passCount = passCount + 1;
        end
        else begin
            $display("    FAIL: tlast[%0d] expected=%b got=%b",
                     idx, expectedTlast, txTlast[idx]);
            failCount = failCount + 1;
        end
    end
    endtask

    integer i;

    initial begin
        $display("");
        $display("tb_tx_header_bridge, stage 3 verification");
        $display("");

        passCount = 0;
        failCount = 0;
        totalTests = 0;

        // init control flags
        streamGo = 1'b0;
        ethGo = 1'b0;
        captureRst = 1'b0;
        ethBackpressure = 1'b0;
        ethDelay = 32'd0;
        streamLen = 16'd0;

        // reset
        rst = 1'b1;
        repeat (5) @(posedge clk);
        #1; rst = 1'b0;
        repeat (2) @(posedge clk);
        #1;

        // test 1: 3-byte packet
        $display("test 1: 3-byte packet");
        streamData[0] = 8'hAA; streamData[1] = 8'hBB; streamData[2] = 8'hCC;
        start_test(16'd3, 32'd0, 1'b0);
        wait_stream_done();

        totalTests = totalTests + 1;
        if (hdrSeen && hdrLen == 16'd3) begin
            $display("    PASS: header, len=%0d", hdrLen);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: header seen=%b len=%0d", hdrSeen, hdrLen);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (txCount == 3) begin
            $display("    PASS: %0d bytes", txCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d bytes (expected 3)", txCount);
            failCount = failCount + 1;
        end

        if (txCount >= 3) begin
            check_tx_byte(0, 8'hAA);
            check_tx_byte(1, 8'hBB);
            check_tx_byte(2, 8'hCC);
            check_tx_tlast(0, 1'b0);
            check_tx_tlast(1, 1'b0);
            check_tx_tlast(2, 1'b1);
        end

        $display("    test 1 complete");

        // test 2: 44-byte packet
        $display("");
        $display("test 2: 44-byte packet");
        for (i = 0; i < 44; i = i + 1) streamData[i] = i[7:0];
        start_test(16'd44, 32'd0, 1'b0);
        wait_stream_done();

        totalTests = totalTests + 1;
        if (hdrSeen && hdrLen == 16'd44) begin
            $display("    PASS: header, len=%0d", hdrLen);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: header len=%0d", hdrLen);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (txCount == 44) begin
            $display("    PASS: %0d bytes", txCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d bytes (expected 44)", txCount);
            failCount = failCount + 1;
        end

        for (i = 0; i < 44; i = i + 1) check_tx_byte(i, i[7:0]);
        check_tx_tlast(43, 1'b1);
        check_tx_tlast(0, 1'b0);

        $display("    test 2 complete");

        // test 3: delayed header ack (10 cycles)
        $display("");
        $display("test 3: delayed header ack (10 cycles)");
        streamData[0] = 8'hDE; streamData[1] = 8'hAD; streamData[2] = 8'hFF;
        start_test(16'd3, 32'd10, 1'b0);
        wait_stream_done();

        totalTests = totalTests + 1;
        if (hdrSeen && hdrLen == 16'd3) begin
            $display("    PASS: header after delay, len=%0d", hdrLen);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: header len=%0d", hdrLen);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (txCount == 3) begin
            $display("    PASS: %0d bytes", txCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d bytes (expected 3)", txCount);
            failCount = failCount + 1;
        end

        check_tx_byte(0, 8'hDE);
        check_tx_byte(1, 8'hAD);
        check_tx_byte(2, 8'hFF);
        check_tx_tlast(2, 1'b1);

        $display("    test 3 complete");

        // test 4: payload backpressure
        $display("");
        $display("test 4: payload backpressure");
        for (i = 0; i < 8; i = i + 1) streamData[i] = 8'hB0 + i[7:0];
        start_test(16'd8, 32'd0, 1'b1);
        wait_stream_done();

        totalTests = totalTests + 1;
        if (txCount == 8) begin
            $display("    PASS: %0d bytes with backpressure", txCount);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: %0d bytes (expected 8)", txCount);
            failCount = failCount + 1;
        end

        for (i = 0; i < 8; i = i + 1) check_tx_byte(i, 8'hB0 + i[7:0]);
        check_tx_tlast(7, 1'b1);
        check_tx_tlast(3, 1'b0);

        $display("    test 4 complete");

        // test 5: back-to-back packets
        $display("");
        $display("test 5: back-to-back packets");

        // packet 1
        streamData[0] = 8'h11; streamData[1] = 8'h22; streamData[2] = 8'h33;
        start_test(16'd3, 32'd0, 1'b0);
        wait_stream_done();

        totalTests = totalTests + 1;
        if (txCount == 3 && hdrLen == 16'd3) begin
            $display("    PASS: packet 1 (3 bytes, len=%0d)", hdrLen);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: pkt 1: %0d bytes, len=%0d", txCount, hdrLen);
            failCount = failCount + 1;
        end

        check_tx_byte(0, 8'h11);
        check_tx_byte(1, 8'h22);
        check_tx_byte(2, 8'h33);
        check_tx_tlast(2, 1'b1);

        // packet 2 (no reset between packets)
        streamData[0] = 8'hAA; streamData[1] = 8'hBB;
        start_test(16'd2, 32'd0, 1'b0);
        wait_stream_done();

        totalTests = totalTests + 1;
        if (txCount == 2 && hdrLen == 16'd2) begin
            $display("    PASS: packet 2 (2 bytes, len=%0d)", hdrLen);
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: pkt 2: %0d bytes, len=%0d", txCount, hdrLen);
            failCount = failCount + 1;
        end

        check_tx_byte(0, 8'hAA);
        check_tx_byte(1, 8'hBB);
        check_tx_tlast(1, 1'b1);

        $display("    test 5 complete");

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
