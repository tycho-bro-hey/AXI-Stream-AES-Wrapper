`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// 
// Author: Robert Stacy Lois
// Email: rslois@sandia.gov
// 
// Project: AES-256-GCM
// Module: ghash.v 
// Created: 2026-02
// Target Device: Arty A7-100T
// 
// Description: GHASH function for AES-GCM authentication,
//   which implements NIST SP 800-38D Algorithm 2 (GHASH)
//
//   GHASH computes: Y = X_1*H^m XOR X_2*H^(m-1) XOR ... XOR X_m*H
// 
// Dependencies: gf128_mult 
//
//////////////////////////////////////////////////////////////////////////////

module ghash (
    input wire clk,
    input wire rst,
    
    // control signals
    input wire start, // Initialize GHASH 
    input wire block_valid, // Input block is valid
    input wire finish, // Signal that current block is the last
    
    // data inputs
    input wire [127:0] h, // Hash subkey H = AES_K(0^128)
    input wire [127:0] block_in, // Input block (AAD, ciphertext, or length block)
    
    // outputs
    output reg [127:0] ghash_out, // GHASH result
    output wire done, // GHASH computation complete
    output wire ready // ready to accept new block
);

    // State Machine States
    localparam STATE_IDLE = 3'd0; // waiting for start
    localparam STATE_READY = 3'd1; // ready to receive blocks
    localparam STATE_XOR = 3'd2; // XOR block with accumulator
    localparam STATE_MULT_START = 3'd3; // start GF multiplication
    localparam STATE_MULT_WAIT = 3'd4; // wait for multiplication to complete
    localparam STATE_DONE = 3'd5; // GHASH complete
    
    reg [2:0] state;
    
    // Internal Registers
    reg [127:0] h_reg; // Stored hash subkey
    reg [127:0] y_reg; // GHASH accumulator
    reg [127:0] xor_result; // Result of Y XOR X
    reg last_block; // Flag indicating final block
    
    // GF(2^128) Multiplier Interface
    reg mult_start;
    wire [127:0] mult_result;
    wire mult_done;
    
    gf128_mult u_gf128_mult (
        .clk(clk),
        .rst(rst),
        .start(mult_start),
        .x(h_reg),
        .y(xor_result), 
        .result(mult_result), 
        .done(mult_done)
    );
    
    // Output Assignments
    assign done = (state == STATE_DONE);
    assign ready = (state == STATE_READY);
       
    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            h_reg <= 128'd0;
            y_reg <= 128'd0;
            xor_result <= 128'd0;
            ghash_out <= 128'd0;
            mult_start <= 1'b0;
            last_block <= 1'b0;
        end
        else begin
            mult_start <= 1'b0;
            
            case (state)
                // IDLE --- wait for start signal
                STATE_IDLE: begin
                    if (start) begin
                        h_reg <= h; // Store hash subkey
                        y_reg <= 128'd0; // Y_0 = 0^128
                        last_block <= 1'b0;
                        state <= STATE_READY;
                    end
                end
                
                // READY --- wait for input block
                STATE_READY: begin
                    if (block_valid) begin
                        // Capture whether this is the last block
                        last_block <= finish;
                        state <= STATE_XOR;
                    end
                end
                
                // compute Y_{i-1} XOR X_i
                STATE_XOR: begin
                    xor_result <= y_reg ^ block_in;
                    state <= STATE_MULT_START;
                end
                
                // begin GF(2^128) multiplication
                STATE_MULT_START: begin
                    mult_start <= 1'b1;
                    state <= STATE_MULT_WAIT;
                end
                
                // wait for multiplication to complete
                STATE_MULT_WAIT: begin
                    if (mult_done) begin
                        y_reg <= mult_result;   // Y_i = (Y_{i-1} XOR X_i) * H
                        
                        if (last_block) begin
                            ghash_out <= mult_result;
                            state <= STATE_DONE;
                        end
                        else begin
                            state <= STATE_READY;  // ready for next block
                        end
                    end
                end
                
                STATE_DONE: begin
                    if (start) begin
                        h_reg <= h;
                        y_reg <= 128'd0;
                        last_block <= 1'b0;
                        state <= STATE_READY;
                    end
                end
                
                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
