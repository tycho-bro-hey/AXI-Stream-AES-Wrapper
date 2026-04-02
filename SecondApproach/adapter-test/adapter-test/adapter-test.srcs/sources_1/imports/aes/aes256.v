`timescale 1ns / 1ps
/****************************************************************************
* CLASSIFICATION: Unclassified Controlled Information (OUO/ECI)
*
*           Official Use Only / Export Controlled Information
*
* May be exempt from public release under the Freedom of Information Act
* (5 U.S.C. 552) exemption number and category: Exemption 3 - Export
* Controlled Information.
*
*       Department of Energy review required before public release
*
* EXPORT CONTROLLED INFORMATION
* Treat this material per Department of State (DOS) International Traffic
* and Arms Regulations (ITAR), 22 CFR 120-130. Information contained in this
* document is also subject to controls defined by the Department of Defense
* Directive 5230.25
*
****************************************************************************
* Copyright National Technology and Authoring Solutions of Sandia, LLC. 
* Under the terms of Contract DE-NA0003525, there is a non-exclusive license 
* for use of this work by or on behalf of the U.S. Government. Export of this 
* program may require a license from the United States Government.
*
****************************************************************************/

//////////////////////////////////////////////////////////////////////////////////
// Author: Jarom B. Christensen
// Email: jbchri@sandia.gov
// 
// Project: Enano AES
// Module: aes256KeySchedule
// Created: 2022-05-31
// Target Device: ZYNQ-7010
// 
// Description: Full implementation of AES 256. Begins computation when plaintext
//  is changed, raises done signal when finished.
// 
// Dependencies: aesKeySchedule, aesRound
// 
//////////////////////////////////////////////////////////////////////////////////

module aes256 (ciphertext, plaintext, key, clk, in_valid, out_valid);
    output [127:0] ciphertext;
    output out_valid;
    input [127:0] plaintext;
    input [255:0] key;
    input clk, in_valid;

    reg [127:0] inData;
    wire [127:0] roundKey, subData;
    wire [255:0] currentKey;
    reg [255:0] prevKey;
    wire kschout_valid, roundout_valid, roundClk, rst;
    reg [3:0] round;
    wire [31:0] toSub, subWord;
    reg sbox_rst;
    reg in_valid_d = 1'b0;

    localparam [3:0] ROUND_MAX = 4'd14;

    assign out_valid = round == ROUND_MAX;

    // block to compute a single round of AES
    aesRound ROUND (
        .inData(inData),
        .outData(ciphertext), 
        .roundKey(roundKey),
        .last(round == ROUND_MAX)
    );
    
    // key schedule computation
    aes256KeySchedule KSCH (
        .roundKey(roundKey),
        .key(currentKey),
        .prevKey(prevKey), 
        .round(round)
    );
    
    always @(posedge clk)
        in_valid_d <= in_valid;

    always @(posedge clk) begin
        sbox_rst <= 0;
        if (in_valid == 1 && in_valid_d != 1) begin
            inData <= plaintext ^ key[255:128];
            prevKey <= key;
            round <= 4'h1;
            sbox_rst <= 1;
        end
        else if (~out_valid) begin
                inData <= ciphertext;
                prevKey <= currentKey;
                round <= round + 1;
                sbox_rst <= 1;
        end
    end
endmodule

module aes256_tb();
    wire [127:0] ciphertext;
    wire out_valid;
    reg clk, rst;
    
    // instance module
    aes256 AES (.ciphertext(ciphertext),
        .plaintext(128'h00112233445566778899aabbccddeeff),
        .key(256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f),
        .clk(clk),
        .rst(rst),
        .out_valid(out_valid)
    );
    
    // simulate clk
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end
    
    initial begin
        rst = 1;
        #10 rst = 0;
        #20 while (~out_valid) #10;
        if (ciphertext == 128'h8ea2b7ca516745bfeafc49904b496089)
            $display("Testbench passed!");
        else $display("Testbench failed.");
        
        $finish;
    end
endmodule
