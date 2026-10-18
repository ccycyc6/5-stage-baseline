`timescale 1ns/1ps
module tb_core;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  // core <-> L1I
  logic        imem_req_valid, imem_req_ready;
  logic [31:0] imem_req_addr, imem_rsp_data;
  logic        imem_rsp_valid;
  // core <-> L1D
  logic        dmem_req_valid, dmem_req_ready, dmem_req_write;
  logic [31:0] dmem_req_addr, dmem_req_wdata, dmem_rsp_rdata;
  logic [3:0]  dmem_req_wstrb;
  logic        dmem_rsp_valid;
  // cache maintenance
  logic dcache_flush_req, dcache_flush_done, icache_invalidate, icache_invalidate_done;
  // L1I <-> mem
  logic i_l2_req_valid, i_l2_req_ready, i_l2_req_write, i_l2_rsp_valid, i_l2_rsp_ready;
  logic [31:0] i_l2_req_addr;
  logic [127:0] i_l2_req_wdata, i_l2_rsp_data;
  logic [15:0] i_l2_req_wstrb;
  // L1D <-> mem
  logic d_l2_req_valid, d_l2_req_ready, d_l2_req_write, d_l2_rsp_valid, d_l2_rsp_ready;
  logic [31:0] d_l2_req_addr;
  logic [127:0] d_l2_req_wdata, d_l2_rsp_data;
  logic [15:0] d_l2_req_wstrb;
  // L1D bypass
  logic b_req_valid, b_req_ready, b_req_write, b_rsp_valid, b_rsp_ready;
  logic [31:0] b_req_addr, b_req_wdata, b_rsp_rdata;
  logic [3:0] b_req_wstrb;
  // debug
  logic [31:0] dbg_pc, dbg_instr;
  logic dbg_commit, dbg_halt;
  logic [31:0] dbg_pc_f;
  logic dbg_ifid_valid, dbg_idex_valid, dbg_exmem_valid, dbg_memwb_valid, dbg_if_pending;
  logic [31:0] dbg_exmem_addr, dbg_mem_rsp_data, dbg_mem_result, dbg_memwb_result;
  logic [1:0] dbg_exmem_size;

  ares_l_core #(.RESET_PC(32'h0), .HARTID(4'd0)) u_core (
    .clk, .rst,
    .imem_req_valid, .imem_req_ready, .imem_req_addr, .imem_rsp_valid, .imem_rsp_data,
    .dmem_req_valid, .dmem_req_ready, .dmem_req_write, .dmem_req_addr,
    .dmem_req_wdata, .dmem_req_wstrb, .dmem_rsp_valid, .dmem_rsp_rdata,
    .irq_timer(1'b0), .irq_soft(1'b0), .irq_ext(1'b0),
    .dcache_flush_req, .dcache_flush_done, .icache_invalidate, .icache_invalidate_done,
    .dbg_pc, .dbg_instr, .dbg_commit, .dbg_halt,
    .dbg_pc_f, .dbg_ifid_valid, .dbg_idex_valid, .dbg_exmem_valid, .dbg_memwb_valid, .dbg_if_pending,
    .dbg_exmem_addr, .dbg_exmem_size, .dbg_mem_rsp_data, .dbg_mem_result, .dbg_memwb_result
  );

  ares_l1i u_l1i (
    .clk, .rst,
    .cpu_req_valid(imem_req_valid), .cpu_req_ready(imem_req_ready),
    .cpu_req_addr(imem_req_addr), .cpu_rsp_valid(imem_rsp_valid), .cpu_rsp_data(imem_rsp_data),
    .l2_req_valid(i_l2_req_valid), .l2_req_ready(i_l2_req_ready),
    .l2_req_write(i_l2_req_write), .l2_req_addr(i_l2_req_addr),
    .l2_req_wdata(i_l2_req_wdata), .l2_req_wstrb(i_l2_req_wstrb),
    .l2_rsp_valid(i_l2_rsp_valid), .l2_rsp_ready(i_l2_rsp_ready), .l2_rsp_rdata(i_l2_rsp_data),
    .invalidate(icache_invalidate), .invalidate_done(icache_invalidate_done), .busy()
  );

  ares_l1d u_l1d (
    .clk, .rst,
    .cpu_req_valid(dmem_req_valid), .cpu_req_ready(dmem_req_ready),
    .cpu_req_write(dmem_req_write), .cpu_req_addr(dmem_req_addr),
    .cpu_req_wdata(dmem_req_wdata), .cpu_req_wstrb(dmem_req_wstrb),
    .cpu_rsp_valid(dmem_rsp_valid), .cpu_rsp_rdata(dmem_rsp_rdata),
    .l2_req_valid(d_l2_req_valid), .l2_req_ready(d_l2_req_ready),
    .l2_req_write(d_l2_req_write), .l2_req_addr(d_l2_req_addr),
    .l2_req_wdata(d_l2_req_wdata), .l2_req_wstrb(d_l2_req_wstrb),
    .l2_rsp_valid(d_l2_rsp_valid), .l2_rsp_ready(d_l2_rsp_ready), .l2_rsp_rdata(d_l2_rsp_data),
    .bypass_req_valid(b_req_valid), .bypass_req_ready(b_req_ready),
    .bypass_req_write(b_req_write), .bypass_req_addr(b_req_addr),
    .bypass_req_wdata(b_req_wdata), .bypass_req_wstrb(b_req_wstrb),
    .bypass_rsp_valid(b_rsp_valid), .bypass_rsp_ready(b_rsp_ready),
    .bypass_rsp_rdata(b_rsp_rdata), .bypass_rsp_error(1'b0),
    .flush_req(dcache_flush_req), .flush_done(dcache_flush_done), .busy()
  );

  tb_l2_mem #(.MEM_FILE("build/core_test.hex")) u_mem (
    .clk, .rst,
    .req0_valid(i_l2_req_valid), .req0_ready(i_l2_req_ready), .req0_write(i_l2_req_write),
    .req0_addr(i_l2_req_addr), .req0_wdata(i_l2_req_wdata), .req0_wstrb(i_l2_req_wstrb),
    .rsp0_valid(i_l2_rsp_valid), .rsp0_ready(i_l2_rsp_ready), .rsp0_data(i_l2_rsp_data),
    .req1_valid(d_l2_req_valid), .req1_ready(d_l2_req_ready), .req1_write(d_l2_req_write),
    .req1_addr(d_l2_req_addr), .req1_wdata(d_l2_req_wdata), .req1_wstrb(d_l2_req_wstrb),
    .rsp1_valid(d_l2_rsp_valid), .rsp1_ready(d_l2_rsp_ready), .rsp1_data(d_l2_rsp_data),
    .dbg_word_addr(dbg_word_addr), .dbg_word_data(dbg_word_data)
  );

  logic [15:0] dbg_word_addr;
  logic [31:0] dbg_word_data;

  // Bypass port: only used for uncached addresses, which this test does not use.
  assign b_req_ready = 1'b1;
  assign b_rsp_valid = 1'b0;
  assign b_rsp_rdata = 32'd0;
  assign b_rsp_ready = 1'b1;

  int errors = 0;
  task automatic check_word(input int idx, input logic [31:0] exp, input string name);
    logic [31:0] got;
    dbg_word_addr = 16'h1000/4 + idx[15:0];
    #1;
    got = dbg_word_data;
    if (got !== exp) begin
      $display("FAIL %s: got %08x expected %08x", name, got, exp);
      errors++;
    end else begin
      $display("PASS %s = %08x", name, got);
    end
  endtask


  initial begin
    repeat (8) @(negedge clk);
    rst = 0;
    fork
      begin
        wait (dbg_halt);
        repeat (4) @(negedge clk);
        check_word(0, 32'd55,        "sum 1..10");
        check_word(1, 32'd42,        "mul 7*6");
        check_word(2, 32'd14,        "div 100/7");
        check_word(3, 32'd2,         "rem 100%7");
        check_word(4, 32'h12345678,  "sw 0x12345678");
        check_word(5, 32'h00000078,  "lb 0x78");
        check_word(6, 32'h00000012,  "lbu 0x12");
        check_word(7, 32'h0000beef,  "branch");
        if (errors == 0) $display("*** CORE TEST PASSED ***");
        else             $display("*** CORE TEST FAILED: %0d ***", errors);
        $finish;
      end
      begin
        #2_000_000;
        $display("FAIL: timeout pc=%08x", dbg_pc);
        $finish;
      end
    join
  end
endmodule