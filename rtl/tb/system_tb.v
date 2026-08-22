`timescale 1 ns / 1 ps

module system_tb;
	reg clk = 1'b0;
	always #5 clk = ~clk;

	reg resetn_btn = 1'b0;
	reg [3:0] sw = 4'b0;
	reg [3:0] btn = 4'b0;
	reg uart_rx = 1'b1;
	reg sd_miso = 1'b1;

	wire trap;
	wire [7:0] out_byte;
	wire out_byte_en;
	wire uart_tx;
	wire sd_cs_n;
	wire sd_sck;
	wire sd_mosi;

	integer i;
	integer cycle_count = 0;

	system #(
		.UART_TX_HOLDOFF(16'd32),
		.UART_DEFAULT_DIV(10)
	) uut (
		.clk_100    (clk),
		.resetn_btn (resetn_btn),
		.trap       (trap),
		.out_byte   (out_byte),
		.out_byte_en(out_byte_en),
		.sw         (sw),
		.btn        (btn),
		.uart_tx    (uart_tx),
		.uart_rx    (uart_rx),
		.sd_cs_n    (sd_cs_n),
		.sd_sck     (sd_sck),
		.sd_mosi    (sd_mosi),
		.sd_miso    (sd_miso)
	);

	initial begin
		if ($test$plusargs("vcd")) begin
			$dumpfile("system.vcd");
			$dumpvars(0, system_tb);
		end

		#1;
		for (i = 0; i < 16; i = i + 1)
			uut.boot_mem[i] = 32'h0000_0013;
		uut.boot_mem[0] = 32'h0001_02b7; // lui t0, 0x10  -> 0x0001_0000
		uut.boot_mem[1] = 32'h0002_8067; // jalr x0, t0, 0
		$readmemh("sim_app.hex", uut.app_mem);

		repeat (100) @(posedge clk);
		resetn_btn <= 1'b1;
	end

	always @(posedge clk) begin
		cycle_count <= cycle_count + 1;

		if (cycle_count == 0 || (cycle_count % 1000000 == 0)) begin
			$display("[TB] cycle=%0d pc=0x%08x trap=%0b uart_we=%0b",
				cycle_count,
				uut.cpu.picorv32_core.reg_pc,
				trap,
				uut.uart_we);
		end

		if (uut.uart_we) begin
			$write("%c", uut.uart_tx_data);
			$fflush();
		end

		if (out_byte_en && out_byte == 8'hff) begin
			$display("\n[TB] PASS");
			$finish;
		end

		if (out_byte_en && out_byte == 8'h55) begin
			$display("\n[TB] FAIL");
			$fatal(1);
		end

		if (trap) begin
			$display("\n[TB] Unexpected CPU trap at cycle %0d", cycle_count);
			$fatal(1);
		end

		if (cycle_count > 20000000) begin
			$display("\n[TB] TIMEOUT after %0d cycles", cycle_count);
			$fatal(1);
		end
	end
endmodule

// ============================================================
// crypto_cluster_tb — directed APB-level test for the integrated
// ChaCha20-Poly1305 AEAD core (alg_sel == 2'b11). Self-checking,
// no CPU/firmware/SD needed. Drives crypto_cluster's APB slave the
// same way the firmware does (register index << 2).
//
// Golden vector (RFC 8439 IETF ChaCha20-Poly1305, single 16-byte
// data block + 16-byte AD) produced with Python's `cryptography`
// (ChaCha20Poly1305):
//   key   = 80..9f      nonce = 07 00 00 00 40 41 42 43 44 45 46 47
//   ad    = 50..5f      pt    = 10..1f
//   ct    = 8f6afb4e 15e856ad 0dfb95e0 2a9c14b1
//   tag   = b0ffff85 51dee0a6 9e8e2663 60232a04
//
// Run this module as the simulation top, e.g.:
//   iverilog -o cc_tb system_tb.v crypto_cluster.v \
//            ../../picosoc/poly_chaha/chacha20_poly1305_core.v \
//            ../../picosoc/poly_chaha/chacha/chacha_core.v \
//            ../../picosoc/poly_chaha/chacha/chacha_qr.v \
//            ../../picosoc/poly_chaha/poly1305/poly1305_core.v \
//            ../../picosoc/poly_chaha/poly1305/poly1305_final.v \
//            ../../picosoc/poly_chaha/poly1305/poly1305_mulacc.v \
//            ../../picosoc/poly_chaha/poly1305/poly1305_pblock.v \
//            ../../picosoc/tinyjambu/*.v ../../picosoc/Xoodyak_old/*.v \
//            ../../picosoc/GIFT_COFB/*.v -s crypto_cluster_tb
// ============================================================
module crypto_cluster_tb;
	reg         PCLK = 1'b0;
	reg         PRESETn = 1'b0;
	reg  [11:0] PADDR = 12'h0;
	reg         PSEL = 1'b0;
	reg         PENABLE = 1'b0;
	reg         PWRITE = 1'b0;
	reg  [31:0] PWDATA = 32'h0;
	wire [31:0] PRDATA;
	wire        PREADY;
	wire        PSLVERR;

	integer i;
	integer errors = 0;
	reg [31:0] rd;

	always #5 PCLK = ~PCLK;

	crypto_cluster dut (
		.PCLK(PCLK), .PRESETn(PRESETn),
		.PADDR(PADDR), .PSEL(PSEL), .PENABLE(PENABLE),
		.PWRITE(PWRITE), .PWDATA(PWDATA),
		.PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR)
	);

	// AEAD shared register: word index -> byte address (idx << 2)
	function [11:0] aw; input [7:0] idx; aw = idx << 2; endfunction

	task apb_write(input [11:0] addr, input [31:0] data);
		begin
			@(posedge PCLK);
			PADDR <= addr; PWDATA <= data; PWRITE <= 1'b1;
			PSEL <= 1'b1; PENABLE <= 1'b0;
			@(posedge PCLK);
			PENABLE <= 1'b1;
			@(posedge PCLK);
			while (!PREADY) @(posedge PCLK);
			PSEL <= 1'b0; PENABLE <= 1'b0; PWRITE <= 1'b0;
		end
	endtask

	task apb_read(input [11:0] addr, output [31:0] data);
		begin
			@(posedge PCLK);
			PADDR <= addr; PWRITE <= 1'b0;
			PSEL <= 1'b1; PENABLE <= 1'b0;
			@(posedge PCLK);
			PENABLE <= 1'b1;
			@(posedge PCLK);
			while (!PREADY) @(posedge PCLK);
			data = PRDATA;
			PSEL <= 1'b0; PENABLE <= 1'b0;
		end
	endtask

	// Poll ctrl reg (word 0x00) bit6 (sticky done) with a bounded loop.
	task apb_poll_done;
		integer k;
		reg [31:0] s;
		begin
			s = 32'h0; k = 0;
			while (!(s & 32'h40) && (k < 4000)) begin
				apb_read(aw(8'h00), s);
				k = k + 1;
			end
			if (!(s & 32'h40)) begin
				$display("[crypto_tb] TIMEOUT waiting for AEAD done");
				errors = errors + 1;
			end
		end
	endtask

	// Golden vector (words in cluster order: word0 = bits[31:0], byte0 = MSB)
	reg [31:0] k_lo  [0:3];   // key[127:0]   -> words 0x01..0x04
	reg [31:0] k_hi  [0:3];   // key[255:128] -> words 0x1A..0x1D
	reg [31:0] nonce [0:2];   // 96-bit nonce -> words 0x05..0x07
	reg [31:0] adw   [0:3];   // AD block     -> words 0x09..0x0C
	reg [31:0] ptw   [0:3];   // plaintext    -> words 0x0D..0x10
	reg [31:0] ctw   [0:3];   // expected ciphertext (read 0x20..0x23)
	reg [31:0] tagw  [0:3];   // expected tag        (read 0x24..0x27)
	reg [31:0] outw  [0:3];
	reg [31:0] st;
	integer e;

	initial begin : main_test
		if ($test$plusargs("vcd")) begin
			$dumpfile("crypto_cluster_tb.vcd");
			$dumpvars(0, crypto_cluster_tb);
		end

		k_lo[0]=32'h80818283; k_lo[1]=32'h84858687; k_lo[2]=32'h88898a8b; k_lo[3]=32'h8c8d8e8f;
		k_hi[0]=32'h90919293; k_hi[1]=32'h94959697; k_hi[2]=32'h98999a9b; k_hi[3]=32'h9c9d9e9f;
		nonce[0]=32'h07000000; nonce[1]=32'h40414243; nonce[2]=32'h44454647;
		adw[0]=32'h50515253; adw[1]=32'h54555657; adw[2]=32'h58595a5b; adw[3]=32'h5c5d5e5f;
		ptw[0]=32'h10111213; ptw[1]=32'h14151617; ptw[2]=32'h18191a1b; ptw[3]=32'h1c1d1e1f;
		ctw[0]=32'h8f6afb4e; ctw[1]=32'h15e856ad; ctw[2]=32'h0dfb95e0; ctw[3]=32'h2a9c14b1;
		tagw[0]=32'hb0ffff85; tagw[1]=32'h51dee0a6; tagw[2]=32'h9e8e2663; tagw[3]=32'h60232a04;

		PRESETn = 1'b0;
		repeat (8) @(posedge PCLK);
		PRESETn = 1'b1;
		repeat (4) @(posedge PCLK);

		// ---------- helper: load common inputs ----------
		for (i = 0; i < 4; i = i + 1) apb_write(aw(8'h01 + i[7:0]), k_lo[i]);  // key[127:0]
		for (i = 0; i < 4; i = i + 1) apb_write(aw(8'h1A + i[7:0]), k_hi[i]);  // key[255:128]
		for (i = 0; i < 3; i = i + 1) apb_write(aw(8'h05 + i[7:0]), nonce[i]); // nonce
		for (i = 0; i < 4; i = i + 1) apb_write(aw(8'h09 + i[7:0]), adw[i]);   // AD
		apb_write(aw(8'h15), 32'h10);   // ad_len   = 16
		apb_write(aw(8'h16), 32'h10);   // data_len = 16

		// ================= ENCRYPT =================
		for (i = 0; i < 4; i = i + 1) apb_write(aw(8'h0D + i[7:0]), ptw[i]);   // plaintext
		apb_write(aw(8'h00), 32'h07);   // alg_sel=11, start, decrypt=0
		apb_poll_done;

		e = 0;
		for (i = 0; i < 4; i = i + 1) begin
			apb_read(aw(8'h20 + i[7:0]), outw[i]);
			if (outw[i] !== ctw[i]) begin
				$display("[crypto_tb] enc CT word %0d: got %08x exp %08x", i, outw[i], ctw[i]);
				e = e + 1;
			end
		end
		for (i = 0; i < 4; i = i + 1) begin
			apb_read(aw(8'h24 + i[7:0]), outw[i]);
			if (outw[i] !== tagw[i]) begin
				$display("[crypto_tb] enc TAG word %0d: got %08x exp %08x", i, outw[i], tagw[i]);
				e = e + 1;
			end
		end
		apb_read(aw(8'h00), st);
		if (!(st & 32'h80)) begin $display("[crypto_tb] enc valid flag not set"); e = e + 1; end
		$display("[crypto_tb] ChaCha20-Poly1305 ENCRYPT     : %s", (e == 0) ? "PASS" : "FAIL");
		errors = errors + e;

		// ================= DECRYPT + VERIFY =================
		for (i = 0; i < 4; i = i + 1) apb_write(aw(8'h0D + i[7:0]), ctw[i]);   // ciphertext in
		for (i = 0; i < 4; i = i + 1) apb_write(aw(8'h11 + i[7:0]), tagw[i]);  // expected tag
		apb_write(aw(8'h00), 32'h0F);   // alg_sel=11, start, decrypt=1
		apb_poll_done;

		e = 0;
		for (i = 0; i < 4; i = i + 1) begin
			apb_read(aw(8'h20 + i[7:0]), outw[i]);
			if (outw[i] !== ptw[i]) begin
				$display("[crypto_tb] dec PT word %0d: got %08x exp %08x", i, outw[i], ptw[i]);
				e = e + 1;
			end
		end
		apb_read(aw(8'h00), st);
		if (!(st & 32'h80)) begin $display("[crypto_tb] dec tag verify FAILED (valid=0)"); e = e + 1; end
		$display("[crypto_tb] ChaCha20-Poly1305 DECRYPT     : %s", (e == 0) ? "PASS" : "FAIL");
		errors = errors + e;

		$display("[crypto_tb] ===== %s (errors=%0d) =====",
			(errors == 0) ? "ALL PASS" : "SOME FAILED", errors);
		$finish;
	end

	// Global watchdog so a stuck core cannot hang the sim forever.
	initial begin
		#5000000;
		$display("[crypto_tb] GLOBAL TIMEOUT");
		$fatal(1);
	end
endmodule

// ============================================================
// Simulation-only model of the Xilinx BUFG global clock buffer.
// This file is never read by synth_system.tcl, so synthesis
// still uses the real unisim primitive.
// ============================================================
module BUFG (input I, output O);
	assign O = I;
endmodule
