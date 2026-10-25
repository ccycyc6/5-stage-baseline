# ---------------------------------------------------------------------------
# Program the configuration QSPI flash (固化) so the board boots standalone.
# cdt_cfg needs a flash image (produced by the PDS "Create Flash File" /
# gen_bit_stream flash options). Fill in the file produced by the tool:
#   generate_bitstream/<top>.fs  (or .sfc for embedded-flash parts)
#
# Usage:
#   cdt_cfg.exe -file fpga/pango/program_flash.tcl -args {<flash image>}
# ---------------------------------------------------------------------------
cfg_connect -ip 127.0.0.1 -port 65420
cfg_scan_chain
cfg_assign_file -file %s -device_index 0
cfg_program -device_index 0
cfg_disconnect
cfg_close
