# ARES-P4 Verification Report

Environment: Verilator 5.040, riscv64-unknown-elf-gcc 13.2.0, Python 3,
100 MHz SoC clock model. Reproduce with the make targets in README.md.

## 1. Core directed ISA test

build/obj_core/Vtb_core exercises RV32IM arithmetic, branches (including
BGEU), loads/stores (LB/LBU/SW), MUL/DIV/REM, FENCE, FENCE.I and EBREAK. All
checks pass:

    PASS sum 1..10 = 00000037
    PASS mul 7*6 = 0000002a
    PASS div 100/7 = 0000000e
    PASS rem 100%7 = 00000002
    PASS sw 0x12345678 = 12345678
    PASS lb 0x78 = 00000078
    PASS lbu 0x12 = 00000012
    PASS branch = 0000beef
    *** CORE TEST PASSED ***

## 2. CoreMark v1.0

Command: make coremark (10 iterations, 100 MHz model). The observed CRCs match
the 2K performance-run reference values:

    CoreMark Size    : 666
    seedcrc          : 0xe9f5
    [0]crclist       : 0xe714
    [0]crcmatrix     : 0x1fd7
    [0]crcstate      : 0x8e3a
    [0]crcfinal      : 0xfcaf

Summary measured by the firmware around the timed region:

    ARES-P4 timed cycles : 11071382
    ARES-P4 CoreMark/MHz : 0.903
    ARES-P4 Iterations/s : 90

The core is a single-issue 5-stage machine with blocking L1/L2 misses and a
33-cycle divider. The score is limited by branch mispredicts, load-use stalls
and the blocking L2. The next performance steps are a non-blocking L2/MSHR,
store buffer, and a 2-cycle pipelined multiplier.

## 3. Four-hart SMP

make smp boots all four harts. Harts 1-3 wait in worker_entry, receive a
mailbox value, write it to the shared scratchpad, and hit the barrier. Hart 0
verifies the values:

    ARES-P4 SMP mailbox/barrier test
      hart1 wrote 00000101 (expect 00000101)
      hart2 wrote 00000102 (expect 00000102)
      hart3 wrote 00000103 (expect 00000103)
      barrier status=0000000e
    *** SMP TEST PASS ***

This validates HARTID, per-hart reset/startup, mailbox, barrier, uncached
scratchpad and FENCE.

## 4. miniTensor regression

make mt-gemm runs a 64-row DMA copy, a 4x4x4 INT8 GEMM, nine accumulating
GEMMs (C=72), and the epilogue (mult=1, shift=0, relu=0):

    MT DMA multi-row test
    dma bad=0
    C[0..15]=00000008
    Cacc[0..15]=00000048
    out[0..3]=48484848
    *** MT GEMM + ACCUM + EPILOGUE PASS ***

This exercises the CV-X-IF shim, command FIFO, DMA read/write bridge, UB,
systolic array, accumulator and epilogue through the full SoC fabric.

## 5. Scratchpad

A 64 KiB byte pattern write/read test over 0x1000_0000..0x1000_FFFF returns
zero errors. This covers the L1D bypass, cluster arbiter, L2 scratchpad and
byte-lane handling.

## 6. Video

make video checks the 640x480@60 timing generator, the 8-box OSD register path
and the TMDS encoders:

    frame1 active=1228800 lines=492
    *** VIDEO TEST PASS ***

## 7. YOLO detector

make yolo executes the packed INT8 detector on the first test image:

    17,184 accelerator commands
    6,371,520 cycles (about 0.27 ms/command in this blocking model)
    full 3-conv + head graph runs to completion

The packed weight/image copies and the layer-1 pad buffer match the Python
reference byte-for-byte. The layer-1 convolution output diverges from the
packed golden after the first 16 bytes, and the current head map has no
positive objectness cell, so the demo prints "no detection". The bisection
data and the next fix are in docs/yolo_status.md.

## 8. What is not signed off

- Pango PDS synthesis/place-and-route, timing closure and board bring-up.
- DDR3 calibration and the Pango DDR3/HDMI IP wrappers.
- Full 1080p video and OV5640 capture/scaler.
- A-extension atomics and hardware cache coherence.
