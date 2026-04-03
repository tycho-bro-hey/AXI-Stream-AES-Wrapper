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
// Module: subByte
// Created: 2022-05-13
// Target Device: ZYNQ-7010
// 
// Description: Calculates substitution byte according to Rijndael's
//   AES substitution algorithm using Galois field inverse.
// 
// Dependencies: one gfInverse module, LUT6_2
// 
//////////////////////////////////////////////////////////////////////////////////

module subByte (
    input [7:0] inByte,
    output [7:0] outByte
    );

    wire [7:0] inv;
    wire [3:0] save;

    gfInverse INV (.a(inByte), .inv(inv));
    
    // bottom 32 bits give XOR for 4 common bits between affine[x] and affine[x+1]
    // top 32 bits give correct value of affine[x]
    LUT6_2 #(.INIT(64'h6996966969966996)) AFF0 (.O5(save[0]), .O6(outByte[0]),
        .I0(inv[0]), .I1(inv[7]), .I2(inv[6]), .I3(inv[5]), .I4(inv[4]), .I5(1'b1));
    LUT6_2 #(.INIT(64'h9669699669966996)) AFF2 (.O5(save[1]), .O6(outByte[2]),
        .I0(inv[2]), .I1(inv[1]), .I2(inv[0]), .I3(inv[7]), .I4(inv[6]), .I5(1'b1));
    LUT6_2 #(.INIT(64'h9669699669966996)) AFF4 (.O5(save[2]), .O6(outByte[4]),
        .I0(inv[4]), .I1(inv[3]), .I2(inv[2]), .I3(inv[1]), .I4(inv[0]), .I5(1'b1));
    LUT6_2 #(.INIT(64'h6996966969966996)) AFF6 (.O5(save[3]), .O6(outByte[6]),
        .I0(inv[6]), .I1(inv[5]), .I2(inv[4]), .I3(inv[3]), .I4(inv[2]), .I5(1'b1));
    
    // 32 bit chunks give XOR for previous 4 common bits (stored in save
    // wire) and missing bit for correct value of outByte[x]
    // 05 is bottom 2 bits (repeats of 4 bits), O6 is bits 2 and 3, so LUT value
    // repeats every 16 bits (groups of 4 to match repeats of 4 above) 
    LUT6_2 #(.INIT(64'h0ff00ff099999999)) AFF13 (.O5(outByte[1]), .O6(outByte[3]),
        .I0(save[0]), .I1(inv[1]), .I2(save[1]), .I3(inv[3]), .I5(1'b1));
    LUT6_2 #(.INIT(64'h0ff00ff099999999)) AFF57 (.O5(outByte[5]), .O6(outByte[7]),
        .I0(save[2]), .I1(inv[5]), .I2(save[3]), .I3(inv[7]), .I5(1'b1));

endmodule
