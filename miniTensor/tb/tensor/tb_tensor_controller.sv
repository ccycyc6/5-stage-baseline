`timescale 1ns/1ps

module tb_tensor_controller;
  localparam int unsigned AW = 8;
  logic clk, rst;
  always #5 clk = ~clk;

  logic cmd_valid, cmd_ready, cmd_accumulate;
  logic [AW-1:0] cmd_a_addr, cmd_b_addr, cmd_c_addr;
  logic busy, done;
  logic ctrl_rd_en, ctrl_wr_en;
  logic [AW-1:0] ctrl_rd_addr, ctrl_wr_addr;
  logic [127:0] ctrl_wr_data, ub_rd_data;
  logic [15:0] ctrl_wr_be;
  logic ub_rd_valid;

  logic tb_wr_en;
  logic [AW-1:0] tb_wr_addr;
  logic [127:0] tb_wr_data;
  logic [15:0] tb_wr_be;

  logic [127:0] expected_rows [0:3];
  integer write_count;

  tensor_controller #(.UB_ADDR_WIDTH(AW)) dut (
    .clk, .rst,
    .cmd_valid, .cmd_ready,
    .cmd_a_addr, .cmd_b_addr, .cmd_c_addr, .cmd_accumulate,
    .busy, .done,
    .ub_rd_en(ctrl_rd_en), .ub_rd_addr(ctrl_rd_addr),
    .ub_rd_valid, .ub_rd_data,
    .ub_wr_en(ctrl_wr_en), .ub_wr_addr(ctrl_wr_addr),
    .ub_wr_data(ctrl_wr_data), .ub_wr_be(ctrl_wr_be)
  );

  unified_buffer #(.DATA_WIDTH(128), .DEPTH(256), .ADDR_WIDTH(AW)) ub (
    .clk, .rst,
    .wr_en(tb_wr_en || ctrl_wr_en),
    .wr_addr(tb_wr_en ? tb_wr_addr : ctrl_wr_addr),
    .wr_data(tb_wr_en ? tb_wr_data : ctrl_wr_data),
    .wr_be(tb_wr_en ? tb_wr_be : ctrl_wr_be),
    .rd_en(ctrl_rd_en), .rd_addr(ctrl_rd_addr),
    .rd_valid(ub_rd_valid), .rd_data(ub_rd_data)
  );

  task automatic write_ub(input logic [AW-1:0] addr,
                          input logic [127:0] data);
    begin
      @(negedge clk);
      tb_wr_addr = addr;
      tb_wr_data = data;
      tb_wr_be = '1;
      tb_wr_en = 1'b1;
      @(negedge clk);
      tb_wr_en = 1'b0;
    end
  endtask

  task automatic issue(input logic accumulate);
    begin
      @(negedge clk);
      cmd_a_addr = 8'd10;
      cmd_b_addr = 8'd11;
      cmd_c_addr = 8'd20;
      cmd_accumulate = accumulate;
      cmd_valid = 1'b1;
      while (!cmd_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      cmd_valid = 1'b0;
      if (!busy) $fatal(1, "tensor controller did not enter busy state");
      while (!done) @(negedge clk);
    end
  endtask

  always_ff @(posedge clk) begin
    if (rst) begin
      write_count <= 0;
    end else if (ctrl_wr_en) begin
      if (ctrl_wr_be !== '1)
        $fatal(1, "tensor controller byte enable mismatch");
      if (ctrl_wr_addr !== (AW'(20 + write_count)))
        $fatal(1, "tensor write address mismatch: got %0d expected %0d",
               ctrl_wr_addr, 20 + write_count);
      if (ctrl_wr_data !== expected_rows[write_count])
        $fatal(1, "tensor write data mismatch at row %0d", write_count);
      write_count <= write_count + 1;
    end
  end

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    cmd_valid = 1'b0;
    cmd_a_addr = '0;
    cmd_b_addr = '0;
    cmd_c_addr = '0;
    cmd_accumulate = 1'b0;
    tb_wr_en = 1'b0;
    tb_wr_addr = '0;
    tb_wr_data = '0;
    tb_wr_be = '0;
    expected_rows[0] = 128'h00000004_00000014_0000000e_00000004;
    expected_rows[1] = 128'h00000000_0000000c_00000002_fffffffc;
    expected_rows[2] = 128'h0000001e_fffffffa_fffffffa_00000002;
    expected_rows[3] = 128'hfffffc02_000000fe_00000106_000000fa;

    repeat (2) @(posedge clk);
    rst = 1'b0;
    // A/B match the top-level GEMM case, and C is initialized to its result.
    write_ub(8'd10, 128'hff017f80_0100fe05_020100ff_04030201);
    write_ub(8'd11, 128'h0102ff00_000103ff_fe000102_02ff0001);
    write_ub(8'd20, 128'h00000002_0000000a_00000007_00000002);
    write_ub(8'd21, 128'h00000000_00000006_00000001_fffffffe);
    write_ub(8'd22, 128'h0000000f_fffffffd_fffffffd_00000001);
    write_ub(8'd23, 128'hfffffe01_0000007f_00000083_0000007d);

    issue(1'b1);
    if (write_count != 4)
      $fatal(1, "tensor controller write count mismatch: %0d", write_count);
    $display("PASS: tensor controller synchronous UB reads, accumulate and writes completed");
    $finish;
  end
endmodule
