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
// Module: gfMult
// Created: 2022-05-13
// Target Device: ZYNQ-7010
// 
// Description: Multiplies inputs under GF(2^8) using purely combinational logic
//   Footprint could be reduced easily through hardware reuse.
// 
//////////////////////////////////////////////////////////////////////////////////

module gfMult (
    input [7:0] a, b,
    output reg [7:0] result
);
    localparam [7:0] RIJNDAEL = 8'h1B;
    reg [15:0] mult;

    always @(*) begin
        // multiply
        mult = 16'b0;
        if (a[0]) mult = mult ^ b;
        if (a[1]) mult = mult ^ (b << 1);
        if (a[2]) mult = mult ^ (b << 2);
        if (a[3]) mult = mult ^ (b << 3);
        if (a[4]) mult = mult ^ (b << 4);
        if (a[5]) mult = mult ^ (b << 5);
        if (a[6]) mult = mult ^ (b << 6);
        if (a[7]) mult = mult ^ (b << 7);

        // modulo - long polynomial division
        if (mult[15]) mult = mult ^ (RIJNDAEL << 7);
        if (mult[14]) mult = mult ^ (RIJNDAEL << 6);
        if (mult[13]) mult = mult ^ (RIJNDAEL << 5);
        if (mult[12]) mult = mult ^ (RIJNDAEL << 4);
        if (mult[11]) mult = mult ^ (RIJNDAEL << 3);
        if (mult[10]) mult = mult ^ (RIJNDAEL << 2);
        if (mult[9])  mult = mult ^ (RIJNDAEL << 1);
        if (mult[8])  mult = mult ^ RIJNDAEL;
        
        result = mult[7:0];
    end
endmodule
