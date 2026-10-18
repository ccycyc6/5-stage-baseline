`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_mt_shim -- standalone bring-up for mt_cvxif_shim.
//
// Drives the MMIO register interface the way the Mundus perip bridge will,
// against the real mini_tensor_top RTL, and checks LOAD / GEMM / EPILOGUE /
// STORE including the K-dimension accumulate path.
//
// The DPI memory model (mt_dpi_mem.cpp) implements the same mt_dma_read /
// mt_dma_write contract that npc/csrc/wave/mem.cpp will provide, so the DMA
// bridge is exercised over the exact interface used by the SoC integration.
// -----------------------------------------------------------------------------
module tb_mt_shim;

  localparam int DATA_WIDTH = 128;
  localparam int UB_DEPTH   = 256;

  import "DPI-C" function void mt_mem_poke(input int addr, input int data);
  import "DPI-C" function int  mt_mem_peek(input int addr);
  import "DPI-C" function void mt_mem_fill(input int addr, input int byte_value, input int nbytes);

  localparam logic [2:0] IDX_INSTR = 3'd0;
  localparam logic [2:0] IDX_RS1   = 3'd1;
  localparam logic [2:0] IDX_RS2   = 3'd2;
  localparam logic [2:0] IDX_KICK  = 3'd3;

  // Buffer layout inside the 64 KiB uncached alias window
  localparam logic [31:0] A_ADDR    = 32'h8033_0000;
  localparam logic [31:0] B_ADDR    = 32'h8033_0010;
  localparam logic [31:0] BIAS_ADDR = 32'h8033_0100;
  localparam logic [31:0] CFG_ADDR  = 32'h8033_0140;
  localparam logic [31:0] OUT_ADDR  = 32'h8033_0200;
  localparam logic [31:0] ROW_ADDR  = 32'h8033_0300;

  // UB row plan (same shape as tb_mini_tensor_npc.sv)
  localparam logic [7:0] A_ROW = 8'd0, B_ROW = 8'd1, C_ROW = 8'd8;
  localparam logic [7:0] BIAS_ROW = 8'd16, CFG_ROW = 8'd20, OUT_ROW = 8'd24;

  function automatic logic [31:0] mt_enc(input logic [6:0] f7, input logic [2:0] f3, input logic [4:0] rd);
    mt_enc = {f7, 5'd0, 5'd0, f3, rd, 7'b0001011};
  endfunction
  localparam logic [31:0] MT_LOAD     = mt_enc(7'b0000011, 3'b000, 5'd0);
  localparam logic [31:0] MT_STORE    = mt_enc(7'b0000100, 3'b000, 5'd0);
  localparam logic [31:0] MT_GEMM     = mt_enc(7'b0000101, 3'b000, 5'd0);
  localparam logic [31:0] MT_EPILOGUE = mt_enc(7'b0000110, 3'b000, 5'd0);

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  core_v_xif #(
    .X_ID_WIDTH(4),
    .X_HARTID_WIDTH(1)
  ) xif ();

  logic        reg_wr_en;
  logic [2:0]  reg_wr_idx;
  logic [31:0] reg_wr_data;
  logic        status_rd;
  logic [31:0] status;
  logic [31:0] result_data;

  logic         mem_rd_valid, mem_rd_ready, mem_rsp_valid, mem_rsp_ready;
  logic [31:0]  mem_rd_addr;
  logic [127:0] mem_rsp_data;
  logic         mem_wr_valid, mem_wr_ready;
  logic [31:0]  mem_wr_addr;
  logic [127:0] mem_wr_data;
  logic [15:0]  mem_wr_be;

  logic         ub_rd_en, ub_rd_valid;
  logic [7:0]   ub_rd_addr;
  logic [127:0] ub_rd_data;
  logic         dma_busy;

  mt_cvxif_shim #(
    .ISSUE_TO_REGISTER(2),
    .REGISTER_TO_COMMIT(3)
  ) u_shim (
    .clk(clk), .rst(rst),
    .reg_wr_en(reg_wr_en), .reg_wr_idx(reg_wr_idx), .reg_wr_data(reg_wr_data),
    .status_rd(status_rd), .status(status), .result_data(result_data),
    .xif(xif)
  );

  mini_tensor_top #(
    .X_ID_WIDTH(4),
    .X_HARTID_WIDTH(1),
    .DATA_WIDTH(DATA_WIDTH),
    .UB_DEPTH(UB_DEPTH)
  ) u_mt (
    .clk(clk), .rst(rst), .xif(xif),
    .mem_rd_valid(mem_rd_valid), .mem_rd_ready(mem_rd_ready), .mem_rd_addr(mem_rd_addr),
    .mem_rsp_valid(mem_rsp_valid), .mem_rsp_ready(mem_rsp_ready), .mem_rsp_data(mem_rsp_data),
    .mem_wr_valid(mem_wr_valid), .mem_wr_ready(mem_wr_ready), .mem_wr_addr(mem_wr_addr),
    .mem_wr_data(mem_wr_data), .mem_wr_be(mem_wr_be),
    .ub_rd_en(ub_rd_en), .ub_rd_addr(ub_rd_addr),
    .ub_rd_valid(ub_rd_valid), .ub_rd_data(ub_rd_data), .dma_busy(dma_busy)
  );

  mt_dma_bridge u_dma (
    .clk(clk), .rst(rst),
    .mem_rd_valid(mem_rd_valid), .mem_rd_ready(mem_rd_ready), .mem_rd_addr(mem_rd_addr),
    .mem_rsp_valid(mem_rsp_valid), .mem_rsp_ready(mem_rsp_ready), .mem_rsp_data(mem_rsp_data),
    .mem_wr_valid(mem_wr_valid), .mem_wr_ready(mem_wr_ready), .mem_wr_addr(mem_wr_addr),
    .mem_wr_data(mem_wr_data), .mem_wr_be(mem_wr_be)
  );

  // ---------------------------------------------------------------------------
  // MMIO helpers
  // ---------------------------------------------------------------------------
  task automatic mmio_write(input logic [2:0] idx, input logic [31:0] data);
    @(negedge clk);
    reg_wr_en   = 1'b1;
    reg_wr_idx  = idx;
    reg_wr_data = data;
    @(negedge clk);
    reg_wr_en   = 1'b0;
  endtask

  int errors = 0;

  // Cycle accounting for the per-command cost projection.
  int unsigned cyc = 0;
  always_ff @(posedge clk) cyc <= cyc + 1;
  int unsigned last_cmd_cycles = 0;
  int unsigned gemm_chain_cycles = 0;

  // issue one command and poll until the shim is idle again
  task automatic mt_exec(input logic [31:0] instr, input logic [31:0] rs1,
                         input logic [31:0] rs2, output logic [31:0] st);
    int unsigned polls;
    int unsigned cyc_start;
    cyc_start = cyc;
    mmio_write(IDX_INSTR, instr);
    mmio_write(IDX_RS1,   rs1);
    mmio_write(IDX_RS2,   rs2);
    mmio_write(IDX_KICK,  32'd1);

    polls = 0;
    st = 32'hFFFF_FFFF;
    do begin
      @(negedge clk);
      st = status;                       // read without clearing
      polls++;
      if (polls > 20000) begin
        $display("FAIL: mt_exec timed out (instr=%08x)", instr);
        errors++;
        $finish;
      end
    end while (st[0]);

    // consume the sticky done flag
    @(negedge clk);
    status_rd = 1'b1;
    @(negedge clk);
    status_rd = 1'b0;
    last_cmd_cycles = cyc - cyc_start;
  endtask

  task automatic expect_words(input logic [31:0] addr, input int unsigned nwords,
                              input logic [31:0] exp, input string label);
    logic [31:0] got;
    for (int unsigned i = 0; i < nwords; i++) begin
      got = mt_mem_peek(addr + 4*i);
      if (got !== exp) begin
        $display("FAIL %s: word %0d = 0x%08x, expected 0x%08x", label, i, got, exp);
        errors++;
      end
    end
  endtask

  // Queue a command without waiting for it.  This is what exposes a staging
  // register that a queue pop clobbers in the same cycle.
  task automatic mmio_kick(input logic [31:0] instr, input logic [31:0] rs1, input logic [31:0] rs2);
    mmio_write(IDX_INSTR, instr);
    mmio_write(IDX_RS1,   rs1);
    mmio_write(IDX_RS2,   rs2);
    mmio_write(IDX_KICK,  32'd1);
  endtask

  task automatic mt_wait(output logic [31:0] st);
    int unsigned polls;
    polls = 0;
    st = 32'hFFFF_FFFF;
    do begin
      @(negedge clk);
      st = status;
      polls++;
      if (polls > 20000) begin
        $display("FAIL: mt_wait timed out");
        errors++;
        $finish;
      end
    end while (st[0]);
    @(negedge clk);
    status_rd = 1'b1;
    @(negedge clk);
    status_rd = 1'b0;
  endtask

  task automatic expect_ok(input logic [31:0] st, input string label);
    if (!(st[1] && !st[2])) begin
      $display("FAIL %s: status=0x%08x (expected done=1 err=0)", label, st);
      errors++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  logic [31:0] st;

  initial begin
    reg_wr_en   = 1'b0;
    reg_wr_idx  = 3'd0;
    reg_wr_data = 32'd0;
    status_rd   = 1'b0;
    ub_rd_en    = 1'b0;
    ub_rd_addr  = 8'd0;

    mt_mem_fill(A_ADDR,    32'h01, 16);    // A = 4x4 int8, all ones
    mt_mem_fill(B_ADDR,    32'h02, 16);    // B = 4x4 int8, all twos
    mt_mem_fill(BIAS_ADDR, 32'h00, 64);    // bias = 4 rows of zero
    mt_mem_fill(CFG_ADDR,  32'h00, 16);
    mt_mem_fill(OUT_ADDR,  32'hAA, 16);
    mt_mem_fill(ROW_ADDR,  32'h55, 16);
    mt_mem_poke(CFG_ADDR, 32'h0000_0001); // multiplier=1, shift=0, zp=0, relu=0

    repeat (8) @(negedge clk);
    rst = 1'b0;
    repeat (4) @(negedge clk);

    gemm_chain_cycles = cyc;

    // 1. load operands into the UB
    mt_exec(MT_LOAD, A_ADDR,    32'({8'd1,  A_ROW}),    st); expect_ok(st, "LOAD A");
    mt_exec(MT_LOAD, B_ADDR,    32'({8'd1,  B_ROW}),    st); expect_ok(st, "LOAD B");
    mt_exec(MT_LOAD, BIAS_ADDR, 32'({8'd4,  BIAS_ROW}), st); expect_ok(st, "LOAD bias");
    mt_exec(MT_LOAD, CFG_ADDR,  32'({8'd1,  CFG_ROW}),  st); expect_ok(st, "LOAD config");
    $display("[1] 4x MT_LOAD                    ok");

    // 2. C = A*B, requantise, store out  ->  every lane must be 8
    mt_exec(MT_GEMM,     32'({B_ROW, A_ROW}),           32'({9'd0, 1'b0, C_ROW}),        st);
    expect_ok(st, "GEMM acc=0");
    mt_exec(MT_EPILOGUE, 32'({BIAS_ROW, C_ROW}),        32'({CFG_ROW, OUT_ROW}),         st);
    expect_ok(st, "EPILOGUE");
    mt_exec(MT_STORE,    OUT_ADDR,                 32'({8'd1, OUT_ROW}),            st);
    expect_ok(st, "STORE out");
    expect_words(OUT_ADDR, 4, 32'h0808_0808, "C=A*B (K=4)");
    gemm_chain_cycles = cyc - gemm_chain_cycles;
    $display("[2] GEMM + EPILOGUE + STORE       out = 8");
    $display("    4x LOAD + GEMM + EPILOGUE + STORE = %0d cycles (%0d cycles/command avg)",
             gemm_chain_cycles, gemm_chain_cycles / 8);

    // 3. accumulate a second identical tile  ->  16
    mt_exec(MT_GEMM,     32'({B_ROW, A_ROW}),           32'({9'd0, 1'b1, C_ROW}),        st);
    expect_ok(st, "GEMM acc=1");
    mt_exec(MT_EPILOGUE, 32'({BIAS_ROW, C_ROW}),        32'({CFG_ROW, OUT_ROW}),         st);
    expect_ok(st, "EPILOGUE 2");
    mt_exec(MT_STORE,    OUT_ADDR,                 32'({8'd1, OUT_ROW}),            st);
    expect_ok(st, "STORE out 2");
    expect_words(OUT_ADDR, 4, 32'h1010_1010, "accumulated C");
    $display("[3] GEMM accumulate               out = 16");

    // 4. store the A row back out  ->  every lane must be 1
    mt_exec(MT_STORE, ROW_ADDR, 32'({8'd1, A_ROW}), st);
    expect_ok(st, "STORE UB row 0");
    expect_words(ROW_ADDR, 4, 32'h0101_0101, "UB row 0 round trip");
    $display("[4] UB row 0 round trip           out = 1");

    // 5. queue several commands back-to-back and drain once.  The software
    //    writes the next command's staging registers while the queue is still
    //    draining, which used to lose that write whenever a pop landed in the
    //    same cycle -- the whole batch then executed a stale instruction.
    mmio_kick(MT_GEMM,     32'({B_ROW, A_ROW}),     32'({9'd0, 1'b0, 8'd12}));
    mmio_kick(MT_GEMM,     32'({B_ROW, A_ROW}),     32'({9'd0, 1'b1, 8'd12}));
    mmio_kick(MT_EPILOGUE, 32'({BIAS_ROW, 8'd12}),  32'({CFG_ROW, OUT_ROW}));
    mmio_kick(MT_STORE,    OUT_ADDR,                32'({8'd1, OUT_ROW}));
    mt_wait(st);
    expect_ok(st, "queued batch");
    expect_words(OUT_ADDR, 4, 32'h1010_1010, "queued batch C=16");
    $display("[5] back-to-back queueing        out = 16");

    // 6. unsupported encoding must be flagged, not hang
    mt_exec(mt_enc(7'b1111111, 3'b000, 5'd0), 32'd0, 32'd0, st);
    if (!st[3]) begin $display("FAIL: bad encoding not flagged, status=0x%08x", st); errors++; end
    $display("[5] unsupported funct7            accept_err set");

    if (errors == 0) $display("\n*** MT_SHIM TEST PASSED ***\n");
    else             $display("\n*** MT_SHIM TEST FAILED: %0d error(s) ***\n", errors);
    $finish;
  end

  initial begin
    #5_000_000;
    $display("FAIL: global timeout");
    $finish;
  end

endmodule
