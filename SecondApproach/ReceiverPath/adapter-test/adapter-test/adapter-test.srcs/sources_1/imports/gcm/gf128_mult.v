`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// 
// Author: Robert Stacy Lois
// Email: rslois@sandia.gov
// 
// Project: AES-256-GCM
// Module: gf128_mult.v 
// Created: 2026-02
// Target Device: Arty A7-100T
// 
// Description: GF(2^128) multiplication for GHASH authentication in AES-GCM,
//   which implements NIST SP 800-38D Algorithm 1 with correct reflected bit ordering
// 
//   The GCM field polynomial is: x^128 + x^7 + x^2 + x + 1
//   Reduction constant R = 0xE1000000000000000000000000000000
//
//////////////////////////////////////////////////////////////////////////////

module gf128_mult (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [127:0] x, // first operand 
    input wire [127:0] y, // second operand 
    output reg [127:0] result, // product result in GF(2^128)
    output wire done
);

    // GCM Reduction Polynomial Constant
    // R = 11100001 || 0^120 in reflected bit order
    // This is 0xE1 followed by 120 zero bits
    localparam [127:0] R = 128'hE1000000000000000000000000000000;

    // Internal Registers
    reg [127:0] z_reg; // accumulator (Z in NIST notation)
    reg [127:0] v_reg; // shifted multiplicand (V in NIST notation)
    reg [7:0] bit_count; // Bit counter (0 to 127)
    reg running; // FSM state for multiplication 

    assign done = (bit_count == 8'd128) && !running && !start;
    
    always @(posedge clk) begin
        if (rst) begin
            z_reg <= 128'd0;
            v_reg <= 128'd0;
            bit_count <= 8'd0;
            running <= 1'b0;
            result <= 128'd0;
        end
        else if (start && !running) begin
            // initialize for new multiplication
            z_reg <= 128'd0; // Z_0 = 0^128
            v_reg <= y; // V_0 = Y
            bit_count <= 8'd0;
            running <= 1'b1;
        end
        else if (running) begin
            // one iteration of the multiplication algorithm
            
            // step 1 --- If x_i = 1, then Z = Z XOR V
            // x_i in NIST = x[127 - bit_count] (MSB-first ordering per spec)
            if (x[127 - bit_count]) begin
                z_reg <= z_reg ^ v_reg;
            end
            
            // step 2 --- Shift V right, with conditional XOR of R
            // If LSB(V) = 1 (v_127 in NIST = v_reg[0])
            if (v_reg[0]) begin
                v_reg <= {1'b0, v_reg[127:1]} ^ R;
            end
            else begin
                v_reg <= {1'b0, v_reg[127:1]};
            end
            
            // increment bit counter
            bit_count <= bit_count + 8'd1;
            
            // check if complete
            if (bit_count == 8'd127) begin
                running <= 1'b0;
                // Capture final result (need to include last iteration)
                if (x[127 - bit_count]) begin
                    result <= z_reg ^ v_reg;
                end
                else begin
                    result <= z_reg;
                end
            end
        end
    end

endmodule



// testing gf128_mult_comb
// 
// Description: Combinational (single-cycle) GF(2^128) multiplier.
//   Higher area but completes in one clock cycle.
//   Useful for high-throughput applications.
//
//   This uses significantly more LUTs than the sequential version.
//   Use gf128_mult for area-constrained designs.


module gf128_mult_comb (
    input wire [127:0] x,
    input wire [127:0] y,
    output wire [127:0] result
);

    localparam [127:0] R = 128'hE1000000000000000000000000000000;

    // intermediate Z and V values for all 128 iterations
    wire [127:0] z [0:128];
    wire [127:0] v [0:128];
    
    // initial values
    assign z[0] = 128'd0;
    assign v[0] = y;
    
    // generate all 128 iterations combinationally
    genvar i;
    generate
        for (i = 0; i < 128; i = i + 1) begin : mult_stage
            // Z update: if x_i = 1, Z = Z XOR V
            assign z[i+1] = x[127-i] ? (z[i] ^ v[i]) : z[i];
            
            // V update: right shift with conditional R XOR
            assign v[i+1] = v[i][0] ? ({1'b0, v[i][127:1]} ^ R) : {1'b0, v[i][127:1]};
        end
    endgenerate
    
    // Final result
    assign result = z[128];

endmodule
