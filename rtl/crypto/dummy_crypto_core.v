`timescale 1ns / 1ps
// ============================================================================
// dummy_crypto_core.v — Custom Encryption Block Template / Skeleton
// ============================================================================
// This is a sample encryption module (Template/Skeleton) for users to replace
// or integrate custom hardware accelerators (Custom Encryption/AEAD Algorithm).
//
// Standard Interface Ports:
//   - clk, rst_n       : Clock and synchronous active-low reset
//   - start            : 1-cycle start pulse from APB bus
//   - decrypt          : 0 = Encrypt, 1 = Decrypt
//   - key[128]         : 128-bit Encryption Key (or extensible to 256-bit)
//   - nonce[128]       : Nonce / Initialization Vector (IV)
//   - ad[128]          : Associated Data
//   - data_in[128]     : Input Data Block (128-bit Plaintext/Ciphertext)
//   - tag_in[128]      : Input Expected Tag (for Decrypt mode)
//   - data_out[128]    : Output Data Block (128-bit Ciphertext/Plaintext)
//   - tag_out[128]     : 128-bit Output Authentication Tag (MAC/Tag)
//   - done             : 1-cycle completion pulse flag
//   - valid            : Output data and tag valid indicator
// ============================================================================

module dummy_crypto_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         decrypt,
    input  wire [127:0] key,
    input  wire [127:0] nonce,
    input  wire [127:0] ad,
    input  wire [127:0] data_in,
    input  wire [127:0] tag_in,
    output reg  [127:0] data_out,
    output reg  [127:0] tag_out,
    output reg          done,
    output reg          valid
);

    // ------------------------------------------------------------------------
    // FSM States
    // ------------------------------------------------------------------------
    localparam STATE_IDLE    = 2'b00;
    localparam STATE_PROCESS = 2'b01;
    localparam STATE_DONE    = 2'b10;

    reg [1:0] state;
    reg [3:0] cycle_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= STATE_IDLE;
            cycle_cnt   <= 4'd0;
            data_out    <= 128'h0;
            tag_out     <= 128'h0;
            done        <= 1'b0;
            valid       <= 1'b0;
        end else begin
            done <= 1'b0; // Default single-cycle pulse

            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        state     <= STATE_PROCESS;
                        cycle_cnt <= 4'd0;
                        valid     <= 1'b0;
                    end
                end

                STATE_PROCESS: begin
                    // Simulate 4-cycle execution processing (Replace with real logic)
                    if (cycle_cnt == 4'd4) begin
                        state <= STATE_DONE;
                        done  <= 1'b1;
                        valid <= 1'b1;
                        
                        // Sample Encryption/Decryption logic:
                        if (!decrypt) begin
                            // Encryption
                            data_out <= data_in ^ key;
                            tag_out  <= nonce ^ ad ^ key;
                        end else begin
                            // Decryption
                            data_out <= data_in ^ key;
                            tag_out  <= nonce ^ ad ^ key;
                        end
                    end else begin
                        cycle_cnt <= cycle_cnt + 1'b1;
                    end
                end

                STATE_DONE: begin
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
