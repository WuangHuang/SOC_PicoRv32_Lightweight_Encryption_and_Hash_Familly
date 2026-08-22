# Merged TCL Script

# Wrapper and System Verilog Files
read_verilog system.v
read_verilog axi_to_apb_bridge.v
read_verilog apb_interconnect.v
read_verilog crypto_cluster.v
read_verilog ../../picosoc/aead_mmap_wrapper.v
read_verilog ../../picosoc/simple_spi_master.v
read_verilog ../../picorv32.v
read_verilog ../../picosoc/simpleuart.v


# TinyJambu Core
read_verilog ../../picosoc/tinyjambu/tinyjambu_core.v

# Xoodyak Core
read_verilog ../../picosoc/Xoodyak_old/xoodoo.v
read_verilog ../../picosoc/Xoodyak_old/xoodoo_n_rounds.v
read_verilog ../../picosoc/Xoodyak_old/xoodoo_rc.v
read_verilog ../../picosoc/Xoodyak_old/xoodoo_round.v
read_verilog ../../picosoc/Xoodyak_old/xoodyakcore.v

# GIFT-COFB Core
read_verilog ../../picosoc/GIFT_COFB/cofb_core.v
read_verilog ../../picosoc/GIFT_COFB/double_half_block.v
read_verilog ../../picosoc/GIFT_COFB/feedback_G.v
read_verilog ../../picosoc/GIFT_COFB/gift128_addroundkey.v
read_verilog ../../picosoc/GIFT_COFB/gift128_encrypt_top.v
read_verilog ../../picosoc/GIFT_COFB/gift128_keyschedule.v
read_verilog ../../picosoc/GIFT_COFB/gift128_permbits.v
read_verilog ../../picosoc/GIFT_COFB/gift128_round.v
read_verilog ../../picosoc/GIFT_COFB/gift128_roundconst.v
read_verilog ../../picosoc/GIFT_COFB/gift128_subcells.v
read_verilog ../../picosoc/GIFT_COFB/padding.v
read_verilog ../../picosoc/GIFT_COFB/pho.v
read_verilog ../../picosoc/GIFT_COFB/pho1.v
read_verilog ../../picosoc/GIFT_COFB/phoprime.v
read_verilog ../../picosoc/GIFT_COFB/triple_half_block.v
read_verilog ../../picosoc/GIFT_COFB/xor_block.v
read_verilog ../../picosoc/GIFT_COFB/xor_topbar_block.v

# ChaCha20-Poly1305 AEAD wrapper
read_verilog ../../picosoc/poly_chaha/chacha20_poly1305_core.v

# ChaCha20 Core
read_verilog ../../picosoc/poly_chaha/chacha/chacha.v
read_verilog ../../picosoc/poly_chaha/chacha/chacha_core.v
read_verilog ../../picosoc/poly_chaha/chacha/chacha_qr.v

# Poly1305 Core
read_verilog ../../picosoc/poly_chaha/poly1305/poly1305.v
read_verilog ../../picosoc/poly_chaha/poly1305/poly1305_core.v
read_verilog ../../picosoc/poly_chaha/poly1305/poly1305_final.v
read_verilog ../../picosoc/poly_chaha/poly1305/poly1305_mulacc.v
read_verilog ../../picosoc/poly_chaha/poly1305/poly1305_pblock.v

# Constraints
read_xdc synth_system.xdc

# Synthesis and Implementation
synth_design -part XC7A100TCSG324-1 -top system -directive PerformanceOptimized

opt_design -directive ExploreWithRemap
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore

# Reports
report_utilization -hierarchical -file report_utilization.rpt
report_timing

# Write Outputs
write_verilog -force synth_system.v
write_bitstream -force synth_system.bit

# Per-core TIMING reports were removed: opt_design flattens the core
# instances, so they only produced "Instance not found" stubs. The
# authoritative per-core Fmax comes from the standalone OOC flow:
#   vivado -mode batch -source fmax_ooc.tcl   (writes fmax_ooc.csv,
#   consumed automatically by firmware/generate_report.py)

proc report_core_util {inst_path report_file} {
    set inst [get_cells $inst_path]
    if {[llength $inst] == 0} {
        set fh [open $report_file "w"]
        puts $fh "Instance not found (possibly flattened by opt_design): $inst_path"
        close $fh
        return
    }
    report_utilization -cells $inst -file $report_file
}

# Full System Reports
report_utilization -hierarchical -hierarchical_depth 3 -file report_util_full.txt

# Per-core Utilization Reports
report_core_util u_aead/u_cluster/u_tinyjambu report_util_tinyjambu.txt
report_core_util u_aead/u_cluster/u_xoodyak   report_util_xoodyak.txt
report_core_util u_aead/u_cluster/u_cofb      report_util_giftcofb.txt
report_core_util u_aead/u_cluster/u_chacha    report_util_chacha.txt
report_core_util u_aead/u_cluster/u_poly1305  report_util_poly1305.txt

# Summary Timing
report_timing_summary -file report_timing_summary.txt
