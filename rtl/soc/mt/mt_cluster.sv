`timescale 1ns/1ps
// One miniTensor instance plus its CV-X-IF host adapter and DMA bridge.
module mt_cluster #(
  parameter int unsigned UB_DEPTH = 256
) (
  input  logic         clk,
  input  logic         rst,

  // Local 32-bit MMIO window.
  input  logic         reg_wr_en,
  input  logic [2:0]   reg_wr_idx,
  input  logic [31:0]  reg_wr_data,
  input  logic         status_rd,
  output logic [31:0]  status,
  output logic [31:0]  result_data,

  // Cluster L2 master for accelerator DMA.
  output logic         l2_req_valid,
  input  logic         l2_req_ready,
  output logic         l2_req_write,
  output logic [31:0]  l2_req_addr,
  output logic [127:0] l2_req_wdata,
  output logic [15:0]  l2_req_wstrb,
  input  logic         l2_rsp_valid,
  output logic         l2_rsp_ready,
  input  logic [127:0] l2_rsp_rdata,

  output logic         mt_irq
);
  core_v_xif #(
    .X_NUM_RS(2),
    .X_ID_WIDTH(4),
    .X_RFR_WIDTH(32),
    .X_RFW_WIDTH(32),
    .X_NUM_HARTS(1),
    .X_HARTID_WIDTH(1),
    .X_MISA(26'd0),
    .X_DUALREAD(0),
    .X_DUALWRITE(0),
    .X_ISSUE_REGISTER_SPLIT(0),
    .X_MEM_WIDTH(32)
  ) xif ();

  logic        mem_rd_valid, mem_rd_ready;
  logic [31:0] mem_rd_addr;
  logic        mem_rsp_valid, mem_rsp_ready;
  logic [127:0] mem_rsp_data;
  logic        mem_wr_valid, mem_wr_ready;
  logic [31:0] mem_wr_addr;
  logic [127:0] mem_wr_data;
  logic [15:0] mem_wr_be;

  mt_cvxif_shim u_shim (
    .clk,
    .rst,
    .reg_wr_en(reg_wr_en),
    .reg_wr_idx(reg_wr_idx),
    .reg_wr_data(reg_wr_data),
    .status_rd(status_rd),
    .status(status),
    .result_data(result_data),
    .xif(xif)
  );

  mini_tensor_top #(
    .X_ID_WIDTH(4),
    .X_HARTID_WIDTH(1),
    .DATA_WIDTH(128),
    .UB_DEPTH(UB_DEPTH),
    .UB_ADDR_WIDTH($clog2(UB_DEPTH)),
    .COUNT_WIDTH(8)
  ) u_mt (
    .clk,
    .rst,
    .xif(xif),
    .mem_rd_valid(mem_rd_valid),
    .mem_rd_ready(mem_rd_ready),
    .mem_rd_addr(mem_rd_addr),
    .mem_rsp_valid(mem_rsp_valid),
    .mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_data(mem_rsp_data),
    .mem_wr_valid(mem_wr_valid),
    .mem_wr_ready(mem_wr_ready),
    .mem_wr_addr(mem_wr_addr),
    .mem_wr_data(mem_wr_data),
    .mem_wr_be(mem_wr_be),
    .ub_rd_en(1'b0),
    .ub_rd_addr('0),
    .ub_rd_valid(),
    .ub_rd_data(),
    .dma_busy()
  );

  mt_dma_l2_bridge u_bridge (
    .clk,
    .rst,
    .mem_rd_valid(mem_rd_valid),
    .mem_rd_ready(mem_rd_ready),
    .mem_rd_addr(mem_rd_addr),
    .mem_rsp_valid(mem_rsp_valid),
    .mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_data(mem_rsp_data),
    .mem_wr_valid(mem_wr_valid),
    .mem_wr_ready(mem_wr_ready),
    .mem_wr_addr(mem_wr_addr),
    .mem_wr_data(mem_wr_data),
    .mem_wr_be(mem_wr_be),
    .l2_req_valid(l2_req_valid),
    .l2_req_ready(l2_req_ready),
    .l2_req_write(l2_req_write),
    .l2_req_addr(l2_req_addr),
    .l2_req_wdata(l2_req_wdata),
    .l2_req_wstrb(l2_req_wstrb),
    .l2_rsp_valid(l2_rsp_valid),
    .l2_rsp_ready(l2_rsp_ready),
    .l2_rsp_rdata(l2_rsp_rdata)
  );

  assign mt_irq = status[1] | status[2] | status[3] | status[4];

endmodule