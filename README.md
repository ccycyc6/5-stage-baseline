# ARES-P4: 4x ARES-L RISC-V SoC with miniTensor YOLO acceleration

Target board: Pango 200Pro+ (PG2L200H-6IFBG676, 159.8k LUT6 / 415 DRM / 740 APM).

ARES-P4 is a complete FPGA-oriented SoC:

- 4x ARES-L 5-stage in-order RV32IM cores, one per AMP hart. Each core has a
  2-way 8 KiB L1I, a 2-way 8 KiB write-back L1D, a 2-bit BHT + BTB branch
  predictor, M-mode CSR/traps, and its own miniTensor accelerator.
- Shared L2: 128 KiB 4-way cache + 192 KiB scratchpad, four core ports and one
  video port, QoS arbitration, and a DDR3 master.
- System: CLINT (4 harts), PLIC (32 sources / 4 contexts), mailbox/barrier,
  Boot ROM trampoline, DDR3, QSPI window, UART/GPIO/SPI/I2C/SD/GbE stubs.
- AI: 4x miniTensor (4x4 INT8 GEMM + VPU + epilogue) driven by a CV-X-IF host
  adapter and a 128-bit DMA bridge. Packed INT8 YOLO detector firmware.
- Video: 640x480@60 timing, colour-bar test pattern, 8-box OSD, HDMI TMDS
  encoders. The OV5640/HDMI-IN capture/scaler register window is reserved.
- Software: bare-metal runtime, CoreMark v1.0 port, SMP/mailbox test,
  miniTensor DMA/GEMM regression, YOLO detector.

See docs/implementation_plan.md, docs/verification_report.md and docs/register_map.md.

## Quick start

Prerequisites: Verilator 5 or newer, riscv64-unknown-elf-gcc with the RV32IM
multilib, Python 3.

Commands (run from the repository root):

    make lint        # Verilator lint of the synthesizable SoC
    make sim         # build the Verilator SoC simulator
    make core-test   # directed 5-stage ISA test
    make coremark    # CoreMark v1.0 on hart0
    make smp         # 4-hart mailbox/barrier/scratchpad test
    make mt-gemm     # miniTensor DMA + GEMM + accumulation + epilogue
    make yolo        # packed INT8 YOLO detector on miniTensor
    make video       # 640x480 timing / OSD / TMDS testbench

A longer CoreMark run:

    make coremark ITERATIONS=1000

For the board UART divisor:

    make clean && make board

The simulator loads a DDR image with a plusarg:

    ./build/obj_soc/Vtb_soc +DDR=build/coremark/coremark.hex

UART output is captured in build/uart.log.

## Current results (Verilator, 100 MHz model)

| Test | Result |
|---|---|
| Core directed ISA (arith/branch/load/store/mul/div/fence) | PASS |
| CoreMark v1.0, 10 iterations | PASS, CRC 0xe714/0x1fd7/0x8e3a/0xfcaf |
| CoreMark/MHz | 0.903 (90.2 iterations/s at 100 MHz) |
| 4-hart mailbox/barrier/scratchpad | PASS |
| miniTensor 4x4 GEMM, 9x accumulation, epilogue | PASS |
| 64 KiB scratchpad byte test | PASS |
| 640x480 video timing/OSD/TMDS | PASS |
| YOLO detector execution | runs 17,184 commands/image, 6.37 M cycles; stage golden mismatch under investigation |

The YOLO detector executes the full 3-conv + head graph and decodes the head
map, but the current packed golden comparison shows a stage-1 tiling/spatial
mismatch. See docs/yolo_status.md for the bisection data and next fix.

## Memory map

| Base | Size | Region |
|---|---:|---|
| 0x0000_0000 | 64 KiB | Boot ROM (trampoline to DDR) |
| 0x0001_0000 | 64 KiB | CLINT |
| 0x0002_0000 | 64 KiB | PLIC |
| 0x0003_0000 | 64 KiB | Mailbox / Barrier |
| 0x1000_0000 | 192 KiB | L2 scratchpad / per-core scratch |
| 0x4000_0000 | 1 GiB | DDR3 uncached alias |
| 0x8000_0000 | 1 GiB | DDR3 cached |
| 0xC000_0000 | 64 KiB | QSPI simulation window |
| 0xD000_0000 | 64 KiB | UART/GPIO/SPI/I2C/SD/GbE/Video/DMA |
| 0xE000_0000 | 16 KiB | miniTensor 0-3 (4 KiB each) |
| 0xF000_0000 | 64 KiB | Debug |

## Directory

    rtl/common/        package + memory map
    rtl/core/          ARES-L 5-stage core, CSR, BPU, mul/div, regfile
    rtl/cache/         2-way L1I/L1D
    rtl/soc/           L2, CLINT/PLIC/mailbox/UART/GPIO/SPI/MMIO bus
    rtl/soc/mt/        CV-X-IF shim, DMA bridge, per-core miniTensor wrapper
    rtl/soc/video/     timing, OSD, TMDS
    rtl/soc/ddr/       behavioral DDR3 model
    rtl/minitensor/    imported workspace miniTensor RTL
    firmware/common/   startup, linker, runtime, board header
    firmware/coremark/ CoreMark port
    firmware/yolo/     miniTensor driver, conv engine, packed detector
    firmware/tests/    ISA, scratchpad, SMP, miniTensor tests
    sim/               Verilator testbenches
    fpga/pango/        PDS project scripts and constraints
    docs/              plan, verification, YOLO status

## FPGA flow

The simulation-only ddr3_model is replaced by the Pango DDR3 IP on the board.
See fpga/pango/README.md for the PDS TCL/PDC/SDC templates and the IP
checklist. The RTL is plain SystemVerilog with one CV-X-IF interface internal
to each mt_cluster; the top-level ports are flat.

## Known limitations

- No A extension (AMO/LR/SC); inter-core synchronization uses mailbox/barrier.
- L2 is blocking (single outstanding) in this revision; the arbiter gives
  miniTensor DMA priority to avoid polling starvation.
- Video capture/scaler is register-reserved; the test-pattern/OSD/HDMI path is
  implemented and verified.
- Pango PDS synthesis/place-and-route has not been run in this environment; the
  TCL/PDC/SDC files are templates to be completed with the board pins.
- The YOLO detector golden mismatch is documented and actively bisected.
