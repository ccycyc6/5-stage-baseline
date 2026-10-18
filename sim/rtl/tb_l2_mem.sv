`timescale 1ns/1ps
// Simple 64 KiB, 16-byte-beat memory model with two request ports.
// Address bits [15:0] are used, so 0x0000_xxxx and 0x8000_xxxx alias.
module tb_l2_mem #(
  parameter int unsigned MEM_WORDS = 16384,
  parameter              MEM_FILE  = ""
) (
  input  logic         clk,
  input  logic         rst,

  input  logic         req0_valid,
  output logic         req0_ready,
  input  logic         req0_write,
  input  logic [31:0]  req0_addr,
  input  logic [127:0] req0_wdata,
  input  logic [15:0]  req0_wstrb,
  output logic         rsp0_valid,
  input  logic         rsp0_ready,
  output logic [127:0] rsp0_data,

  input  logic         req1_valid,
  output logic         req1_ready,
  input  logic         req1_write,
  input  logic [31:0]  req1_addr,
  input  logic [127:0] req1_wdata,
  input  logic [15:0]  req1_wstrb,
  output logic         rsp1_valid,
  input  logic         rsp1_ready,
  output logic [127:0] rsp1_data,

  input  logic [15:0]  dbg_word_addr,
  output logic [31:0]  dbg_word_data
);
  logic [31:0] mem [0:MEM_WORDS-1];
  assign dbg_word_data = mem[dbg_word_addr];

  initial begin
    if (MEM_FILE != "") $readmemh(MEM_FILE, mem);
  end

  typedef enum logic [2:0] {M_IDLE, M_RSP0, M_RSP1} state_t;
  state_t state_q;
  logic [1:0] owner_q;
  logic [127:0] rsp_data_q;

  assign req0_ready = (state_q == M_IDLE);
  assign req1_ready = (state_q == M_IDLE) && !req0_valid;
  assign rsp0_valid = (state_q == M_RSP0);
  assign rsp1_valid = (state_q == M_RSP1);
  assign rsp0_data  = rsp_data_q;
  assign rsp1_data  = rsp_data_q;

  function automatic logic [31:0] word_at(input logic [31:0] addr);
    word_at = mem[addr[15:2]];
  endfunction

  task automatic do_write(input logic [31:0] addr, input logic [127:0] wdata,
                          input logic [15:0] wstrb);
    logic [31:0] base;
    base = addr[15:2];
    for (int unsigned i = 0; i < 4; i++) begin
      if (wstrb[4*i +: 4] != 4'd0) begin
        logic [31:0] old;
        logic [31:0] nw;
        old = mem[base + i];
        nw = old;
        for (int unsigned b = 0; b < 4; b++) begin
          if (wstrb[4*i + b]) nw[b*8 +: 8] = wdata[32*i + b*8 +: 8];
        end
        mem[base + i] = nw;
      end
    end
  endtask

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= M_IDLE;
      owner_q <= 2'd0;
      rsp_data_q <= 128'd0;
    end else begin
      case (state_q)
        M_IDLE: begin
          if (req0_valid) begin
            if (req0_write) do_write(req0_addr, req0_wdata, req0_wstrb);
            else rsp_data_q <= {word_at(req0_addr+12), word_at(req0_addr+8),
                                word_at(req0_addr+4),  word_at(req0_addr)};
            state_q <= M_RSP0;
          end else if (req1_valid) begin
            if (req1_write) do_write(req1_addr, req1_wdata, req1_wstrb);
            else rsp_data_q <= {word_at(req1_addr+12), word_at(req1_addr+8),
                                word_at(req1_addr+4),  word_at(req1_addr)};
            state_q <= M_RSP1;
          end
        end
        M_RSP0: if (rsp0_ready) state_q <= M_IDLE;
        M_RSP1: if (rsp1_ready) state_q <= M_IDLE;
        default: state_q <= M_IDLE;
      endcase
    end
  end
endmodule