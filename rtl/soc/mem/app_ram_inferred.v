// ============================================================
// app_ram — application RAM, INFERRED implementation
// ============================================================
// Technology-neutral port list.  To port to an ASIC, add a sibling file
// (app_ram_<tech>.v) with the SAME module name and ports wrapping that
// technology's SRAM macro, and swap which file the build script reads.
// system.v does not change.
//
// Timing contract every implementation must honour:
//   * write : synchronous, byte enables, no read-back
//   * read  : synchronous, data valid on the cycle AFTER `re`
// The AXI slave in system.v is built around exactly that one-cycle read
// latency, so a swapped-in macro must match it or the slave needs a
// pipeline stage.
//
// Why this is a separate module at all: on FPGA the array below infers a
// Block RAM, but an ASIC has no such primitive -- 8192 x 32 = 256 Kbit as
// flip-flops would be ~262 000 FFs against a whole-design budget of about
// 13 000.  Keeping the array behind this boundary means system.v itself
// contains nothing technology-specific.
// ============================================================

module app_ram #(
    parameter WORDS = 8192          // 32 KB
)(
    input  wire        clk,

    // Write port (byte enables)
    input  wire        we,          // write strobe for this cycle
    input  wire [3:0]  wstrb,       // per-byte enable
    input  wire [31:0] waddr,       // word address
    input  wire [31:0] wdata,

    // Read port (synchronous, 1-cycle latency)
    input  wire        re,
    input  wire [31:0] raddr,       // word address
    output reg  [31:0] rdata
);

    reg [31:0] mem [0:WORDS-1];

    always @(posedge clk) begin
        if (we) begin
            // Bare byte-enables on purpose -- see the note in system.v.
            // An `else mem[a][x] <= mem[a][x]` would make the write depend on
            // a same-cycle read of the array and destroy RAM inference.
            if (wstrb[0]) mem[waddr][ 7: 0] <= wdata[ 7: 0];  // lint_no_else_ok: byte-enable
            if (wstrb[1]) mem[waddr][15: 8] <= wdata[15: 8];  // lint_no_else_ok: byte-enable
            if (wstrb[2]) mem[waddr][23:16] <= wdata[23:16];  // lint_no_else_ok: byte-enable
            if (wstrb[3]) mem[waddr][31:24] <= wdata[31:24];  // lint_no_else_ok: byte-enable
        end else begin
            // no write this cycle
        end

        if (re)
            rdata <= mem[raddr];
        else
            rdata <= rdata;
    end

endmodule
