#include "firmware.h"

// ----------------------------------------------------------------------------
// UART Basic Helper Functions
// ----------------------------------------------------------------------------
void print_chr(char ch) {
    *((volatile uint32_t*)0x10000004) = ch;
}

void print_str(const char *p) {
    while (*p) {
        print_chr(*p++);
    }
}

void print_hex(unsigned int val, int digits) {
    for (int i = (digits - 1) * 4; i >= 0; i -= 4) {
        int digit = (val >> i) & 0xF;
        print_chr("0123456789ABCDEF"[digit]);
    }
}

void print_dec(unsigned int val) {
    char buffer[10];
    char *p = buffer;
    while (val || p == buffer) {
        *(p++) = '0' + (val % 10);
        val /= 10;
    }
    while (p != buffer) {
        print_chr(*(--p));
    }
}

// ----------------------------------------------------------------------------
// Crypto Driver Function Example
// ----------------------------------------------------------------------------
void test_dummy_crypto(void) {
    print_str("\r\n========================================\r\n");
    print_str("   PicoRV32 SoC — Custom Crypto Test   \r\n");
    print_str("========================================\r\n");

    // 1. Set Input Key, Nonce, AD, Data In
    reg_crypto_key0 = 0x01234567;
    reg_crypto_key1 = 0x89ABCDEF;
    reg_crypto_key2 = 0x11223344;
    reg_crypto_key3 = 0x55667788;

    reg_crypto_nonce0 = 0xAABBCCDD;
    reg_crypto_nonce1 = 0x11223344;
    reg_crypto_nonce2 = 0x55667788;
    reg_crypto_nonce3 = 0x9900AABB;

    reg_crypto_ad0 = 0x00112233;
    reg_crypto_ad1 = 0x44556677;
    reg_crypto_ad2 = 0x8899AABB;
    reg_crypto_ad3 = 0xCCDDEEFF;

    reg_crypto_datain0 = 0xCAFEBABE;
    reg_crypto_datain1 = 0xDEADBEEF;
    reg_crypto_datain2 = 0x01234567;
    reg_crypto_datain3 = 0x89ABCDEF;

    // 2. Select ALG_DUMMY (0) and Trigger Start Pulse (bit 2)
    // ctrl = [alg_sel:00][start:1][decrypt:0] -> 0x04
    reg_crypto_ctrl = (ALG_DUMMY & 0x03) | (1 << 2);

    print_str("[INFO] Triggered Encryption Start Pulse...\r\n");

    // 3. Wait for Done flag (bit 6 of ctrl)
    while (!(reg_crypto_ctrl & (1 << 6)));

    print_str("[SUCCESS] Core Execution Completed!\r\n");

    // 4. Read Output Data & Tag
    print_str("Data Out [0-3] : 0x");
    print_hex(reg_crypto_dataout3, 8);
    print_hex(reg_crypto_dataout2, 8);
    print_hex(reg_crypto_dataout1, 8);
    print_hex(reg_crypto_dataout0, 8);
    print_str("\r\n");

    print_str("Tag Out  [0-3] : 0x");
    print_hex(reg_crypto_tagout3, 8);
    print_hex(reg_crypto_tagout2, 8);
    print_hex(reg_crypto_tagout1, 8);
    print_hex(reg_crypto_tagout0, 8);
    print_str("\r\n");

    print_str("Cycles Taken   : ");
    print_dec(reg_crypto_cycles);
    print_str(" clock cycles\r\n");
    print_str("========================================\r\n");
}

// ----------------------------------------------------------------------------
// Main Application Entry
// ----------------------------------------------------------------------------
void main(void) {
    // Initialize UART Baud Rate (115200 at 100MHz clock)
    reg_uart_clkdiv = 868;

    test_dummy_crypto();

    while (1) {
        // Main loop
    }
}
