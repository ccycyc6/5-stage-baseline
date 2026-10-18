`timescale 1ns/1ps
/* verilator lint_off UNUSEDSIGNAL */

// Shared byte-addressed testbench memory for the miniTensor NPC model.
// 128-bit little-endian rows back both 32-bit CPU/instruction accesses and
// 128-bit miniTensor DMA transfers.  DMA latency and ready back-pressure are
// configurable so the closed loop is exercised under stalls.
module mt_mem_model #(
  parameter int unsigned DEPTH_ROWS     = 1024,
  parameter int unsigned DMA_RD_LATENCY = 1,
  parameter int unsigned DMA_WR_LATENCY = 1
) (
  input  logic               clk,
  input  logic               rst,

  input  logic               host_wr_en,
  input  logic [31:0]        host_wr_addr,
  input  logic [127:0]       host_wr_data,
  input  logic [15:0]        host_wr_be,
  input  logic [31:0]        dbg_addr,
  output logic [127:0]       dbg_data,

  input  logic               imem_en,
  input  logic [31:0]        imem_addr,
  output logic [31:0]        imem_data,

  input  logic               cpu_rd_en,
  input  logic [31:0]        cpu_rd_addr,
  output logic [31:0]        cpu_rd_data,
  input  logic               cpu_wr_en,
  input  logic [31:0]        cpu_wr_addr,
  input  logic [31:0]        cpu_wr_data,
  input  logic [3:0]         cpu_wr_be,

  input  logic               dma_rd_valid,
  output logic               dma_rd_ready,
  input  logic [31:0]        dma_rd_addr,
  output logic               dma_rsp_valid,
  input  logic               dma_rsp_ready,
  output logic [127:0]       dma_rsp_data,

  input  logic               dma_wr_valid,
  output logic               dma_wr_ready,
  input  logic [31:0]        dma_wr_addr,
  input  logic [127:0]       dma_wr_data,
  input  logic [15:0]        dma_wr_be,

  input  logic               dma_rd_hold,
  input  logic               dma_wr_hold
);
  localparam int unsigned ROW_SEL_BITS = $clog2(DEPTH_ROWS);

  logic [127:0] mem [0:DEPTH_ROWS-1];
  integer i;

  function automatic logic [ROW_SEL_BITS-1:0] row_of(input logic [31:0] addr);
    row_of = addr[ROW_SEL_BITS+3:4];
  endfunction

  function automatic logic [31:0] word_at(input logic [31:0] addr);
    word_at = mem[row_of(addr)][32*addr[3:2] +: 32];
  endfunction

  initial begin
    if (DEPTH_ROWS < 2)
      $fatal(1, "mt_mem_model DEPTH_ROWS must be at least 2");
  end

  always_ff @(posedge clk) begin
    if (rst)
      imem_data <= '0;
    else if (imem_en)
      imem_data <= word_at(imem_addr);
  end

  assign cpu_rd_data = cpu_rd_en ? word_at(cpu_rd_addr) : '0;

  always_ff @(posedge clk) begin
    if (cpu_wr_en) begin
      for (i = 0; i < 4; i = i + 1)
        if (cpu_wr_be[i])
          mem[row_of(cpu_wr_addr)][8*(4*cpu_wr_addr[3:2] + i) +: 8]
              <= cpu_wr_data[8*i +: 8];
    end
  end

  always_ff @(posedge clk) begin
    if (host_wr_en) begin
      for (i = 0; i < 16; i = i + 1)
        if (host_wr_be[i])
          mem[row_of(host_wr_addr)][8*i +: 8] <= host_wr_data[8*i +: 8];
    end
  end

  assign dbg_data = mem[row_of(dbg_addr)];

  logic               rd_busy_q;
  logic [7:0]         rd_cnt_q;
  logic               rsp_valid_q;
  logic [127:0]       rsp_data_q;
  logic [31:0]        rd_addr_q;

  wire dma_rd_fire  = dma_rd_valid && dma_rd_ready;
  wire dma_rsp_fire = dma_rsp_valid && dma_rsp_ready;

  assign dma_rd_ready  = !rd_busy_q && !rsp_valid_q && !dma_rd_hold;
  assign dma_rsp_valid = rsp_valid_q;
  assign dma_rsp_data  = rsp_data_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      rd_busy_q   <= 1'b0;
      rd_cnt_q    <= '0;
      rsp_valid_q <= 1'b0;
      rsp_data_q  <= '0;
      rd_addr_q   <= '0;
    end else begin
      if (dma_rd_fire) begin
        rd_busy_q <= 1'b1;
        rd_cnt_q  <= 8'(DMA_RD_LATENCY);
        rd_addr_q <= dma_rd_addr;
      end else if (rd_busy_q) begin
        if (rd_cnt_q == 0) begin
          rd_busy_q   <= 1'b0;
          rsp_valid_q <= 1'b1;
          rsp_data_q  <= mem[row_of(rd_addr_q)];
        end else begin
          rd_cnt_q <= rd_cnt_q - 1'b1;
        end
      end
      if (dma_rsp_fire)
        rsp_valid_q <= 1'b0;
    end
  end

  logic               wr_busy_q;
  logic [7:0]         wr_cnt_q;

  wire dma_wr_fire = dma_wr_valid && dma_wr_ready;

  assign dma_wr_ready = !wr_busy_q && !dma_wr_hold;

  always_ff @(posedge clk) begin
    if (rst) begin
      wr_busy_q <= 1'b0;
      wr_cnt_q  <= '0;
    end else begin
      if (dma_wr_fire) begin
        for (i = 0; i < 16; i = i + 1)
          if (dma_wr_be[i])
            mem[row_of(dma_wr_addr)][8*i +: 8] <= dma_wr_data[8*i +: 8];
        wr_busy_q <= 1'b1;
        wr_cnt_q  <= 8'(DMA_WR_LATENCY);
      end else if (wr_busy_q) begin
        if (wr_cnt_q == 0)
          wr_busy_q <= 1'b0;
        else
          wr_cnt_q <= wr_cnt_q - 1'b1;
      end
    end
  end
endmodule
