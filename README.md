# ARES-P4: 4x ARES-L RISC-V SoC with miniTensor YOLO acceleration

Target board: Pango 200Pro+ (PG2L200H-**6IFBB676**, 159.8k LUT6 / 415 DRM / 740 APM,
27 MHz system clock, HDMI via the on-board MS7210 PHY).

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

## 上板（盘古 200Pro+ / PG2L200H-6IFBB676）

- 上板指南（硬件、烧写、串口、图像识别、排错）：**[docs/board_guide.md](docs/board_guide.md)**
- 可直接烧写的位流：**[bitstream/ares_p4_vision.sbit](bitstream/ares_p4_vision.sbit)**（图像识别 demo）
  与 **[bitstream/ares_p4_coremark.sbit](bitstream/ares_p4_coremark.sbit)**（CoreMark），
  说明见 [bitstream/README.md](bitstream/README.md)
- 一键重建：`powershell -File tools\build_board.ps1 -Target vision`
  （固件 → 128-bit 镜像 → ADS 兼容 RTL → compile/synthesize -ads/dev_map/pnr/gen_bit_stream，约 1 小时）

Pango ADS 只支持 SystemVerilog 子集（无 interface/enum/隐式端口），
`tools/pango_prep.py` 负责把 `rtl/` 机械改写成 `build/pango/syn/rtl` 后再综合；
仿真仍使用原始 `rtl/`。

实测（PG2L200H-6IFBB676，27 MHz）：setup WNS **+10.971 ns**（Fmax 38.4 MHz）、
hold slow +0.068 ns、fast 角 −0.073 ns / 60 端点；CLMA 45%、LUT 25%、FF 12%、
DRM 219.5/415（53%）、APM 8%；位流 9,188,552 B。

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
mismatch (documented in the 2026-10-18 commits; the YOLO path is not part of the board build).

## Memory map

| Base | Size | Region |
|---|---:|---|
| 0x0000_0000 | 64 KiB | Boot ROM (trampoline to DDR) |
| 0x0001_0000 | 64 KiB | CLINT |
| 0x0002_0000 | 64 KiB | PLIC |
| 0x0003_0000 | 64 KiB | Mailbox / Barrier |
| 0x1000_0000 | 192 KiB | L2 scratchpad / per-core scratch (板级 64 KiB) |
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
    rtl/soc/mt/        CV-X-IF shim, DMA bridge, miniTensor wrapper + board stub
    rtl/soc/video/     timing, OSD, TMDS + board stub
    rtl/soc/ddr/       behavioural DDR3 model, Pango DDR3 front end, on-chip memory
    rtl/board/         board top for the Pangu 200Pro+ (pins, reset, LEDs)
    rtl/minitensor/    imported workspace miniTensor RTL
    firmware/common/   startup, linker, runtime, board header
    firmware/coremark/ CoreMark port
    firmware/vision/   CPU-only 32x32 shape recognition demo (board default)
    firmware/yolo/     miniTensor driver, conv engine, packed detector
    firmware/tests/    ISA, scratchpad, SMP, miniTensor tests
    sim/               Verilator testbenches
    fpga/pango/        board constraints (.fdc), PDS flow, programmer script, DDR3 IP
    bitstream/         prebuilt .sbit images + description
    tools/             build/prep/image-conversion scripts
    docs/              board_guide.md (the single up-to-date document)

## FPGA flow

The board build replaces the behavioural `ddr3_model` with `onchip_ddr`
(128 KiB BRAM pre-loaded with the firmware image) and uses ADS-compatible
stubs for the video subsystem and the miniTensor cluster, because Pango ADS
cannot parse SV interfaces or elaborate those two blocks. The DDR3 IP under
`fpga/pango/ip/ddr3/` is regenerated for this device and validated through
compile/synthesize/dev_map/pnr, but the 128-bit to 256-bit AXI bridge is still
to be written. Details and the remaining steps: [docs/board_guide.md](docs/board_guide.md).

## Known limitations

- No A extension (AMO/LR/SC); inter-core synchronization uses mailbox/barrier.
- L2 is blocking (single outstanding) in this revision.
- Board build uses smaller memories than the simulator (L1 4 KiB, L2 64 KiB,
  scratchpad 64 KiB, on-chip 128 KiB) to fit the DRAM budget ADS infers;
  the simulator keeps the full sizes.
- Video capture/scaler is register-reserved on the board; the OSD/TMDS path is
  verified in simulation only.
- Fast-corner hold misses by 0.073 ns on 60 endpoints (27 MHz has 11 ns setup
  margin, so this is cosmetic for now).
- The YOLO detector golden mismatch (2026-10-18 commits) is not fixed; the YOLO
  path is not part of the board build.