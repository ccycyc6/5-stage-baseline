# Tensor implementation area

The first implemented tensor operation is a non-pipelined 4x4 signed INT8
GEMM. It uses the existing 128-bit Unified Buffer without changing its 1R1W
interface:

```text
A: one UB row, row-major signed INT8, 16 elements
B: one UB row, row-major signed INT8, 16 elements
C: four UB rows, row-major signed INT32, four elements per row
C = A * B
```

`MT_GEMM` uses `funct7=0000101`, `funct3=000` in `custom-0`:

```text
rs1[7:0]  = A UB row
rs1[15:8] = B UB row
rs2[7:0]  = C UB start row (C..C+3 must fit)
rs2[8]    = accumulate (0: C=A*B, 1: C=C_old+A*B)
```

All other operand bits are reserved and must be zero. The command is accepted
through the existing CV-X-IF issue/register/commit/result sequence. A killed
or invalid command has no UB write side effect.

The current implementation boundaries are:

```text
MXU/
  INT8_GEMM/
  Systolic_Array/
  INT32_Accumulator/
Epilogue/
  Bias/
  Requant/
  ReLU/
```

`tensor_gemm_core` runs a fixed 4x4 systolic array for ten cycles, holds its
result under backpressure, and `tensor_controller` performs the two synchronous
UB reads, optionally reads four existing C rows for accumulation, and then
performs four sequential result writes. Multiple K tiles can therefore be
issued by software using one initial GEMM followed by accumulate GEMMs.

`tensor_epilogue_controller` reads four C rows, four Bias rows and one config
row, while `tensor_epilogue_core` applies signed multiplier, arithmetic right
shift, signed zero point, INT8 saturation and optional ReLU. `MT_EPILOGUE`
uses `rs1[7:0]`/`rs1[15:8]` for C/Bias bases and `rs2[7:0]`/`rs2[15:8]` for
output/config rows; all `rs1[31:16]` and `rs2[31:16]` bits are reserved.
Double buffering and pipelining remain future work.

## Closed-loop NPC verification

`tb/npc/vpu_npc_model.sv` (a behavioural CPU with a CV-X-IF master port) and
`tb/npc/mt_mem_model.sv` (memory with wait states and back-pressure) drive
`tb/top/tb_mini_tensor_npc.sv` through a full tensor kernel:

```text
MT_LOAD(A/B/Bias/Config)
  -> MT_GEMM(C = A0*B0)
  -> MT_GEMM(C += A1*B1)
  -> MT_GEMM(C += A2*B2)
  -> MT_EPILOGUE
  -> MT_STORE
```

K = 12 exercises three accumulate rounds.  The testbench checks the INT32
accumulator rows in the UB, the packed INT8 epilogue row, and the final
external memory image against an independent golden model.  Run it with
`make npc-sim`.
