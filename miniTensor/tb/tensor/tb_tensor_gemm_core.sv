`timescale 1ns/1ps

module tb_tensor_gemm_core;
  logic clk;
  logic rst;
  always #5 clk = ~clk;

  logic cmd_valid, cmd_ready;
  logic [127:0] cmd_a_tile, cmd_b_tile;
  logic result_valid, result_ready;
  logic [511:0] result_data;
  logic [511:0] cmd_acc_init;

  tensor_gemm_core dut (
    .clk,
    .rst,
    .cmd_valid,
    .cmd_ready,
    .cmd_a_tile,
    .cmd_b_tile,
    .cmd_acc_init,
    .result_valid,
    .result_ready,
    .result_data
  );

  function automatic logic [127:0] pack_i8(input integer values [0:15]);
    logic [127:0] data_out;
    for (int i = 0; i < 16; i++) data_out[8*i +: 8] = values[i][7:0];
    return data_out;
  endfunction

  function automatic logic [511:0] gemm_reference(
      input logic [127:0] a_tile, input logic [127:0] b_tile);
    logic signed [7:0] a_value, b_value;
    logic signed [31:0] sum;
    logic [511:0] reference;
    reference = '0;
    for (int r = 0; r < 4; r++) begin
      for (int c = 0; c < 4; c++) begin
        sum = '0;
        for (int k = 0; k < 4; k++) begin
          a_value = a_tile[8*(4*r+k) +: 8];
          b_value = b_tile[8*(4*k+c) +: 8];
          sum = sum + a_value * b_value;
        end
        reference[32*(4*r+c) +: 32] = sum;
      end
    end
    return reference;
  endfunction

  function automatic logic [511:0] gemm_reference_with_init(
      input logic [127:0] a_tile, input logic [127:0] b_tile,
      input logic [511:0] acc_init);
    logic signed [31:0] base_value;
    logic signed [31:0] init_value;
    logic signed [31:0] sum_value;
    logic [511:0] reference;
    reference = gemm_reference(a_tile, b_tile);
    for (int i = 0; i < 16; i++) begin
      base_value = $signed(reference[32*i +: 32]);
      init_value = $signed(acc_init[32*i +: 32]);
      sum_value = base_value + init_value;
      reference[32*i +: 32] = sum_value;
    end
    return reference;
  endfunction

  task automatic run_case(
      input logic [127:0] a_tile, input logic [127:0] b_tile,
      input logic [511:0] acc_init);
    logic [511:0] expected_data;
    logic [511:0] held_data;
    begin
      expected_data = gemm_reference_with_init(a_tile, b_tile, acc_init);
      @(negedge clk);
      cmd_a_tile = a_tile;
      cmd_b_tile = b_tile;
      cmd_acc_init = acc_init;
      cmd_valid = 1'b1;
      while (!cmd_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      cmd_valid = 1'b0;
      while (!result_valid) @(negedge clk);
      if (result_data !== expected_data)
        $fatal(1, "GEMM result mismatch: got %h expected %h",
               result_data, expected_data);
      held_data = result_data;
      repeat (2) begin
        @(negedge clk);
        if (!result_valid || result_data !== held_data)
          $fatal(1, "GEMM result changed under backpressure");
      end
      result_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      result_ready = 1'b0;
    end
  endtask

  integer a_values [0:15];
  integer b_values [0:15];
  initial begin
    clk = 1'b0;
    rst = 1'b1;
    cmd_valid = 1'b0;
    cmd_a_tile = '0;
    cmd_b_tile = '0;
    cmd_acc_init = '0;
    result_ready = 1'b0;
    for (int i = 0; i < 16; i++) begin
      a_values[i] = (i % 5 == 0) ? 1 : 0;
      b_values[i] = (i * 7) - 50;
    end
    repeat (2) @(posedge clk);
    rst = 1'b0;
    run_case(pack_i8(a_values), pack_i8(b_values), '0);
    for (int test_index = 0; test_index < 25; test_index++) begin
      run_case({$urandom, $urandom, $urandom, $urandom},
               {$urandom, $urandom, $urandom, $urandom}, '0);
    end
    for (int test_index = 0; test_index < 25; test_index++) begin
      run_case({$urandom, $urandom, $urandom, $urandom},
               {$urandom, $urandom, $urandom, $urandom},
               {$urandom, $urandom, $urandom, $urandom,
                $urandom, $urandom, $urandom, $urandom,
                $urandom, $urandom, $urandom, $urandom,
                $urandom, $urandom, $urandom, $urandom});
    end
    $display("PASS: 4x4 signed INT8 GEMM core passed identity and random tests");
    $finish;
  end
endmodule
