VIVADO_BASE = /xillin/2026.1

VIVADO = $(VIVADO_BASE)/bin/vivado
XVLOG = $(VIVADO_BASE)/bin/xvlog
XELAB = $(VIVADO_BASE)/bin/xelab
GLBL = $(VIVADO_BASE)/data/verilog/src/glbl.v
IVERILOG ?= iverilog
VVP ?= vvp

SIM_RTL = \
	../../rtl/tb/system_tb.v \
	../../rtl/soc/system.v \
	../../rtl/soc/axi_to_apb_bridge.v \
	../../rtl/soc/apb_interconnect.v \
	../../rtl/soc/axi_arbiter_rr.v \
	../../rtl/soc/mem/boot_rom_inferred.v \
	../../rtl/soc/mem/app_ram_inferred.v \
	../../rtl/cpu/picorv32.v \
	../../rtl/peripherals/simpleuart.v \
	../../rtl/peripherals/simple_spi_master.v \
	../../rtl/crypto/aead_mmap_wrapper.v \
	../../rtl/crypto/Klein_Core.v \
	../../rtl/crypto/LiCi_Core.v \
	../../rtl/crypto/Piccolo_Core.v \
	../../rtl/crypto/crypto_cluster.v 

all: sim_iverilog

sim_iverilog: $(SIM_RTL)
	$(IVERILOG) -o system_tb.vvp $(SIM_RTL)
	$(VVP) system_tb.vvp

synth:
	$(VIVADO) -mode batch -source synth_system.tcl

clean:
	rm -rf *.log *.jou *.pb *.vvp xsim.dir
