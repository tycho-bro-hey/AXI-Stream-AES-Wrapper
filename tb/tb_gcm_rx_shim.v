`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Module: tb_gcm_rx_shim
//
// Project: AES-GCM-256 for Arty A7-100T
//
// Description: Testbench for gcm_rx_shim. Verifies byte-reversal from AXI
//              little-endian to GCM big-endian, tkeep-to-byteCount
//              conversion for full and partial blocks, and signal
//              pass-through for tvalid, tlast, tready.
//
// Dependencies: gcm_rx_shim
//
//////////////////////////////////////////////////////////////////////////////////

module tb_gcm_rx_shim;

    // =========================================================================
    // Clock (used only for test sequencing, DUT is combinational)
    // =========================================================================
    reg clk;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // DUT Signals
    // =========================================================================
    reg [127:0]  s_tdata;
    reg [15:0]   s_tkeep;
    reg          s_tvalid;
    reg          s_tlast;
    wire         s_tready;

    wire [127:0] m_tdata;
    wire         m_tvalid;
    wire         m_tlast;
    reg          m_tready;
    wire [4:0]   m_byteCount;

    // =========================================================================
    // Test Tracking
    // =========================================================================
    integer testNum;
    integer passCount;
    integer failCount;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    gcm_rx_shim u_dut (
        .s_tdata     (s_tdata),
        .s_tkeep     (s_tkeep),
        .s_tvalid    (s_tvalid),
        .s_tlast     (s_tlast),
        .s_tready    (s_tready),
        .m_tdata     (m_tdata),
        .m_tvalid    (m_tvalid),
        .m_tlast     (m_tlast),
        .m_tready    (m_tready),
        .m_byteCount (m_byteCount)
    );

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    task init;
    begin
        s_tdata  = 128'd0;
        s_tkeep  = 16'd0;
        s_tvalid = 1'b0;
        s_tlast  = 1'b0;
        m_tready = 1'b1;
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

    // Build an AXI-ordered 128-bit word from a byte sequence.
    // Byte 0 (first received) goes in [7:0], byte 1 in [15:8], etc.
    // This is how the width converter packs bytes.
    function [127:0] axiPack;
        input [7:0] b0, b1, b2, b3, b4, b5, b6, b7;
        input [7:0] b8, b9, b10, b11, b12, b13, b14, b15;
    begin
        axiPack = {b15, b14, b13, b12, b11, b10, b9, b8,
                   b7,  b6,  b5,  b4,  b3,  b2,  b1, b0};
    end
    endfunction

    // Build a GCM-ordered (big-endian) 128-bit word from the same bytes.
    // Byte 0 (first received) goes in [127:120], byte 1 in [119:112], etc.
    function [127:0] gcmPack;
        input [7:0] b0, b1, b2, b3, b4, b5, b6, b7;
        input [7:0] b8, b9, b10, b11, b12, b13, b14, b15;
    begin
        gcmPack = {b0, b1, b2, b3, b4, b5, b6, b7,
                   b8, b9, b10, b11, b12, b13, b14, b15};
    end
    endfunction

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        testNum   = 0;
        passCount = 0;
        failCount = 0;

        init();
        #10;

        // =================================================================
        // TEST 1: Full block (16 bytes), sequential byte pattern
        //         Byte stream: 00 01 02 03 ... 0F
        //         AXI packing: byte 0 in [7:0] → 0x0F0E0D0C_0B0A0908_07060504_03020100
        //         GCM expected: byte 0 in [127:120] → 0x00010203_04050607_08090A0B_0C0D0E0F
        // =================================================================
        testNum = 1;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Full 16-byte block, sequential pattern", testNum);
        $display("==========================================================");

        s_tdata  = axiPack(8'h00, 8'h01, 8'h02, 8'h03,
                           8'h04, 8'h05, 8'h06, 8'h07,
                           8'h08, 8'h09, 8'h0A, 8'h0B,
                           8'h0C, 8'h0D, 8'h0E, 8'h0F);
        s_tkeep  = 16'hFFFF;
        s_tvalid = 1'b1;
        s_tlast  = 1'b0;
        #1;

        checkPass("Data byte-reversed correctly",
                  m_tdata == 128'h000102030405060708090A0B0C0D0E0F);
        checkPass("byteCount == 0 (encodes 16)",
                  m_byteCount == 5'd0);
        checkPass("tvalid passed through",  m_tvalid == 1'b1);
        checkPass("tlast passed through",   m_tlast  == 1'b0);

        $display("  AXI in:  %h", s_tdata);
        $display("  GCM out: %h", m_tdata);

        // =================================================================
        // TEST 2: Full block with NIST Test Case 15 plaintext block 0
        //         PT bytes: d9 31 32 25 f8 84 06 e5 a5 59 09 c5 af f5 26 9a
        // =================================================================
        testNum = 2;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Full block, NIST TC15 plaintext block 0", testNum);
        $display("==========================================================");

        s_tdata  = axiPack(8'hd9, 8'h31, 8'h32, 8'h25,
                           8'hf8, 8'h84, 8'h06, 8'he5,
                           8'ha5, 8'h59, 8'h09, 8'hc5,
                           8'haf, 8'hf5, 8'h26, 8'h9a);
        s_tkeep  = 16'hFFFF;
        s_tvalid = 1'b1;
        s_tlast  = 1'b0;
        #1;

        checkPass("TC15 block 0 reversed correctly",
                  m_tdata == 128'hd9313225f88406e5a55909c5aff5269a);
        checkPass("byteCount == 0 (encodes 16)",
                  m_byteCount == 5'd0);

        $display("  AXI in:  %h", s_tdata);
        $display("  GCM out: %h", m_tdata);

        // =================================================================
        // TEST 3: Partial block — 4 bytes valid (tkeep = 16'h000F)
        //         Bytes: AA BB CC DD (valid), rest don't care
        // =================================================================
        testNum = 3;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Partial block, 4 bytes valid", testNum);
        $display("==========================================================");

        s_tdata  = axiPack(8'hAA, 8'hBB, 8'hCC, 8'hDD,
                           8'h00, 8'h00, 8'h00, 8'h00,
                           8'h00, 8'h00, 8'h00, 8'h00,
                           8'h00, 8'h00, 8'h00, 8'h00);
        s_tkeep  = 16'h000F;
        s_tvalid = 1'b1;
        s_tlast  = 1'b1;
        #1;

        // First 4 bytes should be in top 32 bits of GCM output
        checkPass("4B partial: top 4 bytes correct",
                  m_tdata[127:96] == 32'hAABBCCDD);
        checkPass("byteCount == 4",
                  m_byteCount == 5'd4);
        checkPass("tlast passed through",
                  m_tlast == 1'b1);

        $display("  GCM out: %h", m_tdata);
        $display("  byteCount: %0d", m_byteCount);

        // =================================================================
        // TEST 4: Partial block — 12 bytes valid (tkeep = 16'h0FFF)
        //         TC16 last block: b16aedf5aa0de657ba637b39 (12 bytes)
        // =================================================================
        testNum = 4;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Partial block, 12 bytes valid (TC16 data)", testNum);
        $display("==========================================================");

        s_tdata  = axiPack(8'hb1, 8'h6a, 8'hed, 8'hf5,
                           8'haa, 8'h0d, 8'he6, 8'h57,
                           8'hba, 8'h63, 8'h7b, 8'h39,
                           8'h00, 8'h00, 8'h00, 8'h00);
        s_tkeep  = 16'h0FFF;
        s_tvalid = 1'b1;
        s_tlast  = 1'b1;
        #1;

        checkPass("12B partial: top 12 bytes correct",
                  m_tdata[127:32] == 96'hb16aedf5aa0de657ba637b39);
        checkPass("byteCount == 12",
                  m_byteCount == 5'd12);

        $display("  GCM out: %h", m_tdata);

        // =================================================================
        // TEST 5: Partial block — 1 byte valid (tkeep = 16'h0001)
        // =================================================================
        testNum = 5;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: Partial block, 1 byte valid", testNum);
        $display("==========================================================");

        s_tdata  = axiPack(8'h42, 8'h00, 8'h00, 8'h00,
                           8'h00, 8'h00, 8'h00, 8'h00,
                           8'h00, 8'h00, 8'h00, 8'h00,
                           8'h00, 8'h00, 8'h00, 8'h00);
        s_tkeep  = 16'h0001;
        s_tvalid = 1'b1;
        s_tlast  = 1'b1;
        #1;

        checkPass("1B partial: top byte correct",
                  m_tdata[127:120] == 8'h42);
        checkPass("byteCount == 1",
                  m_byteCount == 5'd1);

        // =================================================================
        // TEST 6: tready pass-through
        // =================================================================
        testNum = 6;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: tready pass-through", testNum);
        $display("==========================================================");

        m_tready = 1'b1;
        #1;
        checkPass("s_tready high when m_tready high",
                  s_tready == 1'b1);

        m_tready = 1'b0;
        #1;
        checkPass("s_tready low when m_tready low",
                  s_tready == 1'b0);

        m_tready = 1'b1;

        // =================================================================
        // TEST 7: tvalid/tlast pass-through combinations
        // =================================================================
        testNum = 7;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: tvalid/tlast combinations", testNum);
        $display("==========================================================");

        s_tvalid = 1'b0; s_tlast = 1'b0; #1;
        checkPass("valid=0 last=0 → m_tvalid=0 m_tlast=0",
                  m_tvalid == 1'b0 && m_tlast == 1'b0);

        s_tvalid = 1'b1; s_tlast = 1'b0; #1;
        checkPass("valid=1 last=0 → m_tvalid=1 m_tlast=0",
                  m_tvalid == 1'b1 && m_tlast == 1'b0);

        s_tvalid = 1'b1; s_tlast = 1'b1; #1;
        checkPass("valid=1 last=1 → m_tvalid=1 m_tlast=1",
                  m_tvalid == 1'b1 && m_tlast == 1'b1);

        s_tvalid = 1'b0; s_tlast = 1'b1; #1;
        checkPass("valid=0 last=1 → m_tvalid=0 m_tlast=1",
                  m_tvalid == 1'b0 && m_tlast == 1'b1);

        // =================================================================
        // TEST 8: All tkeep widths (exhaustive byteCount check)
        // =================================================================
        testNum = 8;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: All tkeep widths (1-16 bytes)", testNum);
        $display("==========================================================");

        s_tvalid = 1'b1;
        s_tlast  = 1'b0;
        s_tdata  = 128'd0;

        begin : tkeepSweep
            integer n;
            reg [4:0] expectedBc;
            reg allPass;

            allPass = 1'b1;
            for (n = 1; n <= 16; n = n + 1) begin
                s_tkeep = (n == 16) ? 16'hFFFF : ((16'h1 << n) - 16'h1);
                expectedBc = (n == 16) ? 5'd0 : n[4:0];
                #1;
                if (m_byteCount !== expectedBc) begin
                    $display("  FAIL: tkeep=%h expected byteCount=%0d got=%0d",
                             s_tkeep, expectedBc, m_byteCount);
                    allPass = 1'b0;
                end
            end
            if (allPass) begin
                $display("  PASS: All 16 tkeep widths produce correct byteCount");
                passCount = passCount + 1;
            end
            else begin
                failCount = failCount + 1;
            end
        end

        // =================================================================
        // TEST 9: Identity check — round-trip byte order
        //         Feed all-FF in AXI order, expect all-FF in GCM order
        // =================================================================
        testNum = 9;
        $display("");
        $display("==========================================================");
        $display("TEST %0d: All-FF identity (byte reversal is self-inverse)", testNum);
        $display("==========================================================");

        s_tdata  = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        s_tkeep  = 16'hFFFF;
        #1;

        checkPass("All-FF unchanged after reversal",
                  m_tdata == 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

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
