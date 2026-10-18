`timescale 1ns/1ps

package minitensor_pkg;
  localparam logic [6:0] MT_CUSTOM0_OPCODE = 7'b0001011;
  localparam logic [6:0] MT_LOAD_FUNCT7 = 7'b0000011;
  localparam logic [2:0] MT_LOAD_FUNCT3 = 3'b000;
  localparam logic [6:0] MT_STORE_FUNCT7 = 7'b0000100;
  localparam logic [2:0] MT_STORE_FUNCT3 = 3'b000;

  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic is_minitensor_load(input logic [31:0] instr);
    is_minitensor_load =
        (instr[6:0] == MT_CUSTOM0_OPCODE) &&
        (instr[31:25] == MT_LOAD_FUNCT7) &&
        (instr[14:12] == MT_LOAD_FUNCT3);
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic is_minitensor_store(input logic [31:0] instr);
    is_minitensor_store =
        (instr[6:0] == MT_CUSTOM0_OPCODE) &&
        (instr[31:25] == MT_STORE_FUNCT7) &&
        (instr[14:12] == MT_STORE_FUNCT3);
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  function automatic logic [31:0] make_minitensor_load(
      input logic [4:0] rd,
      input logic [4:0] src_reg,
      input logic [4:0] dst_reg);
    make_minitensor_load = {
      MT_LOAD_FUNCT7,
      dst_reg,
      src_reg,
      MT_LOAD_FUNCT3,
      rd,
      MT_CUSTOM0_OPCODE
    };
  endfunction

  function automatic logic [31:0] make_minitensor_store(
      input logic [4:0] rd,
      input logic [4:0] dst_reg,
      input logic [4:0] src_reg);
    make_minitensor_store = {
      MT_STORE_FUNCT7,
      src_reg,
      dst_reg,
      MT_STORE_FUNCT3,
      rd,
      MT_CUSTOM0_OPCODE
    };
  endfunction
endpackage
