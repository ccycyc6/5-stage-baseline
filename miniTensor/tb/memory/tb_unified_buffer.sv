`timescale 1ns/1ps

module tb_unified_buffer;
  localparam int unsigned DATA_WIDTH = 128;
  localparam int unsigned DEPTH = 256;
  localparam int unsigned ADDR_WIDTH = $clog2(DEPTH);

  logic clk;
  logic rst;
  logic wr_en;
  logic [ADDR_WIDTH-1:0] wr_addr;
  logic [DATA_WIDTH-1:0] wr_data;
  logic [DATA_WIDTH/8-1:0] wr_be;
  logic rd_en;
  logic [ADDR_WIDTH-1:0] rd_addr;
  logic rd_valid;
  logic [DATA_WIDTH-1:0] rd_data;

  unified_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) dut (
    .clk, .rst,
    .wr_en, .wr_addr, .wr_data, .wr_be,
    .rd_en, .rd_addr, .rd_valid, .rd_data
  );

  always #5 clk = ~clk;

  task automatic write_line(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [DATA_WIDTH-1:0] data,
    input logic [DATA_WIDTH/8-1:0] byte_enable
  );
    @(negedge clk);
    wr_en = 1'b1;
    wr_addr = addr;
    wr_data = data;
    wr_be = byte_enable;
    @(negedge clk);
    wr_en = 1'b0;
  endtask

  task automatic check_line(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [DATA_WIDTH-1:0] expected
  );
    @(negedge clk);
    rd_en = 1'b1;
    rd_addr = addr;
    if (rd_valid)
      $fatal(1, "rd_valid asserted before synchronous read completed");
    @(posedge clk);
    #1;
    if (!rd_valid || rd_data !== expected)
      $fatal(1, "read mismatch at address %0d: got %h expected %h",
             addr, rd_data, expected);
    @(negedge clk);
    rd_en = 1'b0;
    @(posedge clk);
    #1;
    if (rd_valid)
      $fatal(1, "rd_valid did not clear after rd_en was removed");
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    wr_en = 1'b0;
    wr_addr = '0;
    wr_data = '0;
    wr_be = '0;
    rd_en = 1'b0;
    rd_addr = '0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    write_line(8'd3, 128'h00112233445566778899aabbccddeeff, '1);
    check_line(8'd3, 128'h00112233445566778899aabbccddeeff);

    write_line(8'd4, 128'hfedcba98765432100123456789abcdef, '1);
    check_line(8'd4, 128'hfedcba98765432100123456789abcdef);
    check_line(8'd3, 128'h00112233445566778899aabbccddeeff);

    write_line(8'd3, 128'hffeeddccbbaa99887766554433221100,
               16'b1000_0000_0000_0001);
    check_line(8'd3, 128'hff112233445566778899aabbccddee00);
    check_line(8'd4, 128'hfedcba98765432100123456789abcdef);

    $display("PASS: unified buffer synchronous read and byte-mask writes completed");
    $finish;
  end
endmodule
