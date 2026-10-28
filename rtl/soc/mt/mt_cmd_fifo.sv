`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// mt_cmd_fifo - command queue for the miniTensor MMIO shim.
//
// Split out of mt_cvxif_shim because Pango ADS aborts (Flow-0189) when the
// queue and the sequencer live in the same module.  DEPTH is a parameter but
// the count is a plain integer, so no parameterised port widths are involved.
// ---------------------------------------------------------------------------
module mt_cmd_fifo #(
  parameter integer DEPTH = 8
) (
  input  logic        clk,
  input  logic        rst,

  input  logic        push,
  input  logic [31:0] push_instr,
  input  logic [31:0] push_rs1,
  input  logic [31:0] push_rs2,

  input  logic        pop,

  output logic [31:0] head_instr,
  output logic [31:0] head_rs1,
  output logic [31:0] head_rs2,
  output logic        empty,
  output logic        full,
  output logic [31:0] count
);
  localparam integer PTR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;

  logic [31:0] mem_instr [0:DEPTH-1];
  logic [31:0] mem_rs1   [0:DEPTH-1];
  logic [31:0] mem_rs2   [0:DEPTH-1];
  logic [PTR_W-1:0] head_q, tail_q;
  integer           count_q;

  assign head_instr = mem_instr[head_q];
  assign head_rs1   = mem_rs1[head_q];
  assign head_rs2   = mem_rs2[head_q];
  assign empty      = (count_q == 0);
  assign full       = (count_q == DEPTH);
  assign count      = count_q[31:0];

  always_ff @(posedge clk) begin
    if (rst) begin
      head_q  <= '0;
      tail_q  <= '0;
      count_q <= 0;
    end else begin
      if (push) begin
        mem_instr[tail_q] <= push_instr;
        mem_rs1[tail_q]   <= push_rs1;
        mem_rs2[tail_q]   <= push_rs2;
        tail_q            <= tail_q + 1'b1;
      end
      if (pop)
        head_q <= head_q + 1'b1;
      if (push && !pop)
        count_q <= count_q + 1;
      else if (!push && pop)
        count_q <= count_q - 1;
    end
  end
endmodule
