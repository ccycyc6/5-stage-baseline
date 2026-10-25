`timescale 1ns/1ps
// Board-build placeholder for the video subsystem.  The real ares_video
// (timing + test pattern + OSD + TMDS encoder) trips an ADS rtl-infer bug that
// reports multiple drivers on the constant nets _$$_VCC_$$_ / _$$_GND_$$_.
// The HDMI pins are not wired on the board build yet, so the register window is
// kept alive (reads return a scratch value) and the video outputs are idle.
module ares_video_stub (
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
  output logic        vsync_irq,
  output logic        pixel_clk_en,
  output logic        hsync,
  output logic        vsync,
  output logic        de,
  output logic [9:0]  tmds_r,
  output logic [9:0]  tmds_g,
  output logic [9:0]  tmds_b,
  output logic [9:0]  dbg_hcnt,
  output logic [9:0]  dbg_vcnt,
  output logic [3:0]  dbg_div
);
  logic [31:0] ctrl_q;

  assign req_ready = 1'b1;
  assign rsp_valid = req_valid;
  assign rsp_rdata = (req_addr[7:0] == 8'h00) ? ctrl_q : 32'h5649_4445; // 'VIDE'
  assign vsync_irq = 1'b0;
  assign pixel_clk_en = 1'b0;
  assign hsync = 1'b1;
  assign vsync = 1'b1;
  assign de    = 1'b0;
  assign tmds_r = 10'd0;
  assign tmds_g = 10'd0;
  assign tmds_b = 10'd0;
  assign dbg_hcnt = 10'd0;
  assign dbg_vcnt = 10'd0;
  assign dbg_div  = 4'd0;

  always_ff @(posedge clk) begin
    if (rst) ctrl_q <= 32'd0;
    else if (req_valid && req_write && (req_addr[7:0] == 8'h00)) ctrl_q <= req_wdata;
  end
endmodule