`timescale 1ns / 1ps
//
// module: tb_key_iv_loaders
// project: aes-gcm-256 for arty a7-100t
//
// combined testbench for key_loader and iv_loader (stage 4).
// uses clocked always block for axi-stream driving (no races).
//
// key_loader tests:
//   1. power-up default key
//   2. load 32-byte key with correct tlast
//   3. commit waits for enc-busy to drop
//   4. early tlast (error)
//   5. late tlast / missing tlast (error)
//
// iv_loader tests:
//   6. power-up default iv
//   7. load 12-byte iv with correct tlast
//   8. auto-increment (3 pkt-done pulses)
//   9. load new seed then auto-increment
//   10. early tlast (error)
//
// dependencies: key_loader, iv_loader
//

module tb_key_iv_loaders;

    reg clk;
    reg rst;

    // key loader signals
    reg [7:0] key_tdata;
    reg key_tvalid;
    wire key_tready;
    reg key_tlast;
    wire [255:0] keyReg;
    reg encBusy;
    wire keyLoadErr;

    // iv loader signals
    reg [7:0] iv_tdata;
    reg iv_tvalid;
    wire iv_tready;
    reg iv_tlast;
    wire [95:0] ivReg;
    reg pktDone;
    wire ivLoadErr;

    integer passCount;
    integer failCount;
    integer totalTests;

    // stream driver control
    reg [7:0] loadData [0:63];
    reg [6:0] loadLen;
    reg [6:0] loadTlastIdx; // which byte gets tlast (-1 = none)
    reg loadGoKey;
    reg loadGoIv;
    reg loadDoneKey;
    reg loadDoneIv;
    reg [6:0] loadIdx;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    key_loader u_key (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(key_tdata),
        .s_axis_tvalid(key_tvalid),
        .s_axis_tready(key_tready),
        .s_axis_tlast(key_tlast),
        .keyReg(keyReg),
        .encBusy(encBusy),
        .loadErr(keyLoadErr)
    );

    iv_loader u_iv (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(iv_tdata),
        .s_axis_tvalid(iv_tvalid),
        .s_axis_tready(iv_tready),
        .s_axis_tlast(iv_tlast),
        .ivReg(ivReg),
        .encBusy(encBusy),
        .pktDone(pktDone),
        .loadErr(ivLoadErr)
    );

    // key stream driver (clocked, nb, race-free)
    always @(posedge clk) begin
        if (rst) begin
            key_tdata <= 8'd0;
            key_tvalid <= 1'b0;
            key_tlast <= 1'b0;
            loadDoneKey <= 1'b0;
            loadIdx <= 7'd0;
        end
        else if (loadGoKey && !loadDoneKey) begin
            if (!key_tvalid) begin
                // start: present first byte
                key_tdata <= loadData[0];
                key_tvalid <= 1'b1;
                key_tlast <= (loadTlastIdx == 7'd0);
                loadIdx <= 7'd0;
            end
            else if (key_tready) begin
                if (loadIdx == loadLen - 7'd1) begin
                    // all bytes sent
                    key_tvalid <= 1'b0;
                    key_tlast <= 1'b0;
                    loadDoneKey <= 1'b1;
                end
                else begin
                    key_tdata <= loadData[loadIdx + 7'd1];
                    key_tlast <= (loadIdx + 7'd1 == loadTlastIdx);
                    loadIdx <= loadIdx + 7'd1;
                end
            end
        end
        else if (!loadGoKey) begin
            key_tvalid <= 1'b0;
            key_tlast <= 1'b0;
            loadDoneKey <= 1'b0;
            loadIdx <= 7'd0;
        end
    end

    // iv stream driver (reuses data array via separate go flag)
    reg [6:0] ivLoadIdx;

    always @(posedge clk) begin
        if (rst) begin
            iv_tdata <= 8'd0;
            iv_tvalid <= 1'b0;
            iv_tlast <= 1'b0;
            loadDoneIv <= 1'b0;
            ivLoadIdx <= 7'd0;
        end
        else if (loadGoIv && !loadDoneIv) begin
            if (!iv_tvalid) begin
                iv_tdata <= loadData[0];
                iv_tvalid <= 1'b1;
                iv_tlast <= (loadTlastIdx == 7'd0);
                ivLoadIdx <= 7'd0;
            end
            else if (iv_tready) begin
                if (ivLoadIdx == loadLen - 7'd1) begin
                    iv_tvalid <= 1'b0;
                    iv_tlast <= 1'b0;
                    loadDoneIv <= 1'b1;
                end
                else begin
                    iv_tdata <= loadData[ivLoadIdx + 7'd1];
                    iv_tlast <= (ivLoadIdx + 7'd1 == loadTlastIdx);
                    ivLoadIdx <= ivLoadIdx + 7'd1;
                end
            end
        end
        else if (!loadGoIv) begin
            iv_tvalid <= 1'b0;
            iv_tlast <= 1'b0;
            loadDoneIv <= 1'b0;
            ivLoadIdx <= 7'd0;
        end
    end

    task do_reset;
    begin
        rst = 1'b1;
        loadGoKey = 1'b0;
        loadGoIv = 1'b0;
        encBusy = 1'b0;
        pktDone = 1'b0;
        repeat (5) @(posedge clk);
        #1; rst = 1'b0;
        repeat (2) @(posedge clk);
        #1;
    end
    endtask

    // wait for key load to complete
    task wait_key_done;
        integer timeout;
    begin
        timeout = 0;
        while (!loadDoneKey && timeout < 1000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        // let commit settle
        repeat (5) @(posedge clk);
        #1;
        loadGoKey = 1'b0;
        repeat (2) @(posedge clk); #1;
    end
    endtask

    // wait for iv load to complete
    task wait_iv_done;
        integer timeout;
    begin
        timeout = 0;
        while (!loadDoneIv && timeout < 1000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat (5) @(posedge clk);
        #1;
        loadGoIv = 1'b0;
        repeat (2) @(posedge clk); #1;
    end
    endtask

    integer i;

    initial begin
        $display("");
        $display("tb_key_iv_loaders, stage 4 verification");
        $display("");

        passCount = 0;
        failCount = 0;
        totalTests = 0;

        do_reset();

        // test 1: key power-up default
        $display("test 1: key power-up default");
        totalTests = totalTests + 1;
        if (keyReg == 256'h0) begin
            $display("    PASS: default key = 0");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: default key = %h", keyReg);
            failCount = failCount + 1;
        end

        // test 2: load 32-byte key (nist tc15 key)
        $display("");
        $display("test 2: load 32-byte key");
        // key = feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308
        for (i = 0; i < 16; i = i + 1) begin
            loadData[i] = 8'hfe >> ((i % 2 == 0) ? 0 : 0); // will set explicitly
        end
        loadData[0]  = 8'hfe; loadData[1]  = 8'hff; loadData[2]  = 8'he9; loadData[3]  = 8'h92;
        loadData[4]  = 8'h86; loadData[5]  = 8'h65; loadData[6]  = 8'h73; loadData[7]  = 8'h1c;
        loadData[8]  = 8'h6d; loadData[9]  = 8'h6a; loadData[10] = 8'h8f; loadData[11] = 8'h94;
        loadData[12] = 8'h67; loadData[13] = 8'h30; loadData[14] = 8'h83; loadData[15] = 8'h08;
        loadData[16] = 8'hfe; loadData[17] = 8'hff; loadData[18] = 8'he9; loadData[19] = 8'h92;
        loadData[20] = 8'h86; loadData[21] = 8'h65; loadData[22] = 8'h73; loadData[23] = 8'h1c;
        loadData[24] = 8'h6d; loadData[25] = 8'h6a; loadData[26] = 8'h8f; loadData[27] = 8'h94;
        loadData[28] = 8'h67; loadData[29] = 8'h30; loadData[30] = 8'h83; loadData[31] = 8'h08;
        loadLen = 7'd32;
        loadTlastIdx = 7'd31;
        loadGoKey = 1'b1;

        wait_key_done();

        totalTests = totalTests + 1;
        if (keyReg == 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308) begin
            $display("    PASS: key loaded correctly");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: key = %h", keyReg);
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        if (!keyLoadErr) begin
            $display("    PASS: no error");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: unexpected error");
            failCount = failCount + 1;
        end

        // test 3: commit waits for enc-busy
        $display("");
        $display("test 3: key commit waits for enc-busy");
        // load all zeros key while enc-busy is high
        for (i = 0; i < 32; i = i + 1) loadData[i] = 8'h00;
        loadLen = 7'd32;
        loadTlastIdx = 7'd31;
        encBusy = 1'b1;
        loadGoKey = 1'b1;

        // wait for all bytes to be sent but key should not commit yet
        while (!loadDoneKey) @(posedge clk);
        repeat (5) @(posedge clk); #1;

        totalTests = totalTests + 1;
        // key should still be the tc15 key (not committed)
        if (keyReg == 256'hfeffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308) begin
            $display("    PASS: key held during encBusy");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: key committed early = %h", keyReg);
            failCount = failCount + 1;
        end

        // release enc-busy
        encBusy = 1'b0;
        repeat (5) @(posedge clk); #1;

        totalTests = totalTests + 1;
        if (keyReg == 256'h0) begin
            $display("    PASS: key committed after encBusy dropped");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: key = %h", keyReg);
            failCount = failCount + 1;
        end

        loadGoKey = 1'b0;
        repeat (3) @(posedge clk); #1;

        // test 4: early tlast on key (error)
        $display("");
        $display("test 4: key early tlast (error)");
        for (i = 0; i < 16; i = i + 1) loadData[i] = 8'hAA;
        loadLen = 7'd16; // only 16 bytes
        loadTlastIdx = 7'd15; // tlast on byte 15 (too early)
        loadGoKey = 1'b1;

        wait_key_done();

        totalTests = totalTests + 1;
        if (keyLoadErr) begin
            $display("    PASS: error flagged for early tlast");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: no error for early tlast");
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        // key should remain unchanged (still 0 from test 3)
        if (keyReg == 256'h0) begin
            $display("    PASS: key unchanged after error");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: key changed to %h", keyReg);
            failCount = failCount + 1;
        end

        // test 5: late tlast on key (32 bytes without tlast = error)
        $display("");
        $display("test 5: key late tlast (error)");
        for (i = 0; i < 32; i = i + 1) loadData[i] = 8'hBB;
        loadLen = 7'd32;
        loadTlastIdx = 7'd127; // no tlast (index out of range)
        loadGoKey = 1'b1;

        wait_key_done();

        totalTests = totalTests + 1;
        if (keyLoadErr) begin
            $display("    PASS: error flagged for missing tlast");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: no error for missing tlast");
            failCount = failCount + 1;
        end

        do_reset();

        // test 6: iv power-up default
        $display("");
        $display("test 6: iv power-up default");
        totalTests = totalTests + 1;
        if (ivReg == 96'h0) begin
            $display("    PASS: default iv = 0");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: default iv = %h", ivReg);
            failCount = failCount + 1;
        end

        // test 7: load 12-byte iv (nist tc15 iv)
        $display("");
        $display("test 7: load 12-byte iv");
        // iv = cafebabefacedbaddecaf888
        loadData[0]  = 8'hca; loadData[1]  = 8'hfe; loadData[2]  = 8'hba; loadData[3]  = 8'hbe;
        loadData[4]  = 8'hfa; loadData[5]  = 8'hce; loadData[6]  = 8'hdb; loadData[7]  = 8'had;
        loadData[8]  = 8'hde; loadData[9]  = 8'hca; loadData[10] = 8'hf8; loadData[11] = 8'h88;
        loadLen = 7'd12;
        loadTlastIdx = 7'd11;
        loadGoIv = 1'b1;

        wait_iv_done();

        totalTests = totalTests + 1;
        if (ivReg == 96'hcafebabefacedbaddecaf888) begin
            $display("    PASS: iv loaded correctly");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: iv = %h", ivReg);
            failCount = failCount + 1;
        end

        // test 8: auto-increment (3 pkt-done pulses)
        $display("");
        $display("test 8: iv auto-increment");
        // current iv = cafebabefacedbaddecaf888
        // lower 64 bits = facedbaddecaf888
        // after 1 increment: facedbaddecaf889
        pktDone = 1'b1;
        @(posedge clk); #1;
        pktDone = 1'b0;
        @(posedge clk); #1;

        totalTests = totalTests + 1;
        if (ivReg == 96'hcafebabefacedbaddecaf889) begin
            $display("    PASS: iv after 1 increment");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: iv = %h (expected cafebabefacedbaddecaf889)", ivReg);
            failCount = failCount + 1;
        end

        // 2 more increments
        pktDone = 1'b1;
        @(posedge clk); #1;
        pktDone = 1'b0;
        @(posedge clk); #1;

        pktDone = 1'b1;
        @(posedge clk); #1;
        pktDone = 1'b0;
        @(posedge clk); #1;

        totalTests = totalTests + 1;
        if (ivReg == 96'hcafebabefacedbaddecaf88b) begin
            $display("    PASS: iv after 3 total increments");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: iv = %h (expected cafebabefacedbaddecaf88b)", ivReg);
            failCount = failCount + 1;
        end

        // verify upper 32 bits unchanged
        totalTests = totalTests + 1;
        if (ivReg[95:64] == 32'hcafebabe) begin
            $display("    PASS: upper 32 bits unchanged");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: upper 32 bits = %h", ivReg[95:64]);
            failCount = failCount + 1;
        end

        // test 9: load new seed then auto-increment
        $display("");
        $display("test 9: load new iv seed then auto-increment");
        // load iv = 000000010000000000000000
        for (i = 0; i < 12; i = i + 1) loadData[i] = 8'h00;
        loadData[3] = 8'h01; // upper 32 bits = 00000001
        loadLen = 7'd12;
        loadTlastIdx = 7'd11;
        loadGoIv = 1'b1;

        wait_iv_done();

        totalTests = totalTests + 1;
        if (ivReg == 96'h000000010000000000000000) begin
            $display("    PASS: new seed loaded");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: iv = %h", ivReg);
            failCount = failCount + 1;
        end

        // increment once
        pktDone = 1'b1;
        @(posedge clk); #1;
        pktDone = 1'b0;
        @(posedge clk); #1;

        totalTests = totalTests + 1;
        if (ivReg == 96'h000000010000000000000001) begin
            $display("    PASS: increment from new seed");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: iv = %h", ivReg);
            failCount = failCount + 1;
        end

        // test 10: iv early tlast (error)
        $display("");
        $display("test 10: iv early tlast (error)");
        for (i = 0; i < 6; i = i + 1) loadData[i] = 8'hFF;
        loadLen = 7'd6;
        loadTlastIdx = 7'd5; // tlast on byte 5 (too early)
        loadGoIv = 1'b1;

        wait_iv_done();

        totalTests = totalTests + 1;
        if (ivLoadErr) begin
            $display("    PASS: error flagged for early tlast");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: no error for early tlast");
            failCount = failCount + 1;
        end

        totalTests = totalTests + 1;
        // iv should remain unchanged
        if (ivReg == 96'h000000010000000000000001) begin
            $display("    PASS: iv unchanged after error");
            passCount = passCount + 1;
        end else begin
            $display("    FAIL: iv changed to %h", ivReg);
            failCount = failCount + 1;
        end

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
