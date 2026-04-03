`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// 
// Author: Robert Stacy Lois
// Email: rslois@sandia.gov
// 
// Project: AES-256-GCM
// Module: aes_gcm_256.v 
// Created: 2026-02
// Target Device: Arty A7-100T
// 
// Description: TOP-LEVEL AES-GCM-256 authenticated encryption/decryption module,
//   which implements NIST SP 800-38D Algorithm 4 (GCM-AE) and Algorithm 5 (GCM-AD)
//
//   We include two modes (0 for encrypt Alg 4, 1 for decrypt Alg 5).
//   
// Dependencies: aes256 (Enano AES core), ghash, gf128_mult
//
//////////////////////////////////////////////////////////////////////////////

module aes_gcm_256 (
    input wire clk,
    input wire rst,
    
    // control
    input wire start,
    input wire mode, // 0 = encrypt (GCM-AE), 1 = decrypt (GCM-AD)
    output wire busy,
    output wire done,
    
    // Key and IV
    input wire [255:0] key,
    input wire [95:0] iv,
    
    // AAD interface
    input wire [127:0] aad_in,
    input wire aad_valid,
    input wire [4:0] aad_len,
    input wire aad_last,
    
    // data interface --- plaintext for encrypt, ciphertext for decrypt
    input wire [127:0] pt_in,
    input wire pt_valid,
    input wire [4:0] pt_len,
    input wire pt_last,
    
    // for empty data cases
    input wire finalize,
    
    // Data output --- ciphertext for encrypt, plaintext for decrypt
    output reg [127:0] ct_out,
    output reg ct_valid,
    
    // Authentication Tag
    output reg [127:0] tag,
    
    // Decrypt verification
    input wire [127:0] tag_in,
    output reg tag_match, // 1 = tags match (decrypt authenticated)
    output reg auth_fail // 1 = tags mismatch (decrypt failed)
);

    // State Machine
    localparam STATE_IDLE = 4'd0;
    localparam STATE_COMPUTE_H = 4'd1;
    localparam STATE_WAIT_H = 4'd2;
    localparam STATE_INIT_GHASH = 4'd3; 
    localparam STATE_READY = 4'd4;
    localparam STATE_AAD_GHASH = 4'd5;
    localparam STATE_AAD_GHASH_WAIT = 4'd6;
    localparam STATE_PT_AES_START = 4'd7;
    localparam STATE_PT_AES_WAIT = 4'd8;
    localparam STATE_PT_GHASH = 4'd9;
    localparam STATE_PT_GHASH_WAIT = 4'd10;
    localparam STATE_LEN_GHASH = 4'd11;
    localparam STATE_LEN_GHASH_WAIT = 4'd12;
    localparam STATE_COMPUTE_EJ0 = 4'd13;
    localparam STATE_WAIT_EJ0 = 4'd14;
    localparam STATE_DONE = 4'd15;
    
    reg [3:0] state;
    
    // Internal Registers
    reg [255:0] key_reg;
    reg [127:0] h_reg; // Hash subkey
    reg [127:0] j0_reg; // J0 = IV || 0^31 || 1
    reg [127:0] cb_reg; // Current counter block
    reg [127:0] pt_reg; // Stored input data block (PT or CT)
    reg [127:0] ct_reg; // Stored ciphertext for GHASH
    reg [63:0] aad_len_bits;
    reg [63:0] ct_len_bits;
    reg pt_is_last;
    reg [4:0] pt_len_reg; // Bytes in current data block
    reg aad_phase_done;
    reg mode_reg; // Latched mode (0=encrypt, 1=decrypt)
    reg [127:0] tag_in_reg; // Latched received tag for comparison
    
    // AES-256 Interface
    reg [127:0] aes_plaintext;
    reg aes_in_valid;
    wire [127:0] aes_ciphertext;
    wire aes_out_valid;
    
    // GHASH Interface
    reg ghash_start;
    reg ghash_block_valid;
    reg ghash_finish;
    reg [127:0] ghash_block_in;
    wire [127:0] ghash_out;
    wire ghash_done;
    wire ghash_ready;
    
    // output Assignments
    assign busy = (state != STATE_IDLE) && (state != STATE_DONE);
    assign done = (state == STATE_DONE);
    
    // inc_32 Function: Increment rightmost 32 bits
    function [127:0] inc_32;
        input [127:0] x;
        begin
            inc_32 = {x[127:32], x[31:0] + 32'd1};
        end
    endfunction
    
    // partial block mask: zero out unused bytes
    function [127:0] mask_block;
        input [127:0] data;
        input [4:0] num_bytes;  // 1-16 (0 means 16)
        reg [4:0] bytes;
        reg [127:0] mask;
        integer i;
        begin
            bytes = (num_bytes == 5'd0) ? 5'd16 : num_bytes;
            mask = 128'd0;
            for (i = 0; i < 16; i = i + 1) begin
                if (i < bytes) begin
                    mask[127 - i*8 -: 8] = 8'hFF;
                end
            end
            mask_block = data & mask;
        end
    endfunction
    
    // Main State Machine
    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            key_reg <= 256'd0;
            h_reg <= 128'd0;
            j0_reg <= 128'd0;
            cb_reg <= 128'd0;
            pt_reg <= 128'd0;
            ct_reg <= 128'd0;
            aad_len_bits <= 64'd0;
            ct_len_bits <= 64'd0;
            pt_is_last <= 1'b0;
            pt_len_reg <= 5'd16;
            aad_phase_done <= 1'b0;
            aes_plaintext <= 128'd0;
            aes_in_valid <= 1'b0;
            ghash_start <= 1'b0;
            ghash_block_valid <= 1'b0;
            ghash_finish <= 1'b0;
            ghash_block_in <= 128'd0;
            ct_out <= 128'd0;
            ct_valid <= 1'b0;
            tag <= 128'd0;
            mode_reg <= 1'b0;
            tag_in_reg <= 128'd0;
            tag_match <= 1'b0;
            auth_fail <= 1'b0;
        end
        else begin
            // default: deassert single-cycle pulses
            aes_in_valid <= 1'b0;
            ghash_start <= 1'b0;
            ghash_block_valid <= 1'b0;
            ghash_finish <= 1'b0;
            ct_valid <= 1'b0;
            
            case (state)
                // IDLE: Wait for start
                STATE_IDLE: begin
                    if (start) begin
                        // store key and compute J0 DIRECTLY
                        key_reg <= key;
                        j0_reg <= {iv, 32'h00000001};
                        cb_reg <= {iv, 32'h00000001};
                        aad_len_bits <= 64'd0;
                        ct_len_bits <= 64'd0;
                        aad_phase_done <= 1'b0;
                        mode_reg <= mode;
                        tag_in_reg <= tag_in;
                        tag_match <= 1'b0;
                        auth_fail <= 1'b0;
                        
                        // start computing H = E_K(0^128)
                        aes_plaintext <= 128'd0;
                        aes_in_valid <= 1'b1;
                        
                        state <= STATE_COMPUTE_H;
                    end
                end
                
                // COMPUTE_H --- Wait for AES to sample input
                STATE_COMPUTE_H: begin
                    state <= STATE_WAIT_H;
                end
                
                // WAIT_H --- Wait for H = E_K(0^128)
                STATE_WAIT_H: begin
                    if (aes_out_valid) begin
                        h_reg <= aes_ciphertext;
                        // Don't start GHASH yet - wait for h_reg to update
                        state <= STATE_INIT_GHASH;
                    end
                end
                
                // INIT_GHASH --- initialize GHASH with H (h_reg is now valid)
                STATE_INIT_GHASH: begin
                    ghash_start <= 1'b1;
                    state <= STATE_READY;
                end
                
                // READY --- accept AAD or plaintext
                STATE_READY: begin
                    if (aad_valid && !aad_phase_done) begin
                        // Process AAD block
                        ghash_block_in <= aad_in;
                        
                        // Update AAD length in bits
                        if (aad_len == 5'd0 || aad_len == 5'd16)
                            aad_len_bits <= aad_len_bits + 64'd128;
                        else
                            aad_len_bits <= aad_len_bits + {56'd0, aad_len, 3'b000};
                        
                        if (aad_last) begin
                            aad_phase_done <= 1'b1;
                        end
                        
                        state <= STATE_AAD_GHASH;
                    end
                    else if (pt_valid) begin
                        // Process plaintext block
                        aad_phase_done <= 1'b1;  // No more AAD after this
                        pt_reg <= pt_in;
                        pt_is_last <= pt_last;
                        pt_len_reg <= pt_len;
                        
                        // update CT length in bits
                        if (pt_len == 5'd0 || pt_len == 5'd16)
                            ct_len_bits <= ct_len_bits + 64'd128;
                        else
                            ct_len_bits <= ct_len_bits + {56'd0, pt_len, 3'b000};
                        
                        // increment counter and start AES
                        cb_reg <= inc_32(cb_reg);
                        aes_plaintext <= inc_32(cb_reg);
                        aes_in_valid <= 1'b1;
                        
                        state <= STATE_PT_AES_START;
                    end
                    else if (finalize) begin
                        // No plaintext - go to length block
                        aad_phase_done <= 1'b1;
                        state <= STATE_LEN_GHASH;
                    end
                end
                
                // AAD_GHASH --- send AAD block to GHASH
                STATE_AAD_GHASH: begin
                    if (ghash_ready) begin
                        ghash_block_valid <= 1'b1;
                        state <= STATE_AAD_GHASH_WAIT;
                    end
                end
                
                // AAD_GHASH_WAIT --- wait for GHASH to process AAD
                STATE_AAD_GHASH_WAIT: begin
                    if (ghash_ready) begin
                        state <= STATE_READY;
                    end
                end
                
                // PT_AES_START --- wait for AES to sample counter
                STATE_PT_AES_START: begin
                    state <= STATE_PT_AES_WAIT;
                end
                
                // PT_AES_WAIT --- wait for E_K(CB) to complete
                STATE_PT_AES_WAIT: begin
                    if (aes_out_valid) begin
                        if (mode_reg == 1'b0) begin
                            // ENCRYPT C = P XOR E_K(CB)
                            // Output = ciphertext 
                            // GHASH = ciphertext 
                            if (pt_is_last && pt_len_reg != 5'd0 && pt_len_reg != 5'd16) begin
                                ct_reg <= mask_block(pt_reg ^ aes_ciphertext, pt_len_reg);
                                ct_out <= mask_block(pt_reg ^ aes_ciphertext, pt_len_reg);
                                ghash_block_in <= mask_block(pt_reg ^ aes_ciphertext, pt_len_reg);
                            end else begin
                                ct_reg <= pt_reg ^ aes_ciphertext;
                                ct_out <= pt_reg ^ aes_ciphertext;
                                ghash_block_in <= pt_reg ^ aes_ciphertext;
                            end
                        end else begin
                            // DECRYPT P = C XOR E_K(CB)
                            // Output = plaintext
                            // GHASH = ciphertext
                            if (pt_is_last && pt_len_reg != 5'd0 && pt_len_reg != 5'd16) begin
                                ct_out <= mask_block(pt_reg ^ aes_ciphertext, pt_len_reg);
                                ghash_block_in <= mask_block(pt_reg, pt_len_reg);
                            end else begin
                                ct_out <= pt_reg ^ aes_ciphertext;
                                ghash_block_in <= pt_reg;
                            end
                        end
                        ct_valid <= 1'b1;
                        
                        state <= STATE_PT_GHASH;
                    end
                end
                
                // PT_GHASH --- send ciphertext to GHASH
                STATE_PT_GHASH: begin
                    if (ghash_ready) begin
                        ghash_block_valid <= 1'b1;
                        state <= STATE_PT_GHASH_WAIT;
                    end
                end
                
                // PT_GHASH_WAIT --- wait for GHASH to process ciphertext
                STATE_PT_GHASH_WAIT: begin
                    if (ghash_ready) begin
                        if (pt_is_last) begin
                            state <= STATE_LEN_GHASH;
                        end else begin
                            state <= STATE_READY;
                        end
                    end
                end
                
                // LEN_GHASH --- send length block to GHASH
                STATE_LEN_GHASH: begin
                    if (ghash_ready) begin
                        ghash_block_in <= {aad_len_bits, ct_len_bits};
                        ghash_block_valid <= 1'b1;
                        ghash_finish <= 1'b1;
                        state <= STATE_LEN_GHASH_WAIT;
                    end
                end
                
                // LEN_GHASH_WAIT --- wait for final GHASH
                STATE_LEN_GHASH_WAIT: begin
                    if (ghash_done) begin
                        // Start computing E_K(J0)
                        aes_plaintext <= j0_reg;
                        aes_in_valid <= 1'b1;
                        state <= STATE_COMPUTE_EJ0;
                    end
                end
                
                // COMPUTE_EJ0: Wait for AES to sample J0
                STATE_COMPUTE_EJ0: begin
                    state <= STATE_WAIT_EJ0;
                end
                
                // WAIT_EJ0: Wait for E_K(J0) and compute tag-
                STATE_WAIT_EJ0: begin
                    if (aes_out_valid) begin
                        // T = GHASH XOR E_K(J0)
                        tag <= ghash_out ^ aes_ciphertext;
                        
                        // perform tag comparison HERE using the computed value
                        if (mode_reg == 1'b1) begin
                            // DECRYPT --- compare computed tag with received tag
                            tag_match <= ((ghash_out ^ aes_ciphertext) == tag_in_reg);
                            auth_fail <= ((ghash_out ^ aes_ciphertext) != tag_in_reg);
                        end else begin
                            // ENCRYPT --- no verification needed
                            tag_match <= 1'b0;
                            auth_fail <= 1'b0;
                        end
                        
                        state <= STATE_DONE;
                    end
                end
                
                STATE_DONE: begin
                    
                    if (start) begin
                        // restart with new key/IV --- compute directly
                        key_reg <= key;
                        j0_reg <= {iv, 32'h00000001};
                        cb_reg <= {iv, 32'h00000001};
                        aad_len_bits <= 64'd0;
                        ct_len_bits <= 64'd0;
                        aad_phase_done <= 1'b0;
                        mode_reg <= mode;
                        tag_in_reg <= tag_in;
                        tag_match <= 1'b0;
                        auth_fail <= 1'b0;
                        
                        aes_plaintext <= 128'd0;
                        aes_in_valid <= 1'b1;
                        
                        state <= STATE_COMPUTE_H;
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end
    
    // Module Instantiations
    
    // AES-256 (from Enano Repo)
    aes256 u_aes256 (
        .ciphertext(aes_ciphertext),
        .out_valid(aes_out_valid),
        .plaintext(aes_plaintext),
        .key(key_reg),
        .clk(clk),
        .in_valid(aes_in_valid)
    );
    
    // GHASH
    ghash u_ghash (
        .clk(clk),
        .rst(rst),
        .start(ghash_start),
        .block_valid(ghash_block_valid),
        .finish(ghash_finish),
        .h(h_reg),
        .block_in(ghash_block_in),
        .ghash_out(ghash_out),
        .done(ghash_done),
        .ready(ghash_ready)
    );

endmodule
