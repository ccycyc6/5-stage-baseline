`timescale 1ns/1ps
// Placeholder miniTensor cluster used for FPGA builds where the CV-X-IF
// interface cannot be elaborated (Pango ADS does not support SV interfaces).
// It keeps the MMIO window alive and reports an idle/zero accelerator so the
// CPU, cache, DDR and UART paths can be built and tested independently.
module mt_cluster_stub #(
  parameter int unsigned UB_DEPTH = 256
) (
  input  logic         clk,
  input  logic         rst,

  input  logic         reg_wr_en,
  input  logic [2:0]   reg_wr_idx,
  input  logic [31:0]  reg_wr_data,
  input  logic         status_rd,
  output logic [31:0]  status,
  output logic [31:0]  result_data,

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
  logic [31:0] last;
  always_ff @(posedge clk) begin
    if (rst) last <= 32'h0;
    else if (reg_wr_en) last <= reg_wr_data;
  end
  assign status      = 32'h0000_0004; // IDLE, no error
  assign result_data = last;
  assign l2_req_valid = 1'b0;
  assign l2_req_write = 1'b0;
  assign l2_req_addr  = 32'd0;
  assign l2_req_wdata = 128'd0;
  assign l2_req_wstrb = 16'd0;
  assign l2_rsp_ready = 1'b1;
  assign mt_irq       = 1'b0;
endmodule