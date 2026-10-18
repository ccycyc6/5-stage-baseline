# Pango PDS integration notes (Pangu 200Pro+)

## Device and clocks

- Device: PG2L200H-6IFBG676 (159.8k LUT6, 415 DRM, 740 APM).
- System clock: 100 MHz on the board oscillator. The current SoC has a single
  clock domain; ares_video divides it by 4 for a 25 MHz 640x480 pixel clock.
  For 720p/1080p, add a PLL and a 74.25/148.5 MHz pixel clock domain.
- Reset: active-high board reset, synchronized to sys_clk.

## IP checklist

1. PLL / clocking: 100 MHz system clock, optional 74.25 MHz pixel clock.
2. DDR3: Pango DDR3 IP for the board's 2x32-bit 1066 Mbps memory. Generate the
   IP, expose the simple 128-bit request/response port used by
   rtl/soc/ddr/pango_ddr3_axi.sv, and define PANGO_DDR3_IP for synthesis.
3. HDMI TX: OSERDES/TMDS serializers for the three 10-bit TMDS symbols from
   ares_video (tmds_r/g/b). The current RTL outputs parallel 10-bit symbols;
   the board wrapper must serialize them and drive the HDMI clock pair.
4. HDMI IN / OV5640: capture front end, BT1120/DVP to AXI-Stream or to the
   reserved video register window. The capture/scaler path is a future board
   integration item; the test-pattern/OSD/HDMI output is implemented.
5. QSPI flash: the 64 KiB simulation window in ares_l2 is replaced by the Pango
   QSPI controller for boot.
6. UART/GPIO/SPI/I2C/SD: pin-level wrappers only; the controllers are in
   rtl/soc.

## DDR3 wrapper contract

rtl/soc/ddr/pango_ddr3_axi.sv instantiates pango_ddr3_ip when PANGO_DDR3_IP is
defined. The generated wrapper must expose:

    clk, rst
    req_valid, req_ready, req_write, req_addr[31:0],
    req_wdata[127:0], req_wstrb[15:0]
    rsp_valid, rsp_ready, rsp_rdata[127:0]

The L2 issues 16-byte aligned beats for cache refill/eviction and word-aligned
beats for uncached MMIO/DDR accesses. If the Pango AXI4 IP requires bursts,
add a small AXI4 master between the L2 and the IP (single-beat AXI4 is valid but
less efficient; a 2-beat burst per 32-byte cache line is preferable).

## PDS flow

From the repository root:

    pds -batch -source fpga/pango/build.tcl

Before synthesis, complete the placeholders in:

- fpga/pango/ares_p4.pdc: board pin locations and I/O standards.
- fpga/pango/ares_p4.sdc: clock period/uncertainty and HDMI output timing.
- fpga/pango/build.tcl: define PANGO_DDR3_IP and add the generated DDR3/HDMI IP
  files.

The behavioral ddr3_model is selected automatically when PANGO_DDR3_IP is not
defined, so the same RTL tree lints and simulates without the Pango IP.

## Resource budget (estimate, to be replaced by the PDS report)

| Block | Estimated LUT6 | DRM | APM |
|---|---:|---:|---:|
| 4x ARES-L core + L1 | 30-36k | 4-8 | 0 |
| 4x miniTensor + shim/DMA | 12-18k | 0 | 16-32 |
| L2 + scratchpad | 6-10k | 40-56 | 0 |
| Bus/peripherals/CLINT/PLIC | 4-6k | 0 | 0 |
| Video/OSD/TMDS | 3-5k | 0 | 0 |
| Total estimate | 55-75k | 44-64 | 16-32 |

This leaves headroom on the 159.8k-LUT device for DDR3/HDMI IP and future
capture. The ARES-L core is deliberately single-issue and 5-stage to fit four
copies; the L2 is the main shared resource.

## Board test plan

1. Program the bitstream, connect UART at the divisor compiled with
   UART_DIV=868 (make board).
2. Run the CoreMark image from DDR or QSPI; verify the CRCs and record
   CoreMark/MHz and the PDS frequency.
3. Run the SMP image; verify all four harts report through the mailbox.
4. Run the miniTensor GEMM image; verify the DMA/GEMM/epilogue result.
5. Run the YOLO image; capture the UART log and, once the golden mismatch is
   fixed, verify the detected centre against the Python model.
6. Enable the video test pattern and OSD; verify 640x480 timing and the box
   overlay on HDMI. Replace the test pattern with the capture/scaler path for
   the camera demo.
7. Use an ILA on the L2 request/response, the miniTensor DMA and the CPU
   pipeline for the performance analysis required by the contest.

## Caveats

- Pango PDS support for SystemVerilog interfaces: the CV-X-IF interface is
  internal to mt_cluster and the top-level ports are flat. If the installed PDS
  version rejects the interface, flatten core_v_xif.sv into packed ports in
  mt_cluster/mini_tensor_top (the interface shape is documented in
  rtl/minitensor/interface/core_v_xif.sv).
- The 128 KiB L2 data array and 192 KiB scratchpad infer large BRAMs; confirm
  the PDS inferred memory map and initialize the scratchpad to zero if the tool
  requires it.
- The YOLO detector golden mismatch must be resolved before claiming a
  bit-exact AI demo; the infrastructure, DMA, GEMM and video paths are ready.
