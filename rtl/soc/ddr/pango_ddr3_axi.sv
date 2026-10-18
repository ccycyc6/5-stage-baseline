`timescale 1ns/1ps
// DDR3 front end.  In simulation (PANGO_DDR3_IP undefined) this is the
// behavioral 32 MiB model.  On the board define PANGO_DDR3_IP and provide the
// Pango-generated wrapper named pango_ddr3_ip with the simple 128-bit
// request/response port listed below; the Pango DDR3 IP performs calibration
// and drives the board DDR3 pins.
module pango_ddr3_axi #(
  parameter              DDR_FILE = ""
) (
  input  logic         clk,
  input  logic         rst,
  input  logic         req_valid,
  output logic         req_ready,
  input  logic         req_write,
  input  logic [31:0]  req_addr,
  input  logic [127:0] req_wdata,
  input  logic [15:0]  req_wstrb,
  output logic         rsp_valid,
  input  logic         rsp_ready,
  output logic [127:0] rsp_rdata
);
`ifdef PANGO_DDR3_IP
  pango_ddr3_ip u_ip (
    .clk, .rst,
    .req_valid, .req_ready, .req_write, .req_addr, .req_wdata, .req_wstrb,
    .rsp_valid, .rsp_ready, .rsp_rdata
  );
`else
  ddr3_model #(.DDR_FILE(DDR_FILE)) u_model (
    .clk, .rst,
    .req_valid, .req_ready, .req_write, .req_addr, .req_wdata, .req_wstrb,
    .rsp_valid, .rsp_ready, .rsp_rdata
  );
`endif
endmodule
