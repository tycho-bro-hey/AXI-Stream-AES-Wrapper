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
// Description: Determines round key given previous key and round number for AES-256
// 
// Dependencies: subByte
// 
//////////////////////////////////////////////////////////////////////////////////

module aes256KeySchedule (roundKey, key, prevKey, round);
    output [127:0] roundKey;
    output [255:0] key;
    input [255:0] prevKey;
    input [3:0] round;

    wire [255:0] newKey;
    wire [31:0] toSub, subWord;
    wire [7:0] Rcon;
    wire rEven, n_compute;

    assign roundKey = key[127:0];
    assign rEven = ~round[0];
    // signal goes high if no computation needed
    assign n_compute = round == 4'h0 || round == 4'h1;

    // save previous key
    assign newKey[255:128] = prevKey[127:0];

    // first word of new key
    // RotWord, grab from previous word
    // if no compute, put in 1's (no computation needed for inverse)
    assign toSub = n_compute ? 32'h01010101 : (rEven ? {key[151:128], key[159:152]} : key[159:128]);

    // substitution modules
    subByte SUB0 (.inByte(toSub[7:0]), .outByte(subWord[7:0]));
    subByte SUB1 (.inByte(toSub[15:8]), .outByte(subWord[15:8]));
    subByte SUB2 (.inByte(toSub[23:16]), .outByte(subWord[23:16]));
    subByte SUB3 (.inByte(toSub[31:24]), .outByte(subWord[31:24]));

    // rcon computation (only used on even rounds)
    assign Rcon = 8'h1 << round[3:1];

    // other words of new key
    assign newKey[127:96] = subWord ^ prevKey[255:224] ^ {rEven ? Rcon[7:1] : 8'h0, 24'h0};
    assign newKey[95:0]  = key[127:32] ^ prevKey[223:128];

    // only set key if not round 1
    assign key = n_compute ? prevKey : newKey;
endmodule

`define keyCheck(expected) \
    round = round + 1;\
    rst = 1'b1;\
    #10 rst = 1'b0;\
    #10 while (~done) #10;\
    if (expected ^ roundKey) begin\
        $display("Key schedule error!\n\tReturned: %032x\n\tExpected: %032x", roundKey, expected);\
        $stop;\
    end\
    else $display("Round %d key correct!", round);\
    prevKey = key

module keySchedule_tb();
    reg [255:0] prevKey;
    reg [3:0] round;
    reg clk, rst;
    wire [127:0] roundKey;
    wire [255:0] key;
    wire [31:0] toSub, subWord;
    wire done, done0, done1, done2, done3;

    // instance module
    aes256KeySchedule k_sch(.roundKey(roundKey), .key(key), .prevKey(prevKey), .toSub(toSub), .subWord(subWord), .round(round));
    
    // substitution blocks
    subByte SUB0 (.inByte(toSub[31:24]), .clk(clk), .rst(rst), .outByte(subWord[31:24]), .done(done0));
    subByte SUB1 (.inByte(toSub[23:16]), .clk(clk), .rst(rst), .outByte(subWord[23:16]), .done(done1));
    subByte SUB2 (.inByte(toSub[15:8]),  .clk(clk), .rst(rst), .outByte(subWord[15:8]),  .done(done2));
    subByte SUB3 (.inByte(toSub[7:0]),   .clk(clk), .rst(rst), .outByte(subWord[7:0]),   .done(done3));
    
    // set done signal
    assign done = done0 & done1 & done2 & done3;

    // clk simulation
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        // round 1
        prevKey = 256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4;
        round = 4'h0;
        `keyCheck(128'h1f352c073b6108d72d9810a30914dff4);
        `keyCheck(128'h9ba354118e6925afa51a8b5f2067fcde);
        `keyCheck(128'ha8b09c1a93d194cdbe49846eb75d5b9a);
        `keyCheck(128'hd59aecb85bf3c917fee94248de8ebe96);
        `keyCheck(128'hb5a9328a2678a647983122292f6c79b3);
        `keyCheck(128'h812c81addadf48ba24360af2fab8b464);
        `keyCheck(128'h98c5bfc9bebd198e268c3ba709e04214);
        `keyCheck(128'h68007bacb2df331696e939e46c518d80);
        `keyCheck(128'hc814e20476a9fb8a5025c02d59c58239);
        `keyCheck(128'hde1369676ccc5a71fa2563959674ee15);
        `keyCheck(128'h5886ca5d2e2f31d77e0af1fa27cf73c3);
        `keyCheck(128'h749c47ab18501ddae2757e4f7401905a);
        `keyCheck(128'hcafaaae3e4d59b349adf6acebd10190d);
        `keyCheck(128'hfe4890d1e6188d0b046df344706c631e);

        $display("Key Schedule test bench passed!");
        $finish;
    end

endmodule
