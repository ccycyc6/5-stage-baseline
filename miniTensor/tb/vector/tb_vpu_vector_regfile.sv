`timescale 1ns/1ps

module tb_vpu_vector_regfile;
  localparam int VLEN = 128;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;
  logic rd0_en, rd1_en, wr_en;
  logic [4:0] rd0_addr, rd1_addr, wr_addr;
  logic [VLEN-1:0] rd0_data, rd1_data, wr_data;
  logic [VLEN/8-1:0] wr_be;

  vpu_vector_regfile dut (
    .clk, .rst, .rd0_en, .rd0_addr, .rd0_data,
    .rd1_en, .rd1_addr, .rd1_data,
    .wr_en, .wr_addr, .wr_data, .wr_be
  );

  initial begin
    rd0_en = 0; rd1_en = 0; wr_en = 0;
    rd0_addr = 0; rd1_addr = 0; wr_addr = 0; wr_data = 0; wr_be = 0;
    repeat (2) @(posedge clk);
    rst = 0;

    // Full write, then verify two independent reads.
    @(negedge clk);
    wr_en = 1; wr_addr = 5'd3; wr_data = 128'h00112233445566778899aabbccddeeff;
    wr_be = '1;
    @(posedge clk);
    @(negedge clk); wr_en = 0; rd0_en = 1; rd1_en = 1; rd0_addr = 3; rd1_addr = 3;
    #1;
    if (rd0_data !== 128'h00112233445566778899aabbccddeeff ||
        rd1_data !== 128'h00112233445566778899aabbccddeeff)
      $fatal(1, "vector register full write/read mismatch");

    // Masked byte update: only bytes 0 and 15 change.
    @(negedge clk);
    rd0_en = 0; rd1_en = 0; wr_en = 1; wr_addr = 3;
    wr_data = 128'hffeeddccbbaa99887766554433221100;
    wr_be = 16'b1000_0000_0000_0001;
    @(posedge clk);
    @(negedge clk); wr_en = 0; rd0_en = 1; rd0_addr = 3;
    #1;
    if (rd0_data !== 128'hff112233445566778899aabbccddee00)
      $fatal(1, "vector register byte mask mismatch: %h", rd0_data);

    // Reset clears all architectural vector state.
    rst = 1;
    @(posedge clk);
    @(negedge clk); rst = 0; #1;
    if (rd0_data !== 0) $fatal(1, "vector register reset mismatch");
    $display("PASS: vector register file dual-read and byte-mask demo completed");
    $finish;
  end
endmodule
