`timescale 1ns / 1ps
// ============================================================================
// aead_mmap_wrapper.v — APB Pass-through Wrapper around crypto_cluster
// ============================================================================
// Preserves hierarchy: system (SoC Top) -> wrapper -> crypto_cluster -> cores
// ============================================================================

module aead_mmap_wrapper (
    input  wire        clk,
    input  wire        rst_n,

    // APB slave interface
    input  wire [11:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr
);

    crypto_cluster u_cluster (
        .PCLK    (clk),
        .PRESETn (rst_n),
        .PADDR   (paddr),
        .PSEL    (psel),
        .PENABLE (penable),
        .PWRITE  (pwrite),
        .PWDATA  (pwdata),
        .PRDATA  (prdata),
        .PREADY  (pready),
        .PSLVERR (pslverr)
    );

endmodule
