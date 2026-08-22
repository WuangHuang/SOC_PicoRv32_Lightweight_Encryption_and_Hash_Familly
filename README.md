# PicoRV32 Extensible SoC Repository (`PicoRV32_SOC`)

A modular PicoRV32 System-on-Chip (SoC) optimized for embedded applications and flexible hardware accelerator integration (Custom Crypto Accelerators), targeted for the Digilent Arty A7 FPGA platform (Artix-7 XC7A100TCSG324-1).


---

## 1. Repository Directory Layout

```
PicoRV32_SOC/
├── README.md                           # Overview & project layout documentation
├── COPYING                             # Open-source license (Unlicense/MIT)
├── .gitignore                          # Build artifact ignore settings
├── firmware/                           # RISC-V Firmware & Bootloader source
│   ├── Makefile                        # Firmware compilation Makefile
│   ├── boot_crt0.S                     # Startup assembly for Boot BRAM
│   ├── app_crt0.S                      # Startup assembly for App BRAM
│   ├── bootloader.c                    # Bootloader loading app from SD/UART
│   ├── bootloader.ld                   # Linker script for Boot BRAM (4 KB)
│   ├── firmware.c                      # C application testing crypto cores
│   ├── firmware.h                      # Header defining SoC & APB Crypto registers
│   ├── firmware.ld                     # Linker script for App RAM (20 KB)
│   ├── makehex.py                      # Convert ELF/BIN files to Verilog HEX
│   ├── wrap_firmware.py                # Package firmware image for bootloader
│   └── gen_sim_sd_hex.py               # Generate SD card memory image for simulation
├── rtl/                                # Verilog Hardware Source Code (RTL)
│   ├── cpu/
│   │   └── picorv32.v                  # PicoRV32 RISC-V CPU Core (RV32I/E/M)
│   ├── crypto/                         # APB Extensible Crypto Accelerator Cluster
│   │   ├── aead_mmap_wrapper.v         # APB Pass-through Wrapper
│   │   ├── crypto_cluster.v            # APB Crypto Bus Cluster & Address Mux
│   │   ├── dummy_crypto_core.v         # Custom Crypto Core Template/Skeleton
│   │   └── README_CRYPTO.md            # Detailed guide for adding new algorithms
│   ├── peripherals/
│   │   ├── simpleuart.v                # UART Controller (115200 baud)
│   │   └── simple_spi_master.v         # SPI Master Controller (SD Card interface)
│   ├── soc/
│   │   ├── system.v                    # Top-level SoC Interconnect
│   │   ├── apb_interconnect.v          # APB Bus Interconnect
│   │   ├── axi_to_apb_bridge.v         # AXI4-Lite to APB3 Bridge
│   │   ├── axi_arbiter_rr.v            # Round-Robin Arbiter
│   │   └── mem/
│   │       ├── boot_rom_inferred.v     # BRAM Boot ROM
│   │       └── app_ram_inferred.v      # BRAM Application RAM
│   └── tb/
│       ├── system_tb.v                 # SoC Simulation Testbench (Icarus / Vivado)
│       └── sd_card_model.v             # SD Card Behavioral Model
└── scripts/
    └── vivado/
        ├── Makefile                    # Makefile for Vivado simulation & synthesis
        ├── build.tcl                   # Vivado TCL build script
        ├── synth_system.tcl            # Vivado TCL synthesis script
        └── synth_system.xdc            # Pin / Timing Constraints for target FPGA
```

---

## 2. SoC Memory Map

| Address Range | Size | Bus | Peripheral / Memory Unit |
|---|---|---|---|
| `0x0000_0000 – 0x0000_0FFF` | 4 KB | APB | Boot BRAM (Read-Only) |
| `0x0001_0000 – 0x0001_4FFF` | 20 KB | AXI | Application BRAM (Read-Write) |
| `0x1000_0000` | 1 Byte | APB | Out Byte / LED |
| `0x1000_0004` | 4 Bytes | APB | UART TX Data Write |
| `0x1000_0008` | 4 Bytes | APB | UART RX Data Read |
| `0x1000_000C` | 4 Bytes | APB | UART Status Read |
| `0x1000_0010` | 4 Bytes | APB | UART Baud Clock Divider |
| `0x2000_0000` | 4 Bytes | APB | Switches Input Read |
| `0x2000_0004` | 4 Bytes | APB | Buttons Input Read |
| `0x3000_0000 – 0x3000_00FC` | 256 Bytes | APB | Extensible Crypto Cluster Registers |
| `0x6000_0000 – 0x6000_000C` | 16 Bytes | APB | SD SPI Master Controller |

---

## 3. Workflow for Adding Custom Crypto Cores

Please refer to the step-by-step guide at [rtl/crypto/README_CRYPTO.md](rtl/crypto/README_CRYPTO.md).

Summary of steps:
1. Create a new Verilog crypto core in `rtl/crypto/my_crypto_core.v`.
2. Connect the module in `rtl/crypto/crypto_cluster.v` and multiplex signals based on `alg_sel`.
3. Declare the algorithm ID and write C drivers in `firmware/firmware.h` and `firmware/firmware.c`.

---

## 4. Compilation & Simulation

### Compiling RISC-V Firmware:
```bash
cd firmware
make clean
make
```

### Running RTL Simulation with Icarus Verilog:
```bash
cd scripts/vivado
make sim_iverilog
```
