`timescale 1ns/1ps

module tb_vpu_vector_controller;
  import vpu_pkg::*;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;
  logic cmd_valid, cmd_ready, cmd_kill, result_valid, result_ready;
  logic [31:0] cmd_instr;
  logic [3:0] cmd_id, result_id;
  logic [127:0] result_data;
  logic [4:0] result_vd;
  logic load_valid, load_ready;
  logic [4:0] load_addr;
  logic [127:0] load_data;
  logic [15:0] load_be;

  vpu_vector_controller dut (
    .clk, .rst, .cmd_valid, .cmd_ready, .cmd_instr, .cmd_id, .cmd_kill,
    .result_valid, .result_ready, .result_id, .result_data, .result_vd,
    .load_valid, .load_ready, .load_addr, .load_data, .load_be
  );

`ifdef TRACE
  initial begin
    $dumpfile("vector_controller.vcd");
    $dumpvars(0, tb_vpu_vector_controller);
  end
`endif

  task automatic load_vector(input logic [4:0] addr, input logic [127:0] data);
    integer guard;
    begin
      @(negedge clk); load_addr = addr; load_data = data; load_be = '1; load_valid = 1;
      guard = 0;
      while (!load_ready && guard < 100) begin @(negedge clk); guard = guard + 1; end
      if (!load_ready) $fatal(1, "load handshake timeout addr=%0d", addr);
      @(posedge clk); @(negedge clk); load_valid = 0;
    end
  endtask

  task automatic run_cmd(input logic [31:0] instr, input logic [3:0] id,
                         input logic [127:0] expected, input logic [4:0] vd);
    integer guard;
    begin
      @(negedge clk); cmd_instr = instr; cmd_id = id; cmd_valid = 1;
      // Allow combinational instruction decode to settle before sampling ready.
      #1;
      guard = 0;
      while (!cmd_ready && guard < 100) begin
        @(negedge clk); guard = guard + 1;
      end
      if (!cmd_ready) $fatal(1, "command handshake timeout instr=%h supported=%b", instr,
                             is_vector_instruction(instr));
      @(posedge clk); @(negedge clk); cmd_valid = 0;
      result_ready = 1;
      guard = 0;
      while (!result_valid && guard < 100) begin @(negedge clk); guard = guard + 1; end
      if (!result_valid) $fatal(1, "result handshake timeout id=%0d", id);
      #1;
      if (result_data !== expected || result_id !== id || result_vd !== vd)
        $fatal(1, "vector controller result mismatch: %h", result_data);
      @(posedge clk); @(negedge clk); result_ready = 0;
    end
  endtask

  initial begin
    cmd_valid = 0; cmd_instr = 0; cmd_id = 0; cmd_kill = 0; result_ready = 0;
    load_valid = 0; load_addr = 0; load_data = 0; load_be = 0;
    repeat (2) @(posedge clk); rst = 0;
    // Bytes are shown from MSB to LSB; each operand contains sixteen INT8 lanes.
    load_vector(5'd1, 128'h7f05ff80_7d03fd80_7c02fc80_7b01fb80);
    load_vector(5'd2, 128'h01010101_01010101_01010101_01010101);

    run_cmd({VPU_VECTOR_FUNCT7, 5'd2, 5'd1, VPU_VECTOR_FUNCT3_RELU8, 5'd3, VPU_CUSTOM0_OPCODE},
            4'd1, 128'h7f050000_7d030000_7c020000_7b010000, 5'd3);
    run_cmd({VPU_VECTOR_FUNCT7, 5'd2, 5'd1, VPU_VECTOR_FUNCT3_ADD8, 5'd4, VPU_CUSTOM0_OPCODE},
            4'd2, 128'h80060081_7e04fe81_7d03fd81_7c02fc81, 5'd4);
    // Read back the first result from VRF and apply VRELU8 again.
    run_cmd({VPU_VECTOR_FUNCT7, 5'd2, 5'd3, VPU_VECTOR_FUNCT3_RELU8, 5'd5, VPU_CUSTOM0_OPCODE},
            4'd3, 128'h7f050000_7d030000_7c020000_7b010000, 5'd5);
    $display("PASS: vector instruction fields, controller protocol and VRF integration completed");
    $finish;
  end
endmodule
