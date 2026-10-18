# NPC model simulation

These files are *testbench models*, not synthesizable RTL.

| File | Role |
| --- | --- |
| `mt_mem_model.sv` | Shared byte-addressed memory: instruction fetch, CPU data, and the 128-bit miniTensor uncached DMA port with configurable latency and ready back-pressure. |
| `vpu_npc_model.sv` | Behavioural main-CPU model. Executes a compact in-order RV32I subset and drives the full CV-X-IF issue/register/commit/result lifecycle for the miniTensor custom-0 instructions. The handshake latency is parameterized and defaults to a deep (~9-stage) in-order core such as Mundus NPC. |

`../top/tb_mini_tensor_npc.sv` wires both models to `mini_tensor_top` and runs the
complete tensor kernel:

```text
MT_LOAD(A/B/Bias/Config) -> MT_GEMM(C = A0*B0) -> MT_GEMM(C += A1*B1)
  -> MT_GEMM(C += A2*B2) -> MT_EPILOGUE -> MT_STORE
```

K = 12, so three accumulate rounds are exercised.  The testbench computes an
independent golden model and checks the INT32 accumulator rows in the UB, the
packed INT8 epilogue row, and the final external memory image.  DMA read/write
latency, periodic DMA ready back-pressure and CPU result back-pressure are all
enabled during the run.

Run it with:

```sh
make npc-sim
```

The real Mundus NPC is not modified: it does not yet expose a CV-X-IF slave
port, so this model stands in for the core until that integration lands.
