# YOLO detector status and bisection

## What is verified

- Packed weights wt1..wt4 copy from .rodata to the scratchpad: 0 bad bytes.
- Input image copy: 0/4096 bad bytes.
- Layer-1 pad buffer plane kx=0 (offset 0..768) matches the Python pad_group
  golden byte-for-byte.
- The miniTensor DMA, 4x4x4 GEMM, 9x accumulation and epilogue pass the
  directed regression (see docs/verification_report.md).
- The full detector graph runs to completion: 17,184 commands/image and
  6.37 M cycles, with no command errors or timeouts.

## First divergence

The Python packer (miniTensor/integration/tools/pack_weights.py, int_forward
with trace) produces the stage buffers in hardware memory order. Comparing the
first 256 bytes of each stage:

- L1: the first 160 bytes are zero in both. The first nonzero golden pixel is
  at byte 160 (row 1, col 8, channel 0) with value 0x1a. The RTL dump has a
  different value at byte 160 and the golden 0x1a pattern appears around
  byte 192. This looks like an 8-pixel (2-tile) horizontal offset or a tile
  index error in the conv output, not a memory corruption.
- L2/L3/L4 inherit the error and the head map has no positive objectness.

The pad buffer, weights and image are exact, so the fault is in the
net_conv tile/addressing path (firmware/yolo/mt_net.c) or in the A-row/C-row
addressing of the miniTensor adapter for this layer geometry.

## Next fix

1. Dump the kx=1 and kx=2 pad planes and compare to Python pad_group. This
   isolates the A-plane selection from the weight/tile selection.
2. Instrument net_conv for layer 1, tile t=0..7, row ho=1: log a_addr,
   crow0, and the first C word after each GEMM. Compare a_addr with the pad
   layout: 16*((((kx*ng+g)*PH + (ho+ky))*ntiles) + t).
3. If a_addr is correct, check the C-row store mapping crow0 + j*ntiles4 and
   the UB_OUT row order against the epilogue.
4. Re-run with DET_IMG_COUNT=1 and the stage dumps enabled in mt_detect.c.
5. Once L1 matches, repeat for L2 (ng=2) and the 1x1 head.

## Files

- firmware/yolo/mt_net.c: net_pad, net_conv, net_pool2 and the epilogue loop.
- firmware/yolo/mt_detect.c: packed detector, stage probes and dumps.
- sim/tools/dump_golden.py and dump_pad.py: Python stage/pad byte dumps.
- docs/verification_report.md: full regression results.
