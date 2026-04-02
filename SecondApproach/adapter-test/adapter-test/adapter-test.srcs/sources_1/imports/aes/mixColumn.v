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
// Module: mixColumn
// Created: 2022-05-17
// Target Device: ZYNQ-7010
// 
// Description: Implementation of MixColumns AES algorithm for a single column.
//   Logic is just routing and bit arithmetic, but hardware reuse is possible.
// 
//////////////////////////////////////////////////////////////////////////////////

module mixColumn (in, out);
	input [31:0] in;
	output [31:0] out;

	localparam [8:0] RIJNDAEL = 9'h11B;
	wire [7:0] b [3:0];
	wire [8:0] oByte [3:0], c [3:0];

	// bytes separated for readability
	// as a note, these internal signals are removed in synthesis
	assign b[0] = in[7:0];
	assign b[1] = in[15:8];
	assign b[2] = in[23:16];
	assign b[3] = in[31:24];
	
	// shifted signals, reused in matrix multiply
	assign c[0] = b[0] << 1;
	assign c[1] = b[1] << 1;
	assign c[2] = b[2] << 1;
	assign c[3] = b[3] << 1;

	// matrix bit multiplication
	assign oByte[0] = c[0] ^ c[1] ^ b[1] ^ b[2] ^ b[3];
	assign oByte[1] = b[0] ^ c[1] ^ c[2] ^ b[2] ^ b[3];
	assign oByte[2] = b[0] ^ b[1] ^ c[2] ^ c[3] ^ b[3];
	assign oByte[3] = c[0] ^ b[0] ^ b[1] ^ b[2] ^ c[3];
	
	assign out[7:0]    = oByte[0] ^ (oByte[0][8] ? RIJNDAEL : 9'h0);
	assign out[15:8]   = oByte[1] ^ (oByte[1][8] ? RIJNDAEL : 9'h0);
	assign out[23:16]  = oByte[2] ^ (oByte[2][8] ? RIJNDAEL : 9'h0);
	assign out[31:24]  = oByte[3] ^ (oByte[3][8] ? RIJNDAEL : 9'h0);
endmodule
