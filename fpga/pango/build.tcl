# Pango PDS build script template for ARES-P4.
# Usage (from the repository root, with PDS in PATH):
#   pds -batch -source fpga/pango/build.tcl
#
# The device and package must match the board:
set_device PG2L200H-6IFBG676
set_top_module ares_p4_soc

# ---------------------------------------------------------------- RTL sources
set rtl_files [list \
  rtl/common/ares_pkg.sv \
  rtl/minitensor/interface/core_v_xif.sv \
  rtl/minitensor/common/minitensor_pkg.sv \
  rtl/minitensor/tensor/tensor_pkg.sv \
  rtl/minitensor/vector/vpu_pkg.sv \
  rtl/minitensor/vector/vpu_vector_regfile.sv \
  rtl/minitensor/vector/vpu_vector_alu.sv \
  rtl/minitensor/control/vpu_vector_controller.sv \
  rtl/minitensor/tensor/MXU/Systolic_Array/tensor_pe.sv \
  rtl/minitensor/tensor/MXU/Systolic_Array/tensor_systolic_array.sv \
  rtl/minitensor/tensor/MXU/INT8_GEMM/tensor_gemm_core.sv \
  rtl/minitensor/tensor/tensor_controller.sv \
  rtl/minitensor/tensor/Epilogue/tensor_epilogue_core.sv \
  rtl/minitensor/tensor/Epilogue/tensor_epilogue_controller.sv \
  rtl/minitensor/memory/unified_buffer.sv \
  rtl/minitensor/memory/vpu_dma.sv \
  rtl/minitensor/top/mini_tensor_top.sv \
  rtl/core/ares_regfile.sv \
  rtl/core/ares_csr.sv \
  rtl/core/ares_bpu.sv \
  rtl/core/ares_muldiv.sv \
  rtl/cache/ares_l1i.sv \
  rtl/cache/ares_l1d.sv \
  rtl/core/ares_l_core.sv \
  rtl/soc/mt/mt_cvxif_shim.sv \
  rtl/soc/mt/mt_dma_l2_bridge.sv \
  rtl/soc/mt/mt_cluster.sv \
  rtl/soc/ares_cluster.sv \
  rtl/soc/ares_clint.sv \
  rtl/soc/ares_plic.sv \
  rtl/soc/ares_mailbox.sv \
  rtl/soc/ares_uart.sv \
  rtl/soc/ares_gpio.sv \
  rtl/soc/ares_spi.sv \
  rtl/soc/ares_periph_stub.sv \
  rtl/soc/ares_mmio_bus.sv \
  rtl/soc/video/ares_video.sv \
  rtl/soc/ares_l2.sv \
  rtl/soc/ddr/ddr3_model.sv \
  rtl/soc/ddr/pango_ddr3_axi.sv \
  rtl/soc/ares_p4_soc.sv \
]
foreach f $rtl_files {
  add_file -type verilog $f
}
add_file -type sdc fpga/pango/ares_p4.sdc
add_file -type pdc fpga/pango/ares_p4.pdc

# Define PANGO_DDR3_IP and add the Pango-generated pango_ddr3_ip wrapper before
# synthesis on the board:
#   set_option -verilog_define PANGO_DDR3_IP
#   add_file -type verilog <generated>/pango_ddr3_ip.v

# ---------------------------------------------------------------- flow
run syn
run place
run route
run bitgen

report_area  -file build/pango_area.rpt
report_timing -file build/pango_timing.rpt
report_power  -file build/pango_power.rpt
