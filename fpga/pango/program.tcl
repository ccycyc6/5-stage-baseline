# ---------------------------------------------------------------------------
# JTAG download onto the Pangu 200Pro+.
#
#   D:\PDS_2022.2-SP6.4\bin\cdt_js.exe -port 65420          (start once)
#   D:\PDS_2022.2-SP6.4\bin\cdt_cfg.exe -file fpga\pango\program.tcl ^
#       -args {<absolute path>\board_smoke.sbit}
# ---------------------------------------------------------------------------
cfg_connect -ip 127.0.0.1 -port 65420
cfg_scan_chain
cfg_assign_file -file %s -device_index 0
cfg_program -device_index 0
cfg_disconnect
cfg_close
