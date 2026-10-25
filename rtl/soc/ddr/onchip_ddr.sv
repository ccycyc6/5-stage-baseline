`timescale 1ns/1ps
// On-chip replacement for the DDR3 controller: one 128-bit line per address,
// byte-strobed writes, one cycle of read latency.  A single write port per
// cycle keeps the array inferable as block RAM (Pango DRM supports per-byte
// write enables); the initial image is a $readmemh file with one 128-bit line
// per hex row (tools/fw_hex128.py produces it from the flat firmware binary).
module onchip_ddr #(
  parameter int unsigned WORDS     = 16384,          // 16 B lines -> 256 KiB
  parameter              INIT_FILE = ""
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
  localparam int unsigned IDX_BITS = $clog2(WORDS);

  logic [127:0] mem [0:WORDS-1];

  integer init_i;
  initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  wire [IDX_BITS-1:0] idx = req_addr[IDX_BITS+3:4];

  logic         rsp_valid_q;
  logic [127:0] rsp_q;
  integer b;

  assign req_ready = !rsp_valid_q;
  assign rsp_valid = rsp_valid_q;
  assign rsp_rdata = rsp_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      rsp_valid_q <= 1'b0;
      rsp_q       <= 128'd0;
    end else if (req_valid && req_ready) begin
      rsp_valid_q <= 1'b1;
      if (req_write) begin
        for (b = 0; b < 16; b = b + 1) begin
          if (req_wstrb[b]) mem[idx][b*8 +: 8] <= req_wdata[b*8 +: 8];
        end
        rsp_q <= 128'd0;
      end else begin
        rsp_q <= mem[idx];
      end
    end else if (rsp_valid_q && rsp_ready) begin
      rsp_valid_q <= 1'b0;
    end
  end
endmodule
