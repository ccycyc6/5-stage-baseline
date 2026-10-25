# ---------------------------------------------------------------------------
# JTAG download of the ARES-P4 bitstream onto the Pangu 200Pro+.
#
# Usage (Windows cmd / pwsh):
#   1) start the JTAG server once:
#        D:\PDS_2022.2-SP6.4\bin\cdt_js.exe -port 65420
#   2) program the device:
#        D:\PDS_2022.2-SP6.4\bin\cdt_cfg.exe -file fpga/pango/program.tcl -args {<sbit>}
#
# %s is replaced by the value passed through -args, so the .sbit path can be
# given on the command line (see docs/board_bringup.md).
# ---------------------------------------------------------------------------
cfg_connect -ip 127.0.0.1 -port 65420
cfg_scan_chain
cfg_assign_file -file %s -device_index 0
cfg_program -device_index 0
cfg_disconnect
cfg_close
