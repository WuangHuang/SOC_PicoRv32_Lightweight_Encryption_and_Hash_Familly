#ifndef FIRMWARE_H
#define FIRMWARE_H

#include <stdint.h>
#include <stdbool.h>

// ============================================================================
// PicoRV32 SoC Memory Map Definitions
// ============================================================================
#define reg_spictrl      (*(volatile uint32_t*)0x02000000)
#define reg_uart_clkdiv  (*(volatile uint32_t*)0x10000010)
#define reg_uart_data    (*(volatile uint32_t*)0x10000004)
#define reg_uart_status  (*(volatile uint32_t*)0x1000000C)
#define reg_leds         (*(volatile uint32_t*)0x10000000)
#define reg_btn          (*(volatile uint32_t*)0x20000004)

// ============================================================================
// APB Extensible Crypto Register Map (Base: 0x30000000)
// ============================================================================
#define CRYPTO_BASE      0x30000000

#define reg_crypto_ctrl     (*(volatile uint32_t*)(CRYPTO_BASE + 0x00))

// Key Word 0-3 (128-bit)
#define reg_crypto_key0     (*(volatile uint32_t*)(CRYPTO_BASE + 0x04))
#define reg_crypto_key1     (*(volatile uint32_t*)(CRYPTO_BASE + 0x08))
#define reg_crypto_key2     (*(volatile uint32_t*)(CRYPTO_BASE + 0x0C))
#define reg_crypto_key3     (*(volatile uint32_t*)(CRYPTO_BASE + 0x10))

// Nonce Word 0-3 (128-bit)
#define reg_crypto_nonce0   (*(volatile uint32_t*)(CRYPTO_BASE + 0x14))
#define reg_crypto_nonce1   (*(volatile uint32_t*)(CRYPTO_BASE + 0x18))
#define reg_crypto_nonce2   (*(volatile uint32_t*)(CRYPTO_BASE + 0x1C))
#define reg_crypto_nonce3   (*(volatile uint32_t*)(CRYPTO_BASE + 0x20))

// Associated Data Word 0-3 (128-bit)
#define reg_crypto_ad0      (*(volatile uint32_t*)(CRYPTO_BASE + 0x24))
#define reg_crypto_ad1      (*(volatile uint32_t*)(CRYPTO_BASE + 0x28))
#define reg_crypto_ad2      (*(volatile uint32_t*)(CRYPTO_BASE + 0x2C))
#define reg_crypto_ad3      (*(volatile uint32_t*)(CRYPTO_BASE + 0x30))

// Data In Word 0-3 (128-bit)
#define reg_crypto_datain0  (*(volatile uint32_t*)(CRYPTO_BASE + 0x34))
#define reg_crypto_datain1  (*(volatile uint32_t*)(CRYPTO_BASE + 0x38))
#define reg_crypto_datain2  (*(volatile uint32_t*)(CRYPTO_BASE + 0x3C))
#define reg_crypto_datain3  (*(volatile uint32_t*)(CRYPTO_BASE + 0x40))

// Data Out Word 0-3 (128-bit Read-Only)
#define reg_crypto_dataout0 (*(volatile uint32_t*)(CRYPTO_BASE + 0x80))
#define reg_crypto_dataout1 (*(volatile uint32_t*)(CRYPTO_BASE + 0x84))
#define reg_crypto_dataout2 (*(volatile uint32_t*)(CRYPTO_BASE + 0x88))
#define reg_crypto_dataout3 (*(volatile uint32_t*)(CRYPTO_BASE + 0x8C))

// Tag Out Word 0-3 (128-bit Read-Only)
#define reg_crypto_tagout0  (*(volatile uint32_t*)(CRYPTO_BASE + 0x90))
#define reg_crypto_tagout1  (*(volatile uint32_t*)(CRYPTO_BASE + 0x94))
#define reg_crypto_tagout2  (*(volatile uint32_t*)(CRYPTO_BASE + 0x98))
#define reg_crypto_tagout3  (*(volatile uint32_t*)(CRYPTO_BASE + 0x9C))

// Diagnostics
#define reg_crypto_status   (*(volatile uint32_t*)(CRYPTO_BASE + 0xA0))
#define reg_crypto_cycles   (*(volatile uint32_t*)(CRYPTO_BASE + 0xA8))

// Algorithm IDs
#define ALG_LICI           0
#define ALG_PICCOLO        1
#define ALG_KLEIN          2

// UART Print Drivers
void print_chr(char ch);
void print_str(const char *p);
void print_dec(unsigned int val);
void print_hex(unsigned int val, int digits);

// Crypto Driver Example
void test_dummy_crypto(void);

#endif // FIRMWARE_H
