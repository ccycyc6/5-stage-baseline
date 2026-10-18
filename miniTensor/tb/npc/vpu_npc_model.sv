`timescale 1ns/1ps
/* verilator lint_off IMPORTSTAR */
/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */

// Behavioural model of the main RISC-V CPU (NPC) that drives miniTensor
// through CV-X-IF.  The offload handshake timing mirrors a deep in-order
// pipeline such as the 9-stage Mundus core:
//
//   fetch -> decode -> issue -> (ISSUE_TO_REGISTER) -> register
//         -> (REGISTER_TO_COMMIT) -> commit -> wait result
//
// Custom-0 miniTensor instructions are not executed locally: the model runs
// the full issue/register/commit/result lifecycle and waits for the
// accelerator result before retiring the instruction.  Because miniTensor
// accepts a single command at a time, the model naturally stalls while a
// tensor command is in flight.
//
// The model never drives XIF memory transactions; miniTensor uses its own
// uncached DMA port.  Unused CPU-side XIF signals are tied off safely.
import minitensor_pkg::*;
import tensor_pkg::*;
import vpu_pkg::*;

module vpu_npc_model #(
  parameter int unsigned X_ID_WIDTH          = 4,
  parameter int unsigned X_HARTID_WIDTH      = 1,
  parameter int unsigned ISSUE_TO_REGISTER   = 2,
  parameter int unsigned REGISTER_TO_COMMIT  = 3,
  parameter int unsigned RESULT_ACCEPT_DELAY = 0
) (
  input  logic         clk,
  input  logic         rst,
  core_v_xif           xif,

  output logic         imem_en,
  output logic [31:0]  imem_addr,
  input  logic [31:0]  imem_data,

  output logic         cpu_rd_en,
  output logic [31:0]  cpu_rd_addr,
  input  logic [31:0]  cpu_rd_data,
  output logic         cpu_wr_en,
  output logic [31:0]  cpu_wr_addr,
  output logic [31:0]  cpu_wr_data,
  output logic [3:0]   cpu_wr_be,

  output logic         halted,
  output logic         error,
  output logic [31:0]  pc_out,
  output logic [31:0]  retire_count
);
  localparam int unsigned GPR_COUNT = 32;

  typedef enum logic [3:0] {
    S_FETCH,
    S_DECODE,
    S_XIF_ISSUE,
    S_XIF_REG_WAIT,
    S_XIF_REGISTER,
    S_XIF_COMMIT_WAIT,
    S_XIF_COMMIT,
    S_XIF_RESULT_WAIT,
    S_HALTED,
    S_ERROR
  } state_t;

  state_t                state_q;
  logic [31:0]           pc_q;
  logic [31:0]           gpr [0:GPR_COUNT-1];
  logic [31:0]           instr_q;
  logic [31:0]           operand1_q;
  logic [31:0]           operand2_q;
  logic [X_ID_WIDTH-1:0] xif_id_q;
  logic [X_ID_WIDTH-1:0] xif_id_counter_q;
  logic [7:0]            wait_q;
  logic [31:0]           retire_count_q;
  logic                  error_q;

  wire [6:0] d_opcode = imem_data[6:0];
  wire [4:0] d_rd     = imem_data[11:7];
  wire [2:0] d_funct3 = imem_data[14:12];
  wire [4:0] d_rs1    = imem_data[19:15];
  wire [4:0] d_rs2    = imem_data[24:20];
  wire [6:0] d_funct7 = imem_data[31:25];

  wire [31:0] d_imm_i = {{20{imem_data[31]}}, imem_data[31:20]};
  wire [31:0] d_imm_s = {{20{imem_data[31]}}, imem_data[31:25], imem_data[11:7]};
  wire [31:0] d_imm_b = {{19{imem_data[31]}}, imem_data[31], imem_data[7],
                         imem_data[30:25], imem_data[11:8], 1'b0};
  wire [31:0] d_imm_u = {imem_data[31:12], 12'b0};
  wire [31:0] d_imm_j = {{11{imem_data[31]}}, imem_data[31], imem_data[19:12],
                         imem_data[20], imem_data[30:21], 1'b0};

  wire [31:0] d_rs1_val = (d_rs1 == 5'd0) ? 32'h0 : gpr[d_rs1];
  wire [31:0] d_rs2_val = (d_rs2 == 5'd0) ? 32'h0 : gpr[d_rs2];

  wire d_is_halt   = (imem_data == 32'h0010_0073);
  wire d_is_custom = is_minitensor_load(imem_data) || is_minitensor_store(imem_data) ||
                     is_vector_instruction(imem_data) || is_tensor_gemm(imem_data) ||
                     is_tensor_epilogue(imem_data);

  logic [31:0] d_wb;
  logic        d_wen;
  logic [31:0] d_next_pc;
  logic        d_is_load;
  logic        d_is_store;

  always_comb begin
    d_wb       = 32'h0;
    d_wen      = 1'b0;
    d_next_pc  = pc_q + 32'd4;
    d_is_load  = 1'b0;
    d_is_store = 1'b0;

    case (d_opcode)
      7'b0110111: begin  // LUI
        d_wb  = d_imm_u;
        d_wen = 1'b1;
      end
      7'b0010111: begin  // AUIPC
        d_wb  = pc_q + d_imm_u;
        d_wen = 1'b1;
      end
      7'b1101111: begin  // JAL
        d_wb      = pc_q + 32'd4;
        d_wen     = 1'b1;
        d_next_pc = pc_q + d_imm_j;
      end
      7'b1100111: begin  // JALR
        d_wb      = pc_q + 32'd4;
        d_wen     = 1'b1;
        d_next_pc = (d_rs1_val + d_imm_i) & 32'hffff_fffe;
      end
      7'b1100011: begin  // BRANCH
        case (d_funct3)
          3'b000: if (d_rs1_val == d_rs2_val)                   d_next_pc = pc_q + d_imm_b;
          3'b001: if (d_rs1_val != d_rs2_val)                   d_next_pc = pc_q + d_imm_b;
          3'b100: if ($signed(d_rs1_val) <  $signed(d_rs2_val)) d_next_pc = pc_q + d_imm_b;
          3'b101: if (d_rs1_val <  d_rs2_val)                   d_next_pc = pc_q + d_imm_b;
          3'b110: if ($signed(d_rs1_val) >= $signed(d_rs2_val)) d_next_pc = pc_q + d_imm_b;
          3'b111: if (d_rs1_val >= d_rs2_val)                   d_next_pc = pc_q + d_imm_b;
          default: ;
        endcase
      end
      7'b0000011: begin  // LOAD
        d_is_load = 1'b1;
        d_wen     = 1'b1;
        d_wb      = cpu_rd_data;
      end
      7'b0100011: begin  // STORE
        d_is_store = 1'b1;
      end
      7'b0010011: begin  // OP-IMM
        d_wen = 1'b1;
        case (d_funct3)
          3'b000: d_wb = d_rs1_val + d_imm_i;
          3'b010: d_wb = ($signed(d_rs1_val) < $signed(d_imm_i)) ? 32'd1 : 32'd0;
          3'b011: d_wb = (d_rs1_val < d_imm_i) ? 32'd1 : 32'd0;
          3'b100: d_wb = d_rs1_val ^ d_imm_i;
          3'b110: d_wb = d_rs1_val | d_imm_i;
          3'b111: d_wb = d_rs1_val & d_imm_i;
          3'b001: d_wb = d_rs1_val << d_imm_i[4:0];
          3'b101: d_wb = d_funct7[5] ? ($signed(d_rs1_val) >>> d_imm_i[4:0])
                                     : (d_rs1_val >> d_imm_i[4:0]);
          default: ;
        endcase
      end
      7'b0110011: begin  // OP
        d_wen = 1'b1;
        case (d_funct3)
          3'b000: d_wb = d_funct7[5] ? (d_rs1_val - d_rs2_val) : (d_rs1_val + d_rs2_val);
          3'b001: d_wb = d_rs1_val << d_rs2_val[4:0];
          3'b010: d_wb = ($signed(d_rs1_val) < $signed(d_rs2_val)) ? 32'd1 : 32'd0;
          3'b011: d_wb = (d_rs1_val < d_rs2_val) ? 32'd1 : 32'd0;
          3'b100: d_wb = d_rs1_val ^ d_rs2_val;
          3'b101: d_wb = d_funct7[5] ? ($signed(d_rs1_val) >>> d_rs2_val[4:0])
                                     : (d_rs1_val >> d_rs2_val[4:0]);
          3'b110: d_wb = d_rs1_val | d_rs2_val;
          3'b111: d_wb = d_rs1_val & d_rs2_val;
          default: ;
        endcase
      end
      7'b0001111: ;  // FENCE as nop
      default: ;
    endcase
  end

  assign imem_en   = (state_q == S_FETCH);
  assign imem_addr = pc_q;

  assign cpu_rd_en   = (state_q == S_DECODE) && d_is_load;
  assign cpu_rd_addr = d_rs1_val + d_imm_i;
  assign cpu_wr_en   = (state_q == S_DECODE) && d_is_store;
  assign cpu_wr_addr = d_rs1_val + d_imm_s;
  assign cpu_wr_data = d_rs2_val;
  assign cpu_wr_be   = 4'hf;

  assign halted       = (state_q == S_HALTED);
  assign error        = error_q || (state_q == S_ERROR);
  assign pc_out       = pc_q;
  assign retire_count = retire_count_q;

  always_comb begin
    xif.issue_valid      = 1'b0;
    xif.issue_req        = '0;
    xif.register_valid   = 1'b0;
    xif.register         = '0;
    xif.commit_valid     = 1'b0;
    xif.commit           = '0;
    xif.result_ready     = 1'b0;
    xif.compressed_valid = 1'b0;
    xif.compressed_req   = '0;
    xif.mem_ready        = 1'b1;
    xif.mem_resp         = '0;
    xif.mem_result_valid = 1'b0;
    xif.mem_result       = '0;

    if (state_q == S_XIF_ISSUE) begin
      xif.issue_valid      = 1'b1;
      xif.issue_req.instr  = instr_q;
      xif.issue_req.mode   = 2'b00;
      xif.issue_req.hartid = '0;
      xif.issue_req.id     = xif_id_q;
    end

    if (state_q == S_XIF_REGISTER) begin
      xif.register_valid    = 1'b1;
      xif.register.hartid   = '0;
      xif.register.id       = xif_id_q;
      xif.register.rs[0]    = operand1_q;
      xif.register.rs[1]    = operand2_q;
      xif.register.rs_valid = 2'b11;
    end

    if (state_q == S_XIF_COMMIT) begin
      xif.commit_valid       = 1'b1;
      xif.commit.hartid      = '0;
      xif.commit.id          = xif_id_q;
      xif.commit.commit_kill = 1'b0;
    end

    if ((state_q == S_XIF_RESULT_WAIT) && (wait_q == 8'd0))
      xif.result_ready = 1'b1;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q          <= S_FETCH;
      pc_q             <= 32'h0;
      instr_q          <= 32'h0000_0013;
      operand1_q       <= 32'h0;
      operand2_q       <= 32'h0;
      xif_id_q         <= '0;
      xif_id_counter_q <= '0;
      wait_q           <= 8'd0;
      retire_count_q   <= 32'h0;
      error_q          <= 1'b0;
      for (int unsigned i = 0; i < GPR_COUNT; i = i + 1)
        gpr[i] <= 32'h0;
    end else begin
      case (state_q)
        S_FETCH: state_q <= S_DECODE;

        S_DECODE: begin
          instr_q <= imem_data;
          if (d_is_halt) begin
            state_q <= S_HALTED;
          end else if (d_is_custom) begin
            operand1_q       <= d_rs1_val;
            operand2_q       <= d_rs2_val;
            xif_id_q         <= xif_id_counter_q;
            xif_id_counter_q <= xif_id_counter_q + 1'b1;
            state_q          <= S_XIF_ISSUE;
          end else begin
            if (d_wen && (d_rd != 5'd0))
              gpr[d_rd] <= d_wb;
            pc_q           <= d_next_pc;
            retire_count_q <= retire_count_q + 32'd1;
            state_q        <= S_FETCH;
          end
        end

        S_XIF_ISSUE: begin
          if (xif.issue_ready) begin
            if (xif.issue_resp.accept) begin
              wait_q  <= 8'(ISSUE_TO_REGISTER);
              state_q <= S_XIF_REG_WAIT;
            end else begin
              error_q <= 1'b1;
              state_q <= S_ERROR;
            end
          end
        end

        S_XIF_REG_WAIT: begin
          if (wait_q == 8'd0)
            state_q <= S_XIF_REGISTER;
          else
            wait_q <= wait_q - 8'd1;
        end

        S_XIF_REGISTER: begin
          if (xif.register_ready) begin
            wait_q  <= 8'(REGISTER_TO_COMMIT);
            state_q <= S_XIF_COMMIT_WAIT;
          end
        end

        S_XIF_COMMIT_WAIT: begin
          if (wait_q == 8'd0)
            state_q <= S_XIF_COMMIT;
          else
            wait_q <= wait_q - 8'd1;
        end

        S_XIF_COMMIT: begin
          wait_q  <= 8'(RESULT_ACCEPT_DELAY);
          state_q <= S_XIF_RESULT_WAIT;
        end

        S_XIF_RESULT_WAIT: begin
          if (wait_q != 8'd0)
            wait_q <= wait_q - 8'd1;
          if (xif.result_valid && (wait_q == 8'd0)) begin
            if (xif.result.we[0] && (xif.result.rd != 5'd0))
              gpr[xif.result.rd] <= xif.result.data;
            if (xif.result.err)
              error_q <= 1'b1;
            pc_q           <= pc_q + 32'd4;
            retire_count_q <= retire_count_q + 32'd1;
            state_q        <= S_FETCH;
          end
        end

        S_HALTED: state_q <= S_HALTED;
        S_ERROR:  state_q <= S_ERROR;
        default:  state_q <= S_FETCH;
      endcase
    end
  end
endmodule
