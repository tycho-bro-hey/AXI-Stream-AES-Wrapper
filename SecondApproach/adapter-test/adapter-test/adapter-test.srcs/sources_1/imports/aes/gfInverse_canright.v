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
// Module: gfInverse (combinational implementation)
// Created: 2022-08-09
// Target Device: ZYNQ-7010
// 
// Description: Calculates inverse in GF(2^8) by recursively computing inverse of
//  value in subfield. Requires 11 multiplications.
// 
// Dependencies: gfMult
// 
//////////////////////////////////////////////////////////////////////////////////

module gfInverse(
    input [7:0] a,
    output [7:0] inv
    );

    wire [7:0] G, G_prime [3:0], theta, theta_prime [1:0], Phi,
        Phi_inv, theta_inv;

    assign G = a;

    // calculate G^16
    gfMult G_2  (.a(G), .b(G), .result(G_prime[3]));
    gfMult G_4  (.a(G_prime[3]), .b(G_prime[3]), .result(G_prime[2]));
    gfMult G_8  (.a(G_prime[2]), .b(G_prime[2]), .result(G_prime[1]));
    gfMult G_16 (.a(G_prime[1]), .b(G_prime[1]), .result(G_prime[0]));

    // calculate theta = G^17 = G^16 * G
    gfMult G_17 (.a(G_prime[0]), .b(G), .result(theta));

    // calculate theta^4
    gfMult th_2 (.a(theta), .b(theta), .result(theta_prime[1]));
    gfMult th_4 (.a(theta_prime[1]), .b(theta_prime[1]), .result(theta_prime[0]));

    // calculate Phi = theta^5 = theta^4 * theta
    gfMult th_5 (.a(theta_prime[0]), .b(theta), .result(Phi));

    // calculate Phi ^ 2, which in GF(2^2) Phi^2 = Phi^-1
    gfMult inv_4 (.a(Phi), .b(Phi), .result(Phi_inv));

    // calculate theta^-1 = Phi^-1 * theta_prime
    gfMult inv_16 (.a(Phi_inv), .b(theta_prime[0]), .result(theta_inv));

    // calculate G^-1 = theta^-1 * G_prime
    gfMult inv_256 (.a(theta_inv), .b(G_prime[0]), .result(inv));

endmodule
