// ============================================================
// sd_card_model — behavioural SPI-mode SD card, simulation only
// ============================================================
// Not RTL, not synthesisable, not part of any build the rest of this repo
// reads (Makefile SIM_RTL / synth_system.tcl / build.tcl / OpenLane
// configs). Only rtl/tb/system_tb.v's `ifdef SIM_ROHM path instantiates
// this, to exercise the REAL boot path (bootloader.c reading the card
// over rtl/peripherals/simple_spi_master.v) against the ROHM RAM wrappers,
// instead of the inferred-flow's backdoor $readmemh straight into App RAM.
//
// Implements exactly the command sequence firmware/bootloader.c issues --
// no more of the SD spec than that. Traced directly from bootloader.c:
//   sd_poweron -> CMD0 -> CMD8 -> (CMD55+CMD41)* -> CMD58 -> CMD16
//   -> [CMD17 per sector, from sector 2048 onward]
// CRC bytes are captured but never checked: the card is never taken out of
// its default SPI-mode "CRC off" state (CMD59 is never sent), matching
// real SD behaviour, so bootloader.c's fixed CRC bytes (0x95, 0x87, ...)
// don't need to be validated or even recomputed here.
//
// Electrical/timing model: pure SPI mode 0 (CPOL=0, CPHA=0), slave role,
// entirely edge-triggered off `sck`/`cs_n` -- deliberately has NO `clk`
// port, exactly like a real card has no knowledge of the host SoC's
// system clock. Sampled against rtl/peripherals/simple_spi_master.v's
// actual behaviour (traced from its source): MOSI is driven stable
// through each SCK-low phase and changes on SCK's falling edge; MISO must
// be valid before each SCK rising edge. This model mirrors that: capture
// on posedge sck, drive on negedge sck.
//
// Byte-frame indexing per CS-low session (frame_idx, 0-based, matches
// exactly what bootloader.c's spi_xfer() call sequence produces):
//   0       leading dummy byte (sd_dummy() right after cs_lo())
//   1       command byte (0x40 | index)
//   2..5    4-byte argument, MSB first
//   6       CRC byte (captured, ignored)
//   7..     response phase -- see resp_byte() below
// The model answers at frame 7 (Ncr = 0 dummy-byte gap after the command
// frame), which is spec-legal and keeps every wait loop in bootloader.c
// (up to 1000 polls for R1, up to 100000 for the CMD17 data token) exiting
// on its very first iteration.
// ============================================================

module sd_card_model #(
    parameter IMG_FILE    = "sim_sd.hex", // one hex BYTE per line ($readmemh)
    parameter IMG_BYTES   = 32768,        // capacity backing `image`; see gen_sim_sd_hex.py
    parameter BASE_SECTOR = 2048          // matches firmware/bootloader.c APP_START_SECTOR
)(
    input  wire sck,
    input  wire mosi,
    input  wire cs_n,
    output reg  miso
);

    reg [7:0] image [0:IMG_BYTES-1];
    integer   k;
    initial begin
        for (k = 0; k < IMG_BYTES; k = k + 1)
            image[k] = 8'h00;
        $readmemh(IMG_FILE, image);
    end

    // ---- frame/bit bookkeeping ----
    reg [15:0] frame_idx;   // index of the byte transfer currently starting/in flight
    reg [2:0]  bit_idx;     // 7 downto 0, MSB-first position within the current byte
    reg [7:0]  cmd_byte;    // latched at start of command
    reg [31:0] arg_reg;     // latched (MSB-first) across 4 argument bytes
    reg [7:0]  shift_in;    // MOSI capture shift register
    reg [7:0]  tx_shift;    // MISO drive shift register
    reg        cmd_captured;
    reg [2:0]  arg_count;

    wire [7:0] shift_in_next = {shift_in[6:0], mosi};

    // ---- response byte for a given (about-to-start) frame index ----
    // R1/R7/R3 layouts and values traced directly from bootloader.c's
    // checks (see the field-by-field comments below); CMD17's data phase
    // serves the loaded image starting at byte (arg_reg-BASE_SECTOR)*512.
    function [7:0] resp_byte;
        input [15:0] fidx;
        reg   [15:0] p;          // poll index = fidx - 7, valid once fidx >= 7
        reg   [31:0] byte_addr;
        begin
            p = fidx - 16'd7;
            if (fidx < 16'd7) begin
                resp_byte = 8'hFF;                       // command/arg/crc phase: line idle
            end else begin
                case (cmd_byte)
                    8'h40: // CMD0 (GO_IDLE_STATE) -> R1 = 0x01 (idle)
                        resp_byte = (p == 16'd0) ? 8'h01 : 8'hFF;

                    8'h48: // CMD8 (SEND_IF_COND) -> R7 = R1, rsvd, rsvd, voltage[3:0], echo
                        case (p)
                            16'd0: resp_byte = 8'h01;
                            16'd1: resp_byte = 8'h00;
                            16'd2: resp_byte = 8'h00;
                            16'd3: resp_byte = 8'h01;    // voltage window: 2.7-3.6V accepted
                            16'd4: resp_byte = 8'hAA;    // echo of CMD8's check pattern
                            default: resp_byte = 8'hFF;
                        endcase

                    8'h77: // CMD55 (APP_CMD) -> R1, value unchecked by bootloader.c
                        resp_byte = (p == 16'd0) ? 8'h01 : 8'hFF;

                    8'h69: // ACMD41 (SD_SEND_OP_COND) -> R1 = 0x00 (ready) immediately;
                           // real cards may answer 0x01 (still initialising) for a while,
                           // bootloader.c retries CMD55+ACMD41 on that -- this model always
                           // reports ready on the first attempt to keep sim time short.
                        resp_byte = (p == 16'd0) ? 8'h00 : 8'hFF;

                    8'h7A: // CMD58 (READ_OCR) -> R3 = R1, OCR[31:24..0:7]
                        case (p)
                            16'd0: resp_byte = 8'h00;
                            16'd1: resp_byte = 8'hC0;    // power-up done(bit7) + CCS/SDHC(bit6)
                            16'd2: resp_byte = 8'hFF;
                            16'd3: resp_byte = 8'h80;
                            16'd4: resp_byte = 8'h00;
                            default: resp_byte = 8'hFF;
                        endcase

                    8'h50: // CMD16 (SET_BLOCKLEN) -> R1, result not gated by bootloader.c
                        resp_byte = (p == 16'd0) ? 8'h00 : 8'hFF;

                    8'h51: begin // CMD17 (READ_SINGLE_BLOCK) -> R1, token, 512B, 2 CRC bytes
                        if (p == 16'd0) begin
                            resp_byte = 8'h00;                          // R1: read accepted
                        end else if (p == 16'd1) begin
                            resp_byte = 8'hFE;                          // data-start token
                        end else if (p >= 16'd2 && p <= 16'd513) begin
                            if (arg_reg >= BASE_SECTOR) begin
                                byte_addr = (arg_reg - BASE_SECTOR) * 32'd512 + (p - 16'd2);
                                resp_byte = (byte_addr < IMG_BYTES) ? image[byte_addr] : 8'h00;
                            end else begin
                                if (p == 16'd512) resp_byte = 8'h55;
                                else if (p == 16'd513) resp_byte = 8'hAA;
                                else resp_byte = 8'h00;   // sector before the loaded image served as dummy MBR
                            end
                        end else begin
                            resp_byte = 8'hFF;                          // 2 CRC bytes, unchecked
                        end
                    end

                    default: resp_byte = 8'hFF;   // command never captured (idle line)
                endcase
            end
        end
    endfunction

    // ---- capture: sample MOSI on the rising edge, advance frame state ----
    always @(posedge sck) begin
        if (!cs_n) begin
            shift_in <= shift_in_next;
            if (bit_idx == 3'd0) begin
                bit_idx <= 3'd7;
                if (!cmd_captured) begin
                    if (shift_in_next != 8'hFF) begin
                        cmd_byte     <= shift_in_next;
                        cmd_captured <= 1'b1;
                        arg_count    <= 3'd0;
                        frame_idx    <= 16'd2; // next byte is arg[31:24]
                    end
                end else begin
                    if (arg_count < 3'd4) begin
                        arg_reg   <= {arg_reg[23:0], shift_in_next};
                        arg_count <= arg_count + 3'd1;
                    end
                    frame_idx <= frame_idx + 16'd1;
                end
            end else begin
                bit_idx <= bit_idx - 3'd1;
            end
        end
    end

    // ---- drive: present MISO stable through the falling edge ----
    // At a byte boundary (bit_idx == 7, meaning the preceding posedge just
    // completed a byte and already advanced frame_idx) reload from
    // resp_byte(frame_idx) and present its MSB; otherwise shift the
    // in-flight byte left by one and present the next bit.
    always @(negedge sck) begin : drive_miso
        reg [7:0] next_byte;
        if (!cs_n) begin
            if (bit_idx == 3'd7) begin
                next_byte = resp_byte(frame_idx);
                tx_shift <= next_byte;
                miso     <= next_byte[7];
            end else begin
                tx_shift <= {tx_shift[6:0], 1'b1};
                miso     <= tx_shift[6];
            end
        end
    end

    // ---- CS assertion: reset frame state, present the idle byte's MSB ----
    always @(negedge cs_n) begin
        bit_idx      <= 3'd7;
        frame_idx    <= 16'd0;
        cmd_byte     <= 8'h00;
        arg_reg      <= 32'h0;
        cmd_captured <= 1'b0;
        arg_count    <= 3'd0;
        tx_shift     <= 8'hFF;
        miso         <= 1'b1;
    end

endmodule
