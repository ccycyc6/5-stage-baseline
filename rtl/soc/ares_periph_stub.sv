`timescale 1ns/1ps
// Register stub for peripherals that are not exercised by the current
// software (I2C, SD, GbE).  It provides a scratch register and a status word
// so software can probe the block.
module ares_periph_stub (
  input  logic        clk,
  input  logic        rst,
  input  logic        req_valid,
  output logic        req_ready,
  input  logic        req_write,
  input  logic [31:0] req_addr,
  input  logic [31:0] req_wdata,
  input  logic [3:0]  req_wstrb,
  output logic        rsp_valid,
  input  logic        rsp_ready,
  output logic [31:0] rsp_rdata,
  output logic        irq
);
  logic [31:0] scratch_q;
  assign req_ready = 1'b1;
  assign rsp_valid = req_valid;
  assign irq = 1'b0;

  always_comb begin
    case (req_addr[7:0])
      8'h00: rsp_rdata = 32'h0000_0001; // present
      8'h04: rsp_rdata = 32'h0000_0000; // status
      8'h08: rsp_rdata = scratch_q;
      default: rsp_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) scratch_q <= 32'd0;
    else if (req_valid && req_ready && req_write && (req_addr[7:0] == 8'h08))
      scratch_q <= req_wdata;
  end
endmodule
