`timescale 1ns/1ps

module tb_vpu_dma;
  localparam int unsigned DATA_WIDTH = 128;
  localparam int unsigned UB_DEPTH = 256;
  localparam int unsigned UB_ADDR_WIDTH = $clog2(UB_DEPTH);
  localparam int unsigned TILE_COUNT = 4;

  logic clk, rst;
  always #5 clk = ~clk;

  logic cmd_valid, cmd_ready, cmd_write;
  logic [31:0] cmd_mem_addr;
  logic [UB_ADDR_WIDTH-1:0] cmd_ub_addr;
  logic [7:0] cmd_tile_count;
  logic busy, done;
  logic mem_rd_valid, mem_rd_ready, mem_rsp_valid, mem_rsp_ready;
  logic [31:0] mem_rd_addr;
  logic [DATA_WIDTH-1:0] mem_rsp_data;
  logic mem_wr_valid, mem_wr_ready;
  logic [31:0] mem_wr_addr;
  logic [DATA_WIDTH-1:0] mem_wr_data;
  logic [DATA_WIDTH/8-1:0] mem_wr_be;
  logic ub_wr_en, ub_rd_en, ub_rd_valid;
  logic [UB_ADDR_WIDTH-1:0] ub_wr_addr, ub_rd_addr;
  logic [DATA_WIDTH-1:0] ub_wr_data, ub_rd_data;
  logic [DATA_WIDTH/8-1:0] ub_wr_be;

  logic debug_rd_en;
  logic [UB_ADDR_WIDTH-1:0] debug_rd_addr;
  logic [DATA_WIDTH-1:0] source_mem [0:TILE_COUNT-1];
  logic [DATA_WIDTH-1:0] destination_mem [0:TILE_COUNT-1];
  logic mem_rsp_pending;
  logic [DATA_WIDTH-1:0] mem_pending_data;
  integer request_count, response_count, write_count;

  vpu_dma #(
    .DATA_WIDTH(DATA_WIDTH),
    .UB_ADDR_WIDTH(UB_ADDR_WIDTH),
    .COUNT_WIDTH(8)
  ) dma (
    .clk, .rst,
    .cmd_valid, .cmd_ready, .cmd_write, .cmd_mem_addr, .cmd_ub_addr,
    .cmd_tile_count, .busy, .done,
    .mem_rd_valid, .mem_rd_ready, .mem_rd_addr,
    .mem_rsp_valid, .mem_rsp_ready, .mem_rsp_data,
    .mem_wr_valid, .mem_wr_ready, .mem_wr_addr, .mem_wr_data, .mem_wr_be,
    .ub_wr_en, .ub_wr_addr, .ub_wr_data, .ub_wr_be,
    .ub_rd_en, .ub_rd_addr, .ub_rd_valid, .ub_rd_data
  );

  unified_buffer #(
    .DATA_WIDTH(DATA_WIDTH), .DEPTH(UB_DEPTH), .ADDR_WIDTH(UB_ADDR_WIDTH)
  ) ub (
    .clk, .rst,
    .wr_en(ub_wr_en), .wr_addr(ub_wr_addr), .wr_data(ub_wr_data), .wr_be(ub_wr_be),
    .rd_en(ub_rd_en || debug_rd_en),
    .rd_addr(ub_rd_en ? ub_rd_addr : debug_rd_addr),
    .rd_valid(ub_rd_valid), .rd_data(ub_rd_data)
  );

  assign mem_rd_ready = 1'b1;
  assign mem_wr_ready = 1'b1;

  always_ff @(posedge clk) begin
    if (rst) begin
      mem_rsp_valid <= 1'b0;
      mem_rsp_data <= '0;
      mem_rsp_pending <= 1'b0;
      mem_pending_data <= '0;
      request_count <= 0;
      response_count <= 0;
      write_count <= 0;
    end else begin
      mem_rsp_valid <= mem_rsp_pending;
      mem_rsp_data <= mem_pending_data;
      mem_rsp_pending <= 1'b0;
      if (mem_rd_valid && mem_rd_ready) begin
        if (mem_rd_addr >= TILE_COUNT * 16)
          $fatal(1, "DMA issued out-of-range read address %h", mem_rd_addr);
        mem_pending_data <= source_mem[mem_rd_addr[5:4]];
        mem_rsp_pending <= 1'b1;
        request_count <= request_count + 1;
      end
      if (mem_rsp_valid && mem_rsp_ready)
        response_count <= response_count + 1;
      if (mem_wr_valid && mem_wr_ready) begin
        if (mem_wr_addr < 32'h100 || mem_wr_addr >= 32'h100 + TILE_COUNT * 16)
          $fatal(1, "DMA issued out-of-range write address %h", mem_wr_addr);
        if (mem_wr_be !== '1)
          $fatal(1, "DMA store byte enable mismatch");
        destination_mem[(mem_wr_addr - 32'h100) >> 4] <= mem_wr_data;
        write_count <= write_count + 1;
      end
    end
  end

  task automatic issue_dma(input logic write, input logic [31:0] mem_addr,
                           input logic [7:0] ub_addr, input logic [7:0] count);
    begin
      @(negedge clk);
      cmd_write = write;
      cmd_mem_addr = mem_addr;
      cmd_ub_addr = ub_addr;
      cmd_tile_count = count;
      cmd_valid = 1'b1;
      #1;
      while (!cmd_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      cmd_valid = 1'b0;
      while (busy) @(negedge clk);
      if (!done) $fatal(1, "DMA completion pulse missing");
      @(negedge clk);
    end
  endtask

  task automatic check_ub(input logic [7:0] addr,
                          input logic [DATA_WIDTH-1:0] expected);
    begin
      @(negedge clk);
      debug_rd_en = 1'b1;
      debug_rd_addr = addr;
      @(posedge clk);
      #1;
      if (!ub_rd_valid || ub_rd_data !== expected)
        $fatal(1, "UB mismatch at %0d", addr);
      @(negedge clk);
      debug_rd_en = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    cmd_valid = 1'b0;
    cmd_write = 1'b0;
    cmd_mem_addr = '0;
    cmd_ub_addr = '0;
    cmd_tile_count = '0;
    debug_rd_en = 1'b0;
    debug_rd_addr = '0;
    source_mem[0] = 128'h00112233445566778899aabbccddeeff;
    source_mem[1] = 128'h102132435465768798a9bacbdcedfe0f;
    source_mem[2] = 128'hfedcba98765432100123456789abcdef;
    source_mem[3] = 128'hffeeddccbbaa99887766554433221100;
    destination_mem[0] = '0;
    destination_mem[1] = '0;
    destination_mem[2] = '0;
    destination_mem[3] = '0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    issue_dma(1'b0, 32'h0000_0000, 8'd12, 8'(TILE_COUNT));
    if (request_count != TILE_COUNT || response_count != TILE_COUNT)
      $fatal(1, "DMA load count mismatch: req=%0d rsp=%0d",
             request_count, response_count);
    check_ub(8'd12, source_mem[0]);
    check_ub(8'd13, source_mem[1]);
    check_ub(8'd14, source_mem[2]);
    check_ub(8'd15, source_mem[3]);

    issue_dma(1'b1, 32'h0000_0100, 8'd12, 8'(TILE_COUNT));
    if (write_count != TILE_COUNT)
      $fatal(1, "DMA store count mismatch: %0d", write_count);
    for (int i = 0; i < TILE_COUNT; i++) begin
      if (destination_mem[i] !== source_mem[i])
        $fatal(1, "DMA store mismatch at %0d", i);
    end

    if (busy) $fatal(1, "DMA remained busy after completion");
    $display("PASS: bidirectional DMA copied Memory -> UB -> Memory");
    $finish;
  end
endmodule
