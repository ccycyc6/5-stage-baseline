# ---------------------------------------------------------------------------
# ARES-P4 board build for the Pangu 200Pro+ (PG2L200H-6IFBB676).
#
# This script is the canonical copy; tools/build_board.ps1 copies it next to
# fw.hex (build/pango/syn) and runs it there, which is also where PDS puts its
# project and action directories:
#
#   cd build/pango/syn
#   D:\PDS_2022.2-SP6.4\bin\pds_shell.exe -file flow_board.tcl -project_name ares_p4
#
# Inputs (relative to this script's directory): rtl/**/*.v, fw.hex.
# ---------------------------------------------------------------------------
set here [file dirname [file normalize [info script]]]

if {[file exists [file join $here "fw.hex"]]} {
  # copied into the build directory
  set fdc [file normalize [file join $here ".." ".." ".." "fpga" "pango" "ares_p4_board.fdc"]]
} else {
  # run from the repo copy: move to the build directory first
  cd [file normalize [file join $here ".." ".." "build" "pango" "syn"]]
  set fdc [file join $here "ares_p4_board.fdc"]
}
puts "ARES-P4: working directory [pwd]"
puts "ARES-P4: constraints $fdc"
if {![file exists "fw.hex"]} {
  error "fw.hex not found in [pwd] - run tools/build_board.ps1 first"
}

set_arch -family Logos2 -device PG2L200H -package FBB676 -speedgrade -6
add_constraint $fdc

proc walk {dir} {
  set out {}
  foreach f [lsort [glob -nocomplain -directory $dir *]] {
    if {[file isdirectory $f]} {
      set out [concat $out [walk $f]]
    } elseif {[string match "*.v" $f]} {
      lappend out $f
    }
  }
  return $out
}

set n 0
foreach f [walk rtl] {
  add_design $f
  incr n
}
puts "ARES-P4: added $n RTL files"

compile -top_module ares_p4_board -system_verilog \
        -compiler_directives "ARES_NO_MT ONCHIP_DDR ARES_FPGA"

synthesize -ads
dev_map
pnr
report_timing -max_path 20
gen_bit_stream -create_bit true
