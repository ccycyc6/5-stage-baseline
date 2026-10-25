`timescale 1ns/1ps
// ARES-P4: four ARES-L clusters, shared L2, DDR3, CLINT/PLIC, mailbox,
// UART/GPIO/SPI, and the miniTensor accelerators.
module ares_p4_soc #(
  parameter logic [31:0] RESET_PC    = 32'h0000_0000,
  parameter              DDR_FILE    = "",
  // Boot ROM / QSPI window sizes; the board build shrinks the unused ROM so
  // the BRAM budget goes to the cache and the on-chip memory image.
  parameter int unsigned L1_BYTES    = 8192,
  parameter int unsigned CACHE_SETS  = 1024,
  parameter int unsigned SCRATCH_WORDS = 12288,
  parameter int unsigned ROM_WORDS   = 16384,
  parameter int unsigned QSPI_WORDS  = 16384,
  parameter int unsigned ONCHIP_WORDS = 65536
) (
  input  logic        clk,
  input  logic        rst,

  input  logic        uart_rx,
  output logic        uart_tx,
  input  logic [31:0] gpio_in,
  output logic [31:0] gpio_out,
  output logic [31:0] gpio_dir,
  output logic        spi_sck,
  output logic        spi_mosi,
  input  logic        spi_miso,
  output logic        spi_cs_n,
  output logic        video_pixel_clk_en,
  output logic        video_hsync,
  output logic        video_vsync,
  output logic        video_de,
  output logic [9:0]  video_tmds_r,
  output logic [9:0]  video_tmds_g,
  output logic [9:0]  video_tmds_b,

  output logic [3:0]  mt_irq,
  output logic [3:0]  dbg_halt,
  output logic [3:0][31:0] dbg_pc,
  output logic [3:0]  dbg_commit,
  output logic [3:0][31:0] dbg_pc_f,
  output logic [3:0]  dbg_ifid_valid,
  output logic [3:0]  dbg_idex_valid,
  output logic [3:0]  dbg_exmem_valid,
  output logic [3:0]  dbg_memwb_valid,
  output logic [3:0]  dbg_if_pending
);
  import ares_pkg::*;

  // ------------------------------------------------------------- cluster buses
  logic [3:0]        c_l2_req_valid, c_l2_req_ready, c_l2_req_write;
  logic [3:0][31:0]  c_l2_req_addr;
  logic [3:0][127:0] c_l2_req_wdata, c_l2_rsp_rdata;
  logic [3:0][15:0]  c_l2_req_wstrb;
  logic [3:0]        c_l2_rsp_valid, c_l2_rsp_ready;

  logic [3:0]        c_irq_timer, c_irq_soft, c_irq_ext;

  genvar h;
  generate
    for (h = 0; h < 4; h = h + 1) begin : g_cluster
      ares_cluster #(.RESET_PC(RESET_PC), .HARTID(4'(h)), .L1_BYTES(L1_BYTES)) u_cluster (
        .clk, .rst,
        .l2_req_valid(c_l2_req_valid[h]), .l2_req_ready(c_l2_req_ready[h]),
        .l2_req_write(c_l2_req_write[h]), .l2_req_addr(c_l2_req_addr[h]),
        .l2_req_wdata(c_l2_req_wdata[h]), .l2_req_wstrb(c_l2_req_wstrb[h]),
        .l2_rsp_valid(c_l2_rsp_valid[h]), .l2_rsp_ready(c_l2_rsp_ready[h]),
        .l2_rsp_rdata(c_l2_rsp_rdata[h]),
        .irq_timer(c_irq_timer[h]), .irq_soft(c_irq_soft[h]), .irq_ext(c_irq_ext[h]),
        .mt_irq(mt_irq[h]),
        .dbg_pc(dbg_pc[h]), .dbg_instr(), .dbg_commit(dbg_commit[h]), .dbg_halt(dbg_halt[h]),
        .dbg_pc_f(dbg_pc_f[h]), .dbg_ifid_valid(dbg_ifid_valid[h]),
        .dbg_idex_valid(dbg_idex_valid[h]), .dbg_exmem_valid(dbg_exmem_valid[h]),
        .dbg_memwb_valid(dbg_memwb_valid[h]), .dbg_if_pending(dbg_if_pending[h])
      );
    end
  endgenerate

  // ------------------------------------------------------------- shared L2
  logic [4:0]        l2_req_valid, l2_req_ready, l2_req_write;
  logic [4:0][31:0]  l2_req_addr;
  logic [4:0][127:0] l2_req_wdata, l2_rsp_rdata;
  logic [4:0][15:0]  l2_req_wstrb;
  logic [4:0]        l2_rsp_valid, l2_rsp_ready, l2_rsp_error;

  assign l2_req_valid[0] = c_l2_req_valid[0];
  assign l2_req_valid[1] = c_l2_req_valid[1];
  assign l2_req_valid[2] = c_l2_req_valid[2];
  assign l2_req_valid[3] = c_l2_req_valid[3];
  assign l2_req_valid[4] = 1'b0; // video port reserved for the video DMA

  assign l2_req_write[0] = c_l2_req_write[0];
  assign l2_req_write[1] = c_l2_req_write[1];
  assign l2_req_write[2] = c_l2_req_write[2];
  assign l2_req_write[3] = c_l2_req_write[3];
  assign l2_req_write[4] = 1'b0;

  assign l2_req_addr[0] = c_l2_req_addr[0];
  assign l2_req_addr[1] = c_l2_req_addr[1];
  assign l2_req_addr[2] = c_l2_req_addr[2];
  assign l2_req_addr[3] = c_l2_req_addr[3];
  assign l2_req_addr[4] = 32'd0;

  assign l2_req_wdata[0] = c_l2_req_wdata[0];
  assign l2_req_wdata[1] = c_l2_req_wdata[1];
  assign l2_req_wdata[2] = c_l2_req_wdata[2];
  assign l2_req_wdata[3] = c_l2_req_wdata[3];
  assign l2_req_wdata[4] = 128'd0;

  assign l2_req_wstrb[0] = c_l2_req_wstrb[0];
  assign l2_req_wstrb[1] = c_l2_req_wstrb[1];
  assign l2_req_wstrb[2] = c_l2_req_wstrb[2];
  assign l2_req_wstrb[3] = c_l2_req_wstrb[3];
  assign l2_req_wstrb[4] = 16'd0;

  assign c_l2_req_ready[0] = l2_req_ready[0];
  assign c_l2_req_ready[1] = l2_req_ready[1];
  assign c_l2_req_ready[2] = l2_req_ready[2];
  assign c_l2_req_ready[3] = l2_req_ready[3];

  assign c_l2_rsp_valid[0] = l2_rsp_valid[0];
  assign c_l2_rsp_valid[1] = l2_rsp_valid[1];
  assign c_l2_rsp_valid[2] = l2_rsp_valid[2];
  assign c_l2_rsp_valid[3] = l2_rsp_valid[3];
  assign c_l2_rsp_rdata[0] = l2_rsp_rdata[0];
  assign c_l2_rsp_rdata[1] = l2_rsp_rdata[1];
  assign c_l2_rsp_rdata[2] = l2_rsp_rdata[2];
  assign c_l2_rsp_rdata[3] = l2_rsp_rdata[3];
  assign l2_rsp_ready[0] = c_l2_rsp_ready[0];
  assign l2_rsp_ready[1] = c_l2_rsp_ready[1];
  assign l2_rsp_ready[2] = c_l2_rsp_ready[2];
  assign l2_rsp_ready[3] = c_l2_rsp_ready[3];
  assign l2_rsp_ready[4] = 1'b1;

  // ------------------------------------------------------------- DDR / MMIO
  logic        ddr_req_valid, ddr_req_ready, ddr_req_write;
  logic [31:0] ddr_req_addr;
  logic [127:0] ddr_req_wdata;
  logic [15:0] ddr_req_wstrb;
  logic        ddr_rsp_valid, ddr_rsp_ready;
  logic [127:0] ddr_rsp_rdata;

  logic        mmio_req_valid, mmio_req_ready, mmio_req_write;
  logic [31:0] mmio_req_addr, mmio_req_wdata, mmio_rsp_rdata;
  logic [3:0]  mmio_req_wstrb;
  logic        mmio_rsp_valid, mmio_rsp_ready;

  logic [31:0] irq_src_ext, irq_src;
  logic        video_irq;

  assign irq_src_ext[5]  = 1'b0; // video vsync
  assign irq_src_ext[6]  = 1'b0; // DMA done
  assign irq_src_ext[12:9] = mt_irq;
  assign irq_src_ext[31:13] = 19'd0;

  ares_l2 #(
    .CACHE_SETS(CACHE_SETS),
    .SCRATCH_WORDS(SCRATCH_WORDS),
    .ROM_WORDS(ROM_WORDS),
    .QSPI_WORDS(QSPI_WORDS)
  ) u_l2 (
    .clk, .rst,
    .req_valid(l2_req_valid), .req_ready(l2_req_ready),
    .req_write(l2_req_write), .req_addr(l2_req_addr),
    .req_wdata(l2_req_wdata), .req_wstrb(l2_req_wstrb),
    .rsp_valid(l2_rsp_valid), .rsp_ready(l2_rsp_ready),
    .rsp_rdata(l2_rsp_rdata), .rsp_error(l2_rsp_error),
    .ddr_req_valid, .ddr_req_ready, .ddr_req_write, .ddr_req_addr,
    .ddr_req_wdata, .ddr_req_wstrb, .ddr_rsp_valid, .ddr_rsp_ready, .ddr_rsp_rdata,
    .mmio_req_valid, .mmio_req_ready, .mmio_req_write, .mmio_req_addr,
    .mmio_req_wdata, .mmio_req_wstrb, .mmio_rsp_valid, .mmio_rsp_ready, .mmio_rsp_rdata
  );

  pango_ddr3_axi #(.DDR_FILE(DDR_FILE), .ONCHIP_DEPTH(ONCHIP_WORDS)) u_ddr (
    .clk, .rst,
    .req_valid(ddr_req_valid), .req_ready(ddr_req_ready), .req_write(ddr_req_write),
    .req_addr(ddr_req_addr), .req_wdata(ddr_req_wdata), .req_wstrb(ddr_req_wstrb),
    .rsp_valid(ddr_rsp_valid), .rsp_ready(ddr_rsp_ready), .rsp_rdata(ddr_rsp_rdata)
  );

  ares_mmio_bus u_mmio (
    .clk, .rst,
    .req_valid(mmio_req_valid), .req_ready(mmio_req_ready), .req_write(mmio_req_write),
    .req_addr(mmio_req_addr), .req_wdata(mmio_req_wdata), .req_wstrb(mmio_req_wstrb),
    .rsp_valid(mmio_rsp_valid), .rsp_ready(mmio_rsp_ready), .rsp_rdata(mmio_rsp_rdata),
    .timer_irq(c_irq_timer), .soft_irq(c_irq_soft), .ext_irq(c_irq_ext),
    .uart_tx, .uart_rx, .gpio_in, .gpio_out, .gpio_dir,
    .spi_sck, .spi_mosi, .spi_miso, .spi_cs_n,
    .video_pixel_clk_en, .video_hsync, .video_vsync, .video_de,
    .video_tmds_r, .video_tmds_g, .video_tmds_b, .video_irq,
    .irq_src_ext(irq_src_ext), .irq_src(irq_src)
  );
endmodule