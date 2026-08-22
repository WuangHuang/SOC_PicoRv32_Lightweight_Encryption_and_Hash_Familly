# Custom Crypto Core Integration Guide

This guide provides step-by-step instructions for defining and connecting custom hardware encryption/AEAD cores (e.g., AES-128, Present, ASCON, SM4, SPECK, etc.) into the PicoRV32 SoC system via the APB bus interface.

---

## 1. APB Crypto Architecture Hierarchy

The cryptographic accelerator subsystem is organized into 3 hierarchical layers:
```
System SoC Top (system.v)
  └── APB Bridge / Interconnect (0x3000_0000)
        └── aead_mmap_wrapper.v
              └── crypto_cluster.v (APB Register Management & Muxing)
                    ├── dummy_crypto_core.v (Sample Template Core)
                    └── my_custom_crypto_core.v (Your Custom Hardware Core)
```

---

## 2. Step 1: Create a New Verilog Crypto Module

Create `my_custom_crypto_core.v` in `rtl/crypto/` with standard interface ports:

```verilog
module my_custom_crypto_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,        // 1-cycle start pulse from APB
    input  wire         decrypt,      // 0 = Encrypt, 1 = Decrypt
    input  wire [127:0] key,          // 128-bit Encryption Key
    input  wire [127:0] nonce,        // 128-bit Nonce / Initialization Vector
    input  wire [127:0] ad,           // 128-bit Associated Data
    input  wire [127:0] data_in,      // 128-bit Input Data Block
    input  wire [127:0] tag_in,       // 128-bit Expected Tag (for Decryption)
    output reg  [127:0] data_out,     // 128-bit Output Result
    output reg  [127:0] tag_out,      // 128-bit Output Tag / MAC
    output reg          done,         // 1-cycle completion pulse
    output reg          valid         // Output valid status flag
);

    // Custom algorithm logic implementation...

endmodule
```

---

## 3. Step 2: Integrate into `crypto_cluster.v`

Open `rtl/crypto/crypto_cluster.v` and complete two steps:

### A. Instantiate the New Core:
```verilog
    wire [127:0] custom_data_out;
    wire [127:0] custom_tag_out;
    wire         custom_done;
    wire         custom_valid;

    my_custom_crypto_core u_my_custom_core (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .start    (start_pulse && (alg_sel == 2'b01)), // Assigned alg_sel ID = 01
        .decrypt  (decrypt_reg),
        .key      (reg_key),
        .nonce    (reg_nonce),
        .ad       (reg_ad),
        .data_in  (reg_data_in),
        .tag_in   (reg_tag_in),
        .data_out (custom_data_out),
        .tag_out  (custom_tag_out),
        .done     (custom_done),
        .valid    (custom_valid)
    );
```

### B. Multiplex Output Signals based on `alg_sel`:
Update the output multiplexers for `core_data_out`, `core_tag_out`, `core_done`, and `core_valid`:
```verilog
    assign core_data_out = (alg_sel == 2'b01) ? custom_data_out : dummy_data_out;
    assign core_tag_out  = (alg_sel == 2'b01) ? custom_tag_out  : dummy_tag_out;
    assign core_done     = (alg_sel == 2'b01) ? custom_done     : dummy_done;
    assign core_valid    = (alg_sel == 2'b01) ? custom_valid    : dummy_valid;
```

---

## 4. Step 3: Update Firmware Driver in C

In the `firmware/` directory:

1. Define the algorithm ID macro in `firmware.h`:
   ```c
   #define ALG_DUMMY       0
   #define ALG_MY_CUSTOM   1
   ```

2. Implement the driver function in `firmware.c`:
   ```c
   void run_my_custom_crypto(const uint32_t *key, const uint32_t *nonce, 
                            const uint32_t *pt, uint32_t *ct) {
       // 1. Write Key, Nonce, Data In into APB registers
       // 2. Set alg_sel = ALG_MY_CUSTOM and trigger the start pulse
       // 3. Wait until done flag == 1
       // 4. Read data result from DATA_OUT registers
   }
   ```

---

## 5. APB Register Map (Base `0x3000_0000`)

| Relative Offset | Register Name | Access | Description |
|---|---|---|---|
| `0x3000_0000` | `CTRL` | R/W | `[1:0]` alg_sel, `[2]` start pulse, `[3]` decrypt, `[6]` done, `[7]` valid |
| `0x3000_0004` - `0x3000_0010` | `KEY` | R/W | 128-bit Key (Words 1–4) |
| `0x3000_0014` - `0x3000_0020` | `NONCE` | R/W | 128-bit Nonce (Words 5–8) |
| `0x3000_0024` - `0x3000_0030` | `AD` | R/W | 128-bit Associated Data (Words 9–12) |
| `0x3000_0034` - `0x3000_0040` | `DATA_IN` | R/W | 128-bit Plaintext / Ciphertext Input |
| `0x3000_0080` - `0x3000_008C` | `DATA_OUT` | RO | 128-bit Data Output |
| `0x3000_0090` - `0x3000_009C` | `TAG_OUT` | RO | 128-bit Tag Output |
| `0x3000_00A4` | `CYCLES_CUR` | RO | Active cycle counter of running algorithm |
| `0x3000_00A8` | `CYCLES_LAST` | RO | Cycle count measured from last execution |
