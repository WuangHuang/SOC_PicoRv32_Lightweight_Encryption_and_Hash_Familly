`timescale 1ns / 1ps
// ============================================================================
// crypto_cluster.v — Shared APB Slave Cluster for Extensible Crypto Cores
// ============================================================================
// This module manages APB bus communication with the CPU, performs address
// decoding, stores input/output data registers, and routes control signals
// to custom hardware accelerators (Custom Encryption/AEAD Cores).
//
// REGISTER MAP (Relative address PADDR[9:0]):
//   0x000 : Control & Status Register (CTRL)
//           [1:0]  alg_sel   : 00 = Dummy Core (or Custom Core 0), 01 = Custom Core 1...
//           [2]    start     : Write 1 to trigger start pulse (auto-cleared next cycle)
//           [3]    decrypt   : 0 = Encrypt, 1 = Decrypt
//           [6]    done      : (Read-Only) Completion status flag
//           [7]    valid     : (Read-Only) Output valid status flag
//   0x004–0x010 : Key[127:0]      (Words 1–4)
//   0x014–0x020 : Nonce[127:0]    (Words 5–8)
//   0x024–0x030 : AD[127:0]       (Words 9–12)
//   0x034–0x040 : Data_In[127:0]  (Words 13–16)
//   0x044–0x050 : Tag_In[127:0]   (Words 17–20)
//   0x080–0x08C : Data_Out[127:0] (Words 32–35) (Read-Only)
//   0x090–0x09C : Tag_Out[127:0]  (Words 36–39) (Read-Only)
//   0x0A0       : meas_status     (Word 40) [0]=active, [2:1]=active_alg
//   0x0A4       : meas_cycles_cur (Word 41) Active clock cycle execution counter
//   0x0A8       : meas_cycles_last(Word 42) Cycle count recorded from last run
// ============================================================================

module crypto_cluster #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32
)(
    input  wire                   PCLK,
    input  wire                   PRESETn,
    input  wire [ADDR_WIDTH-1:0]  PADDR,
    input  wire                   PSEL,
    input  wire                   PENABLE,
    input  wire                   PWRITE,
    input  wire [DATA_WIDTH-1:0]  PWDATA,
    output reg  [DATA_WIDTH-1:0]  PRDATA,
    output wire                   PREADY,
    output wire                   PSLVERR
);

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // ------------------------------------------------------------------------
    // Internal Registers
    // ------------------------------------------------------------------------
    reg [1:0]   alg_sel;
    reg         start_pulse;
    reg         decrypt_reg;

    reg [127:0] reg_key;
    reg [127:0] reg_nonce;
    reg [127:0] reg_ad;
    reg [127:0] reg_data_in;
    reg [127:0] reg_tag_in;

    // Cycle Counter Measurement Registers
    reg [31:0]  cycles_cur;
    reg [31:0]  cycles_last;
    reg         meas_active;

    // Output Signals from Active Core
    wire [127:0] core_data_out;
    wire [127:0] core_tag_out;
    wire         core_done;
    wire         core_valid;

    // ------------------------------------------------------------------------
    // Instantiate Custom Crypto Cores (Sample: Dummy Core Template)
    // ------------------------------------------------------------------------
    // Users can instantiate additional cores here and multiplex signals based on alg_sel
    dummy_crypto_core u_dummy_core (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .start    (start_pulse && (alg_sel == 2'b00)),
        .decrypt  (decrypt_reg),
        .key      (reg_key),
        .nonce    (reg_nonce),
        .ad       (reg_ad),
        .data_in  (reg_data_in),
        .tag_in   (reg_tag_in),
        .data_out (core_data_out),
        .tag_out  (core_tag_out),
        .done     (core_done),
        .valid    (core_valid)
    );

    // ------------------------------------------------------------------------
    // Cycle Counter Measurement Logic
    // ------------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            meas_active <= 1'b0;
            cycles_cur  <= 32'd0;
            cycles_last <= 32'd0;
        end else begin
            if (start_pulse) begin
                meas_active <= 1'b1;
                cycles_cur  <= 32'd0;
            end else if (meas_active) begin
                if (core_done) begin
                    meas_active <= 1'b0;
                    cycles_last <= cycles_cur + 1'b1;
                end else begin
                    cycles_cur <= cycles_cur + 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // APB Write Register Operations
    // ------------------------------------------------------------------------
    wire apb_write_strobe = PSEL && PENABLE && PWRITE;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            alg_sel     <= 2'b00;
            start_pulse <= 1'b0;
            decrypt_reg <= 1'b0;
            reg_key     <= 128'h0;
            reg_nonce   <= 128'h0;
            reg_ad      <= 128'h0;
            reg_data_in <= 128'h0;
            reg_tag_in  <= 128'h0;
        end else begin
            start_pulse <= 1'b0; // Pulse auto-cleared next cycle

            if (apb_write_strobe) begin
                case (PADDR[9:0])
                    10'h000: begin
                        alg_sel     <= PWDATA[1:0];
                        start_pulse <= PWDATA[2];
                        decrypt_reg <= PWDATA[3];
                    end
                    // Key [128-bit]
                    10'h004: reg_key[ 31:  0] <= PWDATA;
                    10'h008: reg_key[ 63: 32] <= PWDATA;
                    10'h00C: reg_key[ 95: 64] <= PWDATA;
                    10'h010: reg_key[127: 96] <= PWDATA;

                    // Nonce [128-bit]
                    10'h014: reg_nonce[ 31:  0] <= PWDATA;
                    10'h018: reg_nonce[ 63: 32] <= PWDATA;
                    10'h01C: reg_nonce[ 95: 64] <= PWDATA;
                    10'h020: reg_nonce[127: 96] <= PWDATA;

                    // AD [128-bit]
                    10'h024: reg_ad[ 31:  0] <= PWDATA;
                    10'h028: reg_ad[ 63: 32] <= PWDATA;
                    10'h02C: reg_ad[ 95: 64] <= PWDATA;
                    10'h030: reg_ad[127: 96] <= PWDATA;

                    // Data In [128-bit]
                    10'h034: reg_data_in[ 31:  0] <= PWDATA;
                    10'h038: reg_data_in[ 63: 32] <= PWDATA;
                    10'h03C: reg_data_in[ 95: 64] <= PWDATA;
                    10'h040: reg_data_in[127: 96] <= PWDATA;

                    // Tag In [128-bit]
                    10'h044: reg_tag_in[ 31:  0] <= PWDATA;
                    10'h048: reg_tag_in[ 63: 32] <= PWDATA;
                    10'h04C: reg_tag_in[ 95: 64] <= PWDATA;
                    10'h050: reg_tag_in[127: 96] <= PWDATA;

                    default: ;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // APB Read Mux Operations
    // ------------------------------------------------------------------------
    always @(*) begin
        case (PADDR[9:0])
            10'h000: PRDATA = {24'b0, core_valid, core_done, 2'b0, decrypt_reg, 1'b0, alg_sel};
            10'h004: PRDATA = reg_key[ 31:  0];
            10'h008: PRDATA = reg_key[ 63: 32];
            10'h00C: PRDATA = reg_key[ 95: 64];
            10'h010: PRDATA = reg_key[127: 96];

            10'h014: PRDATA = reg_nonce[ 31:  0];
            10'h018: PRDATA = reg_nonce[ 63: 32];
            10'h01C: PRDATA = reg_nonce[ 95: 64];
            10'h020: PRDATA = reg_nonce[127: 96];

            10'h034: PRDATA = reg_data_in[ 31:  0];
            10'h038: PRDATA = reg_data_in[ 63: 32];
            10'h03C: PRDATA = reg_data_in[ 95: 64];
            10'h040: PRDATA = reg_data_in[127: 96];

            // Read Data Out [128-bit]
            10'h080: PRDATA = core_data_out[ 31:  0];
            10'h084: PRDATA = core_data_out[ 63: 32];
            10'h088: PRDATA = core_data_out[ 95: 64];
            10'h08C: PRDATA = core_data_out[127: 96];

            // Read Tag Out [128-bit]
            10'h090: PRDATA = core_tag_out[ 31:  0];
            10'h094: PRDATA = core_tag_out[ 63: 32];
            10'h098: PRDATA = core_tag_out[ 95: 64];
            10'h09C: PRDATA = core_tag_out[127: 96];

            // Read Measurement Diagnostics
            10'h0A0: PRDATA = {29'b0, alg_sel, meas_active};
            10'h0A4: PRDATA = cycles_cur;
            10'h0A8: PRDATA = cycles_last;

            default: PRDATA = 32'h0;
        endcase
    end

endmodule
