# ---------------------------------------------------------------------------
# flow_soc.tcl - bring-up stage B2: CPU + on-chip boot ROM + UART, no video.
#
# Top: rtl/board/board_b2.v  (Verilog-2001)
#      calls ares_soc, which is SystemVerilog and is pre-converted by
#      tools/pango_prep.py into build/pango/syn/rtl/**/*.v
#
# Run from a scratch directory:
#   cd build\pango\soc
#   D:\PDS_2022.2-SP6.4\bin\pds_shell.exe -file E:\qs\5-stage-baseline\fpga\pango\flow_soc.tcl -project_name soc
#
# do_pnr = 0 gives a compile + synthesize + dev_map check in a few minutes.
# ---------------------------------------------------------------------------
set do_pnr 1
# Set the environment variable ARES_NO_PNR=1 for a fast parse/synthesis check.
if {[info exists ::env(ARES_NO_PNR)]} { set do_pnr 0 }

set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here ".." ".."]]
set syn  [file join $root "build" "pango" "syn" "rtl"]

puts "soc: here=$here"
puts "soc: root=$root"
puts "soc: workdir=[pwd]"

set_arch -family Logos2 -device PG2L200H -package FBB676 -speedgrade -6
add_constraint [file join $here "board_pins.fdc"]

# ---- converted SystemVerilog (package first) -------------------------------
add_design [file join $syn "common" "ares_pkg.v"]
foreach f [list \
    "core/ares_regfile.v" "core/ares_muldiv.v" "core/ares_bpu.v" \
    "core/ares_csr.v" "core/ares_l_core.v" \
    "cache/ares_l1i.v" "cache/ares_dmem.v" \
    "soc/ares_clint.v" "soc/ares_uart.v" "soc/ares_gpio.v" \
    "soc/ares_mmio_bus.v" "soc/ares_l2.v" "soc/ares_core_complex.v" \
    "soc/ares_soc.v" ] {
    add_design [file join $syn $f]
}

# ---- hand-written Verilog-2001 (not touched by the prep script) ------------
add_design [file join $root "rtl" "soc" "mt"  "mt_cluster_stub.v"]
add_design [file join $root "rtl" "soc" "ddr" "ddr_stub.v"]
add_design [file join $root "rtl" "board" "boot_rom.v"]
add_design [file join $root "rtl" "board" "board_b2.v"]

compile -top_module board_b2 -system_verilog \
        -compiler_directives "ARES_NO_MT ARES_NO_DDR ARES_BOOT_ROM ARES_FPGA"

synthesize -ads
dev_map

if {$do_pnr} {
    pnr
    report_timing -max_path 20
    gen_bit_stream -create_bit true
}
