`timescale 1ns/1ps
// DDR3 front end. Three build flavours:
//  * ONCHIP_DDR      : the on-chip 128-bit memory model (board bring-up, no IP)
//  * PANGO_DDR3_IP   : the Pango HMIC DDR3 IP wrapper (real board memory)
//  * neither         : the behavioural 32 MiB simulation model
module pango_ddr3_axi #(
  parameter              DDR_FILE  = "",
  parameter int unsigned ONCHIP_DEPTH = 16384
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
`elsif ONCHIP_DDR
  onchip_ddr #(.WORDS(ONCHIP_DEPTH), .INIT_FILE(DDR_FILE)) u_oc (
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