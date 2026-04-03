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
// Module: aesRound (combinational logic)
// Created: 2022-05-17
// Target Device: ZYNQ-7010
// 
// Description: Implementation of an AES "round", takes round key as input.
//   Everything is combinational at this level, can be simplified through
//   hardware reuse.
//
// Note: bitstreams are aligned as follows: b0,b1,b2,b3,...,b14,b15
// 
//////////////////////////////////////////////////////////////////////////////////

module aesRound (inData, outData, roundKey, last);
	input [127:0] inData, roundKey;
	output [127:0] outData;
	input last;

	// shiftData and mixData are byte arrays in column-major order
	wire [7:0] shiftData [3:0][3:0], mixData [3:0][3:0];
	wire [127:0] preAdd;
	
	// S-box algorithm, then:
	// ShiftRows algorithm, static assignment
	subByte INV00 (.inByte(inData[127:120]), .outByte(shiftData[0][0]));
	subByte INV01 (.inByte(inData[119:112]), .outByte(shiftData[1][3]));
	subByte INV02 (.inByte(inData[111:104]), .outByte(shiftData[2][2]));
	subByte INV03 (.inByte(inData[103:96]),  .outByte(shiftData[3][1]));
	subByte INV04 (.inByte(inData[95:88]),   .outByte(shiftData[0][1]));
	subByte INV05 (.inByte(inData[87:80]),   .outByte(shiftData[1][0]));
	subByte INV06 (.inByte(inData[79:72]),   .outByte(shiftData[2][3]));
	subByte INV07 (.inByte(inData[71:64]),   .outByte(shiftData[3][2]));
	subByte INV08 (.inByte(inData[63:56]),   .outByte(shiftData[0][2]));
	subByte INV09 (.inByte(inData[55:48]),   .outByte(shiftData[1][1]));
	subByte INV10 (.inByte(inData[47:40]),   .outByte(shiftData[2][0]));
	subByte INV11 (.inByte(inData[39:32]),   .outByte(shiftData[3][3]));
	subByte INV12 (.inByte(inData[31:24]),   .outByte(shiftData[0][3]));
	subByte INV13 (.inByte(inData[23:16]),   .outByte(shiftData[1][2]));
	subByte INV14 (.inByte(inData[15:8]),    .outByte(shiftData[2][1]));
	subByte INV15 (.inByte(inData[7:0]),     .outByte(shiftData[3][0]));

	// colum mixing algorithm, operating on 4-byte words
	mixColumn MIX0 (.in({shiftData[3][0], shiftData[2][0], shiftData[1][0], shiftData[0][0]}),
		.out({mixData[3][0], mixData[2][0], mixData[1][0], mixData[0][0]}));
	mixColumn MIX1 (.in({shiftData[3][1], shiftData[2][1], shiftData[1][1], shiftData[0][1]}),
		.out({mixData[3][1], mixData[2][1], mixData[1][1], mixData[0][1]}));
	mixColumn MIX2 (.in({shiftData[3][2], shiftData[2][2], shiftData[1][2], shiftData[0][2]}),
		.out({mixData[3][2], mixData[2][2], mixData[1][2], mixData[0][2]}));
	mixColumn MIX3 (.in({shiftData[3][3], shiftData[2][3], shiftData[1][3], shiftData[0][3]}),
		.out({mixData[3][3], mixData[2][3], mixData[1][3], mixData[0][3]}));

	// put data back together, column-major order
    // if last round, ignore mixData
    assign preAdd = last ? 
		{shiftData[0][0], shiftData[1][0], shiftData[2][0], shiftData[3][0], 
		shiftData[0][1], shiftData[1][1], shiftData[2][1], shiftData[3][1], 
		shiftData[0][2], shiftData[1][2], shiftData[2][2], shiftData[3][2], 
		shiftData[0][3], shiftData[1][3], shiftData[2][3], shiftData[3][3]}
		: 
		{mixData[0][0], mixData[1][0], mixData[2][0], mixData[3][0], 
		mixData[0][1], mixData[1][1], mixData[2][1], mixData[3][1], 
		mixData[0][2], mixData[1][2], mixData[2][2], mixData[3][2], 
		mixData[0][3], mixData[1][3], mixData[2][3], mixData[3][3]};

	assign outData = roundKey ^ preAdd;

endmodule
