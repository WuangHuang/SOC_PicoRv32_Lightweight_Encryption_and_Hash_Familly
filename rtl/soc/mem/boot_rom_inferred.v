// ============================================================
// boot_rom — 4 KB boot ROM, INFERRED implementation
// ============================================================
// Technology-neutral port list.  To port to an ASIC, add a sibling file
// (boot_rom_<tech>.v) with the SAME module name and ports, and swap which
// file the build script reads.  system.v does not change.
//
// Timing contract: synchronous read, data valid the cycle AFTER `re`.
//
// THE ASIC PROBLEM lives here, isolated to this one file.  On FPGA the
// $readmemh below is picked up by the synthesiser and becomes the Block
// RAM's INIT attribute -- that is the standard, and only, way to get the
// bootloader into the FPGA image.  An ASIC has no equivalent: flops and
// SRAM macros power up undefined.  A ROHM 180 implementation must instead
// do one of:
//
//   a) instantiate a mask ROM generated from bootloader.hex, or
//   b) instantiate an SRAM macro and load it over SPI/JTAG before
//      releasing the CPU from reset, or
//   c) hard-code the boot code as a synthesisable case statement
//      (fine at 4 KB, and fully technology-neutral).
//
// Option (c) is the least tooling-dependent and is what a portable
// tapeout usually does; bootloader.hex can be converted mechanically.
// ============================================================

module boot_rom #(
    parameter WORDS    = 1024,                  // 4 KB
    parameter INIT_HEX = "bootloader.hex"
)(
    input  wire        clk,
    input  wire        re,
    input  wire [31:0] raddr,                   // word address
    output reg  [31:0] rdata
);

    reg [31:0] mem [0:WORDS-1];

    // FPGA-only preload.  Vivado infers BRAM INIT from this; it is NOT
    // synthesisable in an ASIC flow, which is why the ASIC variant of this
    // module is a separate file rather than an `ifdef in this one.
    initial $readmemh(INIT_HEX, mem);

    always @(posedge clk) begin
        if (re)
            rdata <= mem[raddr];
        else
            rdata <= rdata;
    end

endmodule
