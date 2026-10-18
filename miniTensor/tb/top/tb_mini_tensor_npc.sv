`timescale 1ns/1ps
/* verilator lint_off WIDTHEXPAND */

// End-to-end miniTensor closed loop driven by the NPC (main CPU) model.
//
// The model executes a small tensor kernel entirely through CV-X-IF:
//
//   MT_LOAD  A0/A1/A2 and B0/B1/B2 tiles        (memory -> UB)
//   MT_GEMM  C = A0*B0                          (UB -> MXU -> UB)
//   MT_GEMM  C += A1*B1                          (multi-K accumulation)
//   MT_GEMM  C += A2*B2
//   MT_EPILOGUE  out = requant(C, bias, config)  (INT32 -> INT8)
//   MT_STORE out -> memory
//
// K = 12 therefore exercises three K tiles of 4.  The testbench builds the
// whole memory image, computes an independent golden model and compares both
// the INT32 accumulator rows in the UB and the final INT8 row in memory.
// DMA latency / back-pressure and result back-pressure are enabled so the
// closed loop is verified under realistic stalls.
module tb_mini_tensor_npc;
  import minitensor_pkg::*;
  import tensor_pkg::*;
  import vpu_pkg::*;

  localparam int unsigned DATA_WIDTH           = 128;
  localparam int unsigned X_ID_WIDTH           = 4;
  localparam int unsigned ISSUE_TO_REGISTER    = 2;
  localparam int unsigned REGISTER_TO_COMMIT   = 3;
  localparam int unsigned RESULT_ACCEPT_DELAY  = 3;
  localparam int unsigned DMA_RD_LATENCY       = 2;
  localparam int unsigned DMA_WR_LATENCY       = 1;

  // Memory map (byte addresses)
  localparam logic [31:0] PROG_BASE   = 32'h0000_0000;
  localparam logic [31:0] A_BASE      = 32'h0000_1000;
  localparam logic [31:0] B_BASE      = 32'h0000_1030;
  localparam logic [31:0] BIAS_BASE   = 32'h0000_1100;
  localparam logic [31:0] CONFIG_ADDR = 32'h0000_1140;
  localparam logic [31:0] OUT_ADDR    = 32'h0000_1200;

  // UB row plan
  localparam logic [7:0] UB_A     = 8'd0;   // A0..A2 = 0..2
  localparam logic [7:0] UB_B     = 8'd3;   // B0..B2 = 3..5
  localparam logic [7:0] UB_C     = 8'd8;   // C0..C3 = 8..11
  localparam logic [7:0] UB_BIAS  = 8'd16;  // bias0..3 = 16..19
  localparam logic [7:0] UB_CFG   = 8'd20;
  localparam logic [7:0] UB_OUT   = 8'd24;

  logic clk, rst;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  core_v_xif #(
    .X_NUM_RS(2),
    .X_ID_WIDTH(X_ID_WIDTH),
    .X_RFR_WIDTH(32),
    .X_RFW_WIDTH(32),
    .X_HARTID_WIDTH(1),
    .X_ISSUE_REGISTER_SPLIT(1)
  ) xif();

  // miniTensor <-> memory DMA
  logic                   mem_rd_valid, mem_rd_ready, mem_rsp_valid, mem_rsp_ready;
  logic [31:0]            mem_rd_addr;
  logic [DATA_WIDTH-1:0]  mem_rsp_data;
  logic                   mem_wr_valid, mem_wr_ready;
  logic [31:0]            mem_wr_addr;
  logic [DATA_WIDTH-1:0]  mem_wr_data;
  logic [DATA_WIDTH/8-1:0] mem_wr_be;

  // NPC <-> memory
  logic                   imem_en;
  logic [31:0]            imem_addr, imem_data;
  logic                   cpu_rd_en;
  logic [31:0]            cpu_rd_addr, cpu_rd_data;
  logic                   cpu_wr_en;
  logic [31:0]            cpu_wr_addr, cpu_wr_data;
  logic [3:0]             cpu_wr_be;

  // Memory host / debug
  logic                   host_wr_en;
  logic [31:0]            host_wr_addr;
  logic [DATA_WIDTH-1:0]  host_wr_data;
  logic [DATA_WIDTH/8-1:0] host_wr_be;
  logic [31:0]            dbg_addr;
  logic [DATA_WIDTH-1:0]  dbg_data;
  logic                   dma_rd_hold, dma_wr_hold;

  // NPC status
  logic                   halted, npc_error;
  logic [31:0]            pc_out, retire_count;

  // miniTensor debug UB port
  logic                   ub_rd_en, ub_rd_valid;
  logic [7:0]             ub_rd_addr;
  logic [DATA_WIDTH-1:0]  ub_rd_data;

  logic                   dma_busy;

  mini_tensor_top #(
    .X_ID_WIDTH(X_ID_WIDTH),
    .X_HARTID_WIDTH(1),
    .DATA_WIDTH(DATA_WIDTH),
    .UB_DEPTH(256)
  ) dut (
    .clk(clk), .rst(rst), .xif(xif),
    .mem_rd_valid(mem_rd_valid), .mem_rd_ready(mem_rd_ready), .mem_rd_addr(mem_rd_addr),
    .mem_rsp_valid(mem_rsp_valid), .mem_rsp_ready(mem_rsp_ready), .mem_rsp_data(mem_rsp_data),
    .mem_wr_valid(mem_wr_valid), .mem_wr_ready(mem_wr_ready), .mem_wr_addr(mem_wr_addr),
    .mem_wr_data(mem_wr_data), .mem_wr_be(mem_wr_be),
    .ub_rd_en(ub_rd_en), .ub_rd_addr(ub_rd_addr),
    .ub_rd_valid(ub_rd_valid), .ub_rd_data(ub_rd_data), .dma_busy(dma_busy)
  );

  mt_mem_model #(
    .DEPTH_ROWS(1024),
    .DMA_RD_LATENCY(DMA_RD_LATENCY),
    .DMA_WR_LATENCY(DMA_WR_LATENCY)
  ) u_mem (
    .clk(clk), .rst(rst),
    .host_wr_en(host_wr_en), .host_wr_addr(host_wr_addr),
    .host_wr_data(host_wr_data), .host_wr_be(host_wr_be),
    .dbg_addr(dbg_addr), .dbg_data(dbg_data),
    .imem_en(imem_en), .imem_addr(imem_addr), .imem_data(imem_data),
    .cpu_rd_en(cpu_rd_en), .cpu_rd_addr(cpu_rd_addr), .cpu_rd_data(cpu_rd_data),
    .cpu_wr_en(cpu_wr_en), .cpu_wr_addr(cpu_wr_addr),
    .cpu_wr_data(cpu_wr_data), .cpu_wr_be(cpu_wr_be),
    .dma_rd_valid(mem_rd_valid), .dma_rd_ready(mem_rd_ready), .dma_rd_addr(mem_rd_addr),
    .dma_rsp_valid(mem_rsp_valid), .dma_rsp_ready(mem_rsp_ready), .dma_rsp_data(mem_rsp_data),
    .dma_wr_valid(mem_wr_valid), .dma_wr_ready(mem_wr_ready), .dma_wr_addr(mem_wr_addr),
    .dma_wr_data(mem_wr_data), .dma_wr_be(mem_wr_be),
    .dma_rd_hold(dma_rd_hold), .dma_wr_hold(dma_wr_hold)
  );

  vpu_npc_model #(
    .X_ID_WIDTH(X_ID_WIDTH),
    .X_HARTID_WIDTH(1),
    .ISSUE_TO_REGISTER(ISSUE_TO_REGISTER),
    .REGISTER_TO_COMMIT(REGISTER_TO_COMMIT),
    .RESULT_ACCEPT_DELAY(RESULT_ACCEPT_DELAY)
  ) u_npc (
    .clk(clk), .rst(rst), .xif(xif),
    .imem_en(imem_en), .imem_addr(imem_addr), .imem_data(imem_data),
    .cpu_rd_en(cpu_rd_en), .cpu_rd_addr(cpu_rd_addr), .cpu_rd_data(cpu_rd_data),
    .cpu_wr_en(cpu_wr_en), .cpu_wr_addr(cpu_wr_addr),
    .cpu_wr_data(cpu_wr_data), .cpu_wr_be(cpu_wr_be),
    .halted(halted), .error(npc_error), .pc_out(pc_out), .retire_count(retire_count)
  );

  // ---------------------------------------------------------------------------
  // Test data / golden model
  // ---------------------------------------------------------------------------
  logic signed [7:0]  A [0:3][0:11];
  logic signed [7:0]  B [0:11][0:3];
  logic signed [31:0] bias [0:3][0:3];
  logic [15:0]        multiplier;
  logic [4:0]         shift_amount;
  logic signed [7:0]  zero_point;
  logic               relu_enable;

  logic [127:0]       packed_a [0:2];
  logic [127:0]       packed_b [0:2];
  logic [127:0]       packed_bias [0:3];
  logic [127:0]       packed_cfg;
  logic [127:0]       exp_c_row [0:3];
  logic [127:0]       exp_out_row;

  logic [31:0]        prog_image [0:63];
  integer             prog_len;

  integer             watchdog;

  // Interface-visible offload latency accounting
  integer             op_cycles [0:4];
  integer             op_count  [0:4];
  logic [2:0]         cur_op;
  integer             cyc_counter;
  logic               cmd_active;

  assign dma_rd_hold = (watchdog % 7) == 4;
  assign dma_wr_hold = (watchdog % 5) == 2;
  assign dbg_addr    = OUT_ADDR;

  always_ff @(posedge clk) begin
    if (rst)
      watchdog <= 0;
    else if (watchdog < 1000000)
      watchdog <= watchdog + 1;
  end

  // ---------------------------------------------------------------------------
  // Instruction encoders
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] enc_addi(input logic [4:0] rd, input logic [4:0] rs1,
                                           input logic [11:0] imm);
    enc_addi = {imm, rs1, 3'b000, rd, 7'b0010011};
  endfunction

  function automatic logic [31:0] enc_lui(input logic [4:0] rd, input logic [19:0] imm20);
    enc_lui = {imm20, rd, 7'b0110111};
  endfunction

  function automatic logic [7:0] requant(input logic signed [31:0] c_val,
                                         input logic signed [31:0] b_val);
    logic signed [63:0] sum_v, scaled_v, shifted_v, quant_v;
    begin
      sum_v     = $signed(c_val) + $signed(b_val);
      scaled_v  = sum_v * $signed(multiplier);
      shifted_v = scaled_v >>> shift_amount;
      quant_v   = shifted_v + $signed({{56{zero_point[7]}}, zero_point});
      if (relu_enable && (quant_v < 0))
        quant_v = 0;
      if (quant_v > 127)
        requant = 8'h7f;
      else if (quant_v < -128)
        requant = 8'h80;
      else
        requant = quant_v[7:0];
    end
  endfunction

  function automatic logic [2:0] classify_cmd(input logic [31:0] instr);
    if (is_minitensor_load(instr))
      classify_cmd = 0;
    else if (is_minitensor_store(instr))
      classify_cmd = 1;
    else if (is_tensor_gemm(instr))
      classify_cmd = 2;
    else if (is_tensor_epilogue(instr))
      classify_cmd = 3;
    else
      classify_cmd = 4;
  endfunction

  task automatic build_program();
    begin
      prog_image[0]  = enc_lui (5'd1,  20'd1);            // x1  = 0x1000 A base
      prog_image[1]  = enc_addi(5'd2,  5'd0,  12'd768);   // x2  = 0x300
      prog_image[2]  = enc_lui (5'd3,  20'd1);            // x3  = 0x1000
      prog_image[3]  = enc_addi(5'd3,  5'd3,  12'd48);    // x3  = 0x1030 B base
      prog_image[4]  = enc_addi(5'd4,  5'd0,  12'd771);   // x4  = 0x303
      prog_image[5]  = enc_lui (5'd5,  20'd1);
      prog_image[6]  = enc_addi(5'd5,  5'd5,  12'd256);   // x5  = 0x1100 bias base
      prog_image[7]  = enc_addi(5'd6,  5'd0,  12'd1040);  // x6  = 0x410
      prog_image[8]  = enc_lui (5'd7,  20'd1);
      prog_image[9]  = enc_addi(5'd7,  5'd7,  12'd320);   // x7  = 0x1140 config
      prog_image[10] = enc_addi(5'd8,  5'd0,  12'd276);   // x8  = 0x114
      prog_image[11] = enc_addi(5'd10, 5'd0,  12'd8);     // x10 = 0x008 C=8 no acc
      prog_image[12] = enc_addi(5'd11, 5'd0,  12'd1025);  // x11 = 0x401 A=1 B=4
      prog_image[13] = enc_addi(5'd12, 5'd0,  12'd264);   // x12 = 0x108 C=8 acc=1
      prog_image[14] = enc_addi(5'd13, 5'd0,  12'd1282);  // x13 = 0x502 A=2 B=5
      prog_image[15] = enc_lui (5'd14, 20'd1);
      prog_image[16] = enc_addi(5'd14, 5'd14, 12'd8);     // x14 = 0x1008 C=8 bias=16
      prog_image[17] = enc_lui (5'd15, 20'd1);
      prog_image[18] = enc_addi(5'd15, 5'd15, 12'd1048);  // x15 = 0x1418 out=24 cfg=20
      prog_image[19] = enc_lui (5'd16, 20'd1);
      prog_image[20] = enc_addi(5'd16, 5'd16, 12'd512);   // x16 = 0x1200 store addr
      prog_image[21] = enc_addi(5'd17, 5'd0,  12'd280);   // x17 = 0x118 out=24 count=1
      prog_image[22] = make_minitensor_load(5'd0, 5'd1, 5'd2);      // A0..A2 -> UB[0:2]
      prog_image[23] = make_minitensor_load(5'd0, 5'd3, 5'd4);      // B0..B2 -> UB[3:5]
      prog_image[24] = make_minitensor_load(5'd0, 5'd5, 5'd6);      // bias  -> UB[16:19]
      prog_image[25] = make_minitensor_load(5'd0, 5'd7, 5'd8);      // config-> UB[20]
      prog_image[26] = make_tensor_gemm(5'd0, 5'd2,  5'd10);        // C = A0*B0
      prog_image[27] = make_tensor_gemm(5'd0, 5'd11, 5'd12);        // C += A1*B1
      prog_image[28] = make_tensor_gemm(5'd0, 5'd13, 5'd12);        // C += A2*B2
      prog_image[29] = make_tensor_epilogue(5'd0, 5'd14, 5'd15);    // out = quant(C)
      prog_image[30] = make_minitensor_store(5'd0, 5'd16, 5'd17);   // out -> memory
      prog_image[31] = 32'h0010_0073;                                // ebreak
      prog_len    = 32;
    end
  endtask

  task automatic init_data();
    logic [31:0] seed;
    begin
      seed = 32'h1357_9bdf;
      for (int i = 0; i < 4; i = i + 1) begin
        for (int k = 0; k < 12; k = k + 1) begin
          seed  = seed * 32'd1664525 + 32'd1013904223;
          A[i][k] = $signed({1'b0, seed[2:0]}) - 8'sd3;
        end
      end
      for (int k = 0; k < 12; k = k + 1) begin
        for (int j = 0; j < 4; j = j + 1) begin
          seed  = seed * 32'd1664525 + 32'd1013904223;
          B[k][j] = $signed({1'b0, seed[2:0]}) - 8'sd3;
        end
      end
      for (int i = 0; i < 4; i = i + 1) begin
        for (int j = 0; j < 4; j = j + 1) begin
          seed  = seed * 32'd1664525 + 32'd1013904223;
          bias[i][j] = $signed({1'b0, seed[6:0]}) - 32'sd64;
        end
      end
      multiplier   = 16'd16;
      shift_amount = 5'd2;
      zero_point   = -8'sd5;
      relu_enable  = 1'b1;
    end
  endtask

  task automatic build_tiles();
    logic signed [63:0] acc;
    begin
      // A tiles: row-major 4x4 slices over K
      for (int t = 0; t < 3; t = t + 1) begin
        packed_a[t] = '0;
        for (int b = 0; b < 16; b = b + 1)
          packed_a[t][8*b +: 8] = A[b/4][4*t + (b%4)];
      end
      // B tiles: row-major 4x4 slices over K
      for (int t = 0; t < 3; t = t + 1) begin
        packed_b[t] = '0;
        for (int b = 0; b < 16; b = b + 1)
          packed_b[t][8*b +: 8] = B[4*t + (b/4)][b%4];
      end
      // Bias rows: four packed INT32 each
      for (int i = 0; i < 4; i = i + 1) begin
        packed_bias[i] = '0;
        for (int j = 0; j < 4; j = j + 1)
          packed_bias[i][32*j +: 32] = bias[i][j];
      end
      // Quant config row
      packed_cfg = '0;
      packed_cfg[15:0]  = multiplier;
      packed_cfg[20:16] = shift_amount;
      packed_cfg[28:21] = zero_point;
      packed_cfg[29]    = relu_enable;

      // Golden INT32 accumulator and INT8 output
      exp_out_row = '0;
      for (int i = 0; i < 4; i = i + 1) begin
        exp_c_row[i] = '0;
        for (int j = 0; j < 4; j = j + 1) begin
          acc = 0;
          for (int k = 0; k < 12; k = k + 1)
            acc = acc + (A[i][k] * B[k][j]);
          exp_c_row[i][32*j +: 32] = acc[31:0];
          exp_out_row[8*(4*i + j) +: 8] = requant(acc[31:0], bias[i][j]);
        end
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Memory preload helpers
  // ---------------------------------------------------------------------------
  task automatic host_write_row(input logic [31:0] addr, input logic [127:0] data);
    begin
      @(negedge clk);
      host_wr_en   = 1'b1;
      host_wr_addr = addr;
      host_wr_data = data;
      host_wr_be   = 16'hffff;
      @(negedge clk);
      host_wr_en   = 1'b0;
    end
  endtask

  task automatic preload_all();
    logic [127:0] row;
    begin
      for (int i = 0; i < prog_len; i = i + 4) begin
        row = '0;
        for (int b = 0; b < 4; b = b + 1)
          if ((i + b) < prog_len)
            row[32*b +: 32] = prog_image[i + b];
        host_write_row(PROG_BASE + 32'(i*4), row);
      end
      for (int t = 0; t < 3; t = t + 1)
        host_write_row(A_BASE + 32'(16*t), packed_a[t]);
      for (int t = 0; t < 3; t = t + 1)
        host_write_row(B_BASE + 32'(16*t), packed_b[t]);
      for (int i = 0; i < 4; i = i + 1)
        host_write_row(BIAS_BASE + 32'(16*i), packed_bias[i]);
      host_write_row(CONFIG_ADDR, packed_cfg);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------------
  task automatic read_ub_check(input logic [7:0] addr, input logic [127:0] expected,
                               input string label);
    begin
      @(negedge clk);
      ub_rd_addr = addr;
      ub_rd_en   = 1'b1;
      @(posedge clk);
      #1;
      if (!ub_rd_valid || (ub_rd_data !== expected))
        $fatal(1, "UB mismatch %s row=%0d got=%h expected=%h",
               label, addr, ub_rd_data, expected);
      @(negedge clk);
      ub_rd_en = 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Offload latency monitor (uses only CV-X-IF pins)
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      cmd_active  <= 1'b0;
      cyc_counter <= 0;
      cur_op      <= 0;
      for (int unsigned i = 0; i < 5; i = i + 1) begin
        op_cycles[i] <= 0;
        op_count[i]  <= 0;
      end
    end else begin
      if (xif.issue_valid && xif.issue_ready && xif.issue_resp.accept) begin
        cmd_active  <= 1'b1;
        cyc_counter <= 1;
        cur_op      <= classify_cmd(xif.issue_req.instr);
      end else if (cmd_active) begin
        if (xif.result_valid && xif.result_ready) begin
          op_cycles[cur_op] <= op_cycles[cur_op] + cyc_counter;
          op_count[cur_op]  <= op_count[cur_op] + 1;
          cmd_active        <= 1'b0;
        end else begin
          cyc_counter <= cyc_counter + 1;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  initial begin
    rst          = 1'b1;
    host_wr_en   = 1'b0;
    host_wr_addr = '0;
    host_wr_data = '0;
    host_wr_be   = '0;
    ub_rd_en     = 1'b0;
    ub_rd_addr   = '0;

    build_program();
    init_data();
    build_tiles();
    preload_all();

    repeat (4) @(negedge clk);
    rst = 1'b0;

    wait (halted);
    repeat (4) @(negedge clk);

    if (npc_error)
      $fatal(1, "NPC reported an accelerator error");
    if (pc_out !== 32'h0000_007C)
      $fatal(1, "NPC final PC mismatch: %h", pc_out);
    if (dma_busy)
      $fatal(1, "DMA still busy after halt");

    // INT32 accumulator rows in the UB (multi-K accumulation)
    read_ub_check(UB_C + 8'd0, exp_c_row[0], "C0");
    read_ub_check(UB_C + 8'd1, exp_c_row[1], "C1");
    read_ub_check(UB_C + 8'd2, exp_c_row[2], "C2");
    read_ub_check(UB_C + 8'd3, exp_c_row[3], "C3");

    // Tiles staged in the UB by MT_LOAD
    read_ub_check(UB_A + 8'd0, packed_a[0], "A0");
    read_ub_check(UB_A + 8'd1, packed_a[1], "A1");
    read_ub_check(UB_A + 8'd2, packed_a[2], "A2");
    read_ub_check(UB_B + 8'd0, packed_b[0], "B0");
    read_ub_check(UB_B + 8'd1, packed_b[1], "B1");
    read_ub_check(UB_B + 8'd2, packed_b[2], "B2");
    read_ub_check(UB_BIAS + 8'd0, packed_bias[0], "BIAS0");
    read_ub_check(UB_BIAS + 8'd1, packed_bias[1], "BIAS1");
    read_ub_check(UB_BIAS + 8'd2, packed_bias[2], "BIAS2");
    read_ub_check(UB_BIAS + 8'd3, packed_bias[3], "BIAS3");
    read_ub_check(UB_CFG, packed_cfg, "CFG");

    // INT8 epilogue result in the UB
    read_ub_check(UB_OUT, exp_out_row, "OUT");

    // Final memory image after MT_STORE
    if (dbg_data !== exp_out_row)
      $fatal(1, "closed-loop memory mismatch got=%h expected=%h", dbg_data, exp_out_row);

    $display("INFO: retired %0d instructions in %0d cycles", retire_count, watchdog);
    $display("INFO: final INT8 row = %h", exp_out_row);
    $display("INFO: command latency cycles/count: LOAD %0d/%0d  STORE %0d/%0d  GEMM %0d/%0d  EPILOGUE %0d/%0d",
             op_cycles[0], op_count[0], op_cycles[1], op_count[1],
             op_cycles[2], op_count[2], op_cycles[3], op_count[3]);
    $display("PASS: NPC model drove the full tensor closed loop (LOAD/GEMM x3/EPILOGUE/STORE)");
    $finish;
  end

endmodule
