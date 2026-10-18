`timescale 1ns/1ps

// Unified, single-clock miniTensor top.
// One committed command at a time controls DMA load/store or a vector
// operation whose operands and result reside in the Unified Buffer.
module mini_tensor_top #(
  parameter int unsigned X_ID_WIDTH = 4,
  parameter int unsigned X_HARTID_WIDTH = 1,
  parameter int unsigned DATA_WIDTH = 128,
  parameter int unsigned UB_DEPTH = 256,
  parameter int unsigned UB_ADDR_WIDTH = $clog2(UB_DEPTH),
  parameter int unsigned COUNT_WIDTH = 8
) (
  input  logic clk,
  input  logic rst,
  core_v_xif xif,

  output logic mem_rd_valid,
  input  logic mem_rd_ready,
  output logic [31:0] mem_rd_addr,
  input  logic mem_rsp_valid,
  output logic mem_rsp_ready,
  input  logic [DATA_WIDTH-1:0] mem_rsp_data,

  output logic mem_wr_valid,
  input  logic mem_wr_ready,
  output logic [31:0] mem_wr_addr,
  output logic [DATA_WIDTH-1:0] mem_wr_data,
  output logic [DATA_WIDTH/8-1:0] mem_wr_be,

  // Read-only debug port. Future compute blocks can replace this external
  // owner without changing the DMA/UB boundary.
  input  logic ub_rd_en,
  input  logic [UB_ADDR_WIDTH-1:0] ub_rd_addr,
  output logic ub_rd_valid,
  output logic [DATA_WIDTH-1:0] ub_rd_data,
  output logic dma_busy
);
  import minitensor_pkg::*;
  import tensor_pkg::*;
  import vpu_pkg::*;

  typedef enum logic [2:0] {OP_LOAD, OP_STORE, OP_VECTOR, OP_TENSOR, OP_EPILOGUE} op_t;
  typedef enum logic [3:0] {
    S_IDLE,
    S_WAIT_COMMIT,
    S_DISPATCH,
    S_DMA_START,
    S_DMA_WAIT,
    S_VEC_READ_A,
    S_VEC_LOAD_A,
    S_VEC_READ_B,
    S_VEC_LOAD_B,
    S_VEC_COMMAND,
    S_VEC_WAIT,
    S_TENSOR_START,
    S_TENSOR_WAIT,
    S_EPILOGUE_START,
    S_EPILOGUE_WAIT,
    S_RESULT
  } state_t;

  state_t state_q;
  op_t op_q;
  logic [X_ID_WIDTH-1:0] id_q;
  logic [X_HARTID_WIDTH-1:0] hartid_q;
  logic [4:0] rd_q;
  logic [31:0] mem_addr_q;
  logic [UB_ADDR_WIDTH-1:0] ub_base_q;
  logic [COUNT_WIDTH-1:0] tile_count_q;
  logic [UB_ADDR_WIDTH-1:0] vec_src_a_q, vec_src_b_q, vec_dst_q;
  logic [2:0] vec_funct3_q;
  logic tensor_accumulate_q;
  logic [UB_ADDR_WIDTH-1:0] ep_config_addr_q;
  logic [31:0] rs1_q, rs2_q;
  logic register_seen_q, committed_q, command_err_q;

  logic dma_cmd_valid, dma_cmd_ready, dma_cmd_write, dma_done;
  logic dma_ub_wr_en, dma_ub_rd_en;
  logic [UB_ADDR_WIDTH-1:0] dma_ub_wr_addr, dma_ub_rd_addr;
  logic [DATA_WIDTH-1:0] dma_ub_wr_data;
  logic [DATA_WIDTH/8-1:0] dma_ub_wr_be;

  logic vector_cmd_valid, vector_cmd_ready;
  logic [31:0] vector_cmd_instr;
  logic vector_result_valid, vector_result_ready;
  logic [3:0] vector_result_id;
  logic [DATA_WIDTH-1:0] vector_result_data;
  logic [4:0] vector_result_vd;
  logic vector_load_valid, vector_load_ready;
  logic [4:0] vector_load_addr;

  logic ub_mem_wr_en, ub_mem_rd_en, ub_mem_rd_valid;
  logic [UB_ADDR_WIDTH-1:0] ub_mem_wr_addr, ub_mem_rd_addr;
  logic [DATA_WIDTH-1:0] ub_mem_wr_data, ub_mem_rd_data;
  logic [DATA_WIDTH/8-1:0] ub_mem_wr_be;

  logic tensor_cmd_valid, tensor_cmd_ready, tensor_busy, tensor_done;
  logic tensor_ub_rd_en, tensor_ub_wr_en;
  logic [UB_ADDR_WIDTH-1:0] tensor_ub_rd_addr, tensor_ub_wr_addr;
  logic [DATA_WIDTH-1:0] tensor_ub_wr_data;
  logic [DATA_WIDTH/8-1:0] tensor_ub_wr_be;

  logic ep_cmd_valid, ep_cmd_ready, ep_busy, ep_done;
  logic ep_ub_rd_en, ep_ub_wr_en;
  logic [UB_ADDR_WIDTH-1:0] ep_ub_rd_addr, ep_ub_wr_addr;
  logic [DATA_WIDTH-1:0] ep_ub_wr_data;
  logic [DATA_WIDTH/8-1:0] ep_ub_wr_be;

  wire issue_load = is_minitensor_load(xif.issue_req.instr);
  wire issue_store = is_minitensor_store(xif.issue_req.instr);
  wire issue_vector = is_vector_instruction(xif.issue_req.instr);
  wire issue_tensor = is_tensor_gemm(xif.issue_req.instr);
  wire issue_epilogue = is_tensor_epilogue(xif.issue_req.instr);
  wire issue_supported = issue_load || issue_store || issue_vector || issue_tensor || issue_epilogue;
  wire count_valid = (rs2_q[15:8] != 8'h00);
  wire [8:0] ub_end = {1'b0, rs2_q[7:0]} + {1'b0, rs2_q[15:8]};
  wire dma_operands_valid = (rs2_q[31:16] == 16'h0000) &&
      (rs1_q[3:0] == 4'h0) && count_valid &&
      (ub_end <= 9'(UB_DEPTH));
  wire vector_operands_valid = (rs1_q[31:16] == 16'h0000) &&
      (rs2_q[31:8] == 24'h000000) &&
      ({1'b0, rs1_q[7:0]} < 9'(UB_DEPTH)) &&
      ({1'b0, rs1_q[15:8]} < 9'(UB_DEPTH)) &&
      ({1'b0, rs2_q[7:0]} < 9'(UB_DEPTH));
  wire tensor_operands_valid = (rs1_q[31:16] == 16'h0000) &&
      (rs2_q[31:9] == 23'h000000) &&
      ({1'b0, rs1_q[7:0]} < 9'(UB_DEPTH)) &&
      ({1'b0, rs1_q[15:8]} < 9'(UB_DEPTH)) &&
      ({1'b0, rs2_q[7:0]} + 9'd3 < 9'(UB_DEPTH));
  wire epilogue_operands_valid = (rs1_q[31:16] == 16'h0000) &&
      (rs2_q[31:16] == 16'h0000) &&
      ({1'b0, rs1_q[7:0]} + 9'd3 < 9'(UB_DEPTH)) &&
      ({1'b0, rs1_q[15:8]} + 9'd3 < 9'(UB_DEPTH)) &&
      ({1'b0, rs2_q[15:8]} < 9'(UB_DEPTH)) &&
      ({1'b0, rs2_q[7:0]} < 9'(UB_DEPTH));
  wire operands_valid = (op_q == OP_VECTOR) ? vector_operands_valid :
      ((op_q == OP_TENSOR) ? tensor_operands_valid :
      ((op_q == OP_EPILOGUE) ? epilogue_operands_valid : dma_operands_valid));
  wire issue_fire = xif.issue_valid && xif.issue_ready &&
      xif.issue_resp.accept;
  wire register_match = (xif.register.id == id_q) &&
      (xif.register.hartid == hartid_q);
  wire register_operands_valid = (xif.register.rs_valid == 2'b11);
  wire register_fire = xif.register_valid && xif.register_ready;
  wire commit_match = xif.commit_valid && (xif.commit.id == id_q) &&
      (xif.commit.hartid == hartid_q);
  wire commit_fire = commit_match && !xif.commit.commit_kill;
  wire kill_fire = commit_match && xif.commit.commit_kill;
  wire vector_result_match = (vector_result_id == id_q) &&
      (vector_result_vd == 5'd3);
  wire vector_result_fire = vector_result_valid && vector_result_ready;

  initial begin
    if (DATA_WIDTH != 128)
      $fatal(1, "mini_tensor_top currently requires DATA_WIDTH=128");
    if (X_ID_WIDTH != 4)
      $fatal(1, "mini_tensor_top currently requires X_ID_WIDTH=4");
  end

//core's response to the XIF "issue" handshake
  assign xif.issue_ready = (state_q == S_IDLE);
  always_comb begin
    xif.issue_resp = '0;
    xif.issue_resp.accept = issue_supported;
    xif.issue_resp.writeback[0] = issue_supported;
    xif.issue_resp.register_read = issue_supported ? 2'b11 : 2'b00;
  end
  assign xif.register_ready = (state_q == S_WAIT_COMMIT) && !register_seen_q;

//the write-back result that the accelerator sends back to the interface when the command finishes
  assign xif.result_valid = (state_q == S_RESULT);
  always_comb begin
    xif.result = '0;
    xif.result.id = id_q;
    xif.result.hartid = hartid_q;
    xif.result.data = 32'h0000_0000;
    xif.result.rd = rd_q;
    xif.result.we[0] = 1'b1;
    xif.result.err = command_err_q;
  end

  assign xif.compressed_ready = 1'b1;
  assign xif.compressed_resp = '0;
  assign xif.mem_valid = 1'b0;
  assign xif.mem_req = '0;

  assign dma_cmd_valid = (state_q == S_DMA_START);
  assign dma_cmd_write = (op_q == OP_STORE);

  assign tensor_cmd_valid = (state_q == S_TENSOR_START);
  assign ep_cmd_valid = (state_q == S_EPILOGUE_START);

  tensor_controller #(
    .UB_ADDR_WIDTH(UB_ADDR_WIDTH)
  ) u_tensor_controller (
    .clk,
    .rst,
    .cmd_valid(tensor_cmd_valid),
    .cmd_ready(tensor_cmd_ready),
    .cmd_a_addr(vec_src_a_q),
    .cmd_b_addr(vec_src_b_q),
    .cmd_c_addr(vec_dst_q),
    .cmd_accumulate(tensor_accumulate_q),
    .busy(tensor_busy),
    .done(tensor_done),
    .ub_rd_en(tensor_ub_rd_en),
    .ub_rd_addr(tensor_ub_rd_addr),
    .ub_rd_valid(ub_mem_rd_valid),
    .ub_rd_data(ub_mem_rd_data),
    .ub_wr_en(tensor_ub_wr_en),
    .ub_wr_addr(tensor_ub_wr_addr),
    .ub_wr_data(tensor_ub_wr_data),
    .ub_wr_be(tensor_ub_wr_be)
  );

  tensor_epilogue_controller #(
    .UB_ADDR_WIDTH(UB_ADDR_WIDTH)
  ) u_tensor_epilogue_controller (
    .clk,
    .rst,
    .cmd_valid(ep_cmd_valid),
    .cmd_ready(ep_cmd_ready),
    .cmd_c_addr(vec_src_a_q),
    .cmd_bias_addr(vec_src_b_q),
    .cmd_config_addr(ep_config_addr_q),
    .cmd_output_addr(vec_dst_q),
    .busy(ep_busy),
    .done(ep_done),
    .ub_rd_en(ep_ub_rd_en),
    .ub_rd_addr(ep_ub_rd_addr),
    .ub_rd_valid(ub_mem_rd_valid),
    .ub_rd_data(ub_mem_rd_data),
    .ub_wr_en(ep_ub_wr_en),
    .ub_wr_addr(ep_ub_wr_addr),
    .ub_wr_data(ep_ub_wr_data),
    .ub_wr_be(ep_ub_wr_be)
  );

  vpu_dma #(
    .DATA_WIDTH(DATA_WIDTH),
    .UB_ADDR_WIDTH(UB_ADDR_WIDTH),
    .COUNT_WIDTH(COUNT_WIDTH)
  ) u_dma (
    .clk,
    .rst,
    .cmd_valid(dma_cmd_valid),
    .cmd_ready(dma_cmd_ready),
    .cmd_write(dma_cmd_write),
    .cmd_mem_addr(mem_addr_q),
    .cmd_ub_addr(ub_base_q),
    .cmd_tile_count(tile_count_q),
    .busy(dma_busy),
    .done(dma_done),
    .mem_rd_valid,
    .mem_rd_ready,
    .mem_rd_addr,
    .mem_rsp_valid,
    .mem_rsp_ready,
    .mem_rsp_data,
    .mem_wr_valid,
    .mem_wr_ready,
    .mem_wr_addr,
    .mem_wr_data,
    .mem_wr_be,
    .ub_wr_en(dma_ub_wr_en),
    .ub_wr_addr(dma_ub_wr_addr),
    .ub_wr_data(dma_ub_wr_data),
    .ub_wr_be(dma_ub_wr_be),
    .ub_rd_en(dma_ub_rd_en),
    .ub_rd_addr(dma_ub_rd_addr),
    .ub_rd_valid(ub_mem_rd_valid),
    .ub_rd_data(ub_mem_rd_data)
  );

  assign vector_load_valid =
      ((state_q == S_VEC_LOAD_A) || (state_q == S_VEC_LOAD_B)) &&
      ub_mem_rd_valid;
  assign vector_load_addr = (state_q == S_VEC_LOAD_A) ? 5'd1 : 5'd2;
  assign vector_cmd_valid = (state_q == S_VEC_COMMAND);
  assign vector_cmd_instr = make_vector_rtype(vec_funct3_q, 5'd3, 5'd1, 5'd2);
  assign vector_result_ready = (state_q == S_VEC_WAIT) && vector_result_match;

  vpu_vector_controller #(
    .NUM_REGS(32), .VLEN(DATA_WIDTH), .ADDR_WIDTH(5)
  ) u_vector_controller (
    .clk,
    .rst,
    .cmd_valid(vector_cmd_valid),
    .cmd_ready(vector_cmd_ready),
    .cmd_instr(vector_cmd_instr),
    .cmd_id(id_q),
    .cmd_kill(1'b0),
    .result_valid(vector_result_valid),
    .result_ready(vector_result_ready),
    .result_id(vector_result_id),
    .result_data(vector_result_data),
    .result_vd(vector_result_vd),
    .load_valid(vector_load_valid),
    .load_ready(vector_load_ready),
    .load_addr(vector_load_addr),
    .load_data(ub_mem_rd_data),
    .load_be('1)
  );

  // The command FSM guarantees these owners are mutually exclusive.
  always_comb begin
    ub_mem_rd_en = 1'b0;
    ub_mem_rd_addr = '0;
    if (dma_ub_rd_en) begin
      ub_mem_rd_en = 1'b1;
      ub_mem_rd_addr = dma_ub_rd_addr;
    end else if (state_q == S_VEC_READ_A) begin
      ub_mem_rd_en = 1'b1;
      ub_mem_rd_addr = vec_src_a_q;
    end else if (state_q == S_VEC_READ_B) begin
      ub_mem_rd_en = 1'b1;
      ub_mem_rd_addr = vec_src_b_q;
    end else if (tensor_ub_rd_en) begin
      ub_mem_rd_en = 1'b1;
      ub_mem_rd_addr = tensor_ub_rd_addr;
    end else if (ep_ub_rd_en) begin
      ub_mem_rd_en = 1'b1;
      ub_mem_rd_addr = ep_ub_rd_addr;
    end else if (ub_rd_en) begin
      ub_mem_rd_en = 1'b1;
      ub_mem_rd_addr = ub_rd_addr;
    end
  end

  always_comb begin
    ub_mem_wr_en = dma_ub_wr_en;
    ub_mem_wr_addr = dma_ub_wr_addr;
    ub_mem_wr_data = dma_ub_wr_data;
    ub_mem_wr_be = dma_ub_wr_be;
    if (tensor_ub_wr_en) begin
      ub_mem_wr_en = 1'b1;
      ub_mem_wr_addr = tensor_ub_wr_addr;
      ub_mem_wr_data = tensor_ub_wr_data;
      ub_mem_wr_be = tensor_ub_wr_be;
    end else if (ep_ub_wr_en) begin
      ub_mem_wr_en = 1'b1;
      ub_mem_wr_addr = ep_ub_wr_addr;
      ub_mem_wr_data = ep_ub_wr_data;
      ub_mem_wr_be = ep_ub_wr_be;
    end else if (vector_result_fire) begin
      ub_mem_wr_en = 1'b1;
      ub_mem_wr_addr = vec_dst_q;
      ub_mem_wr_data = vector_result_data;
      ub_mem_wr_be = '1;
    end
  end

  unified_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(UB_DEPTH),
    .ADDR_WIDTH(UB_ADDR_WIDTH)
  ) u_unified_buffer (
    .clk,
    .rst,
    .wr_en(ub_mem_wr_en),
    .wr_addr(ub_mem_wr_addr),
    .wr_data(ub_mem_wr_data),
    .wr_be(ub_mem_wr_be),
    .rd_en(ub_mem_rd_en),
    .rd_addr(ub_mem_rd_addr),
    .rd_valid(ub_mem_rd_valid),
    .rd_data(ub_mem_rd_data)
  );

  assign ub_rd_valid = ub_mem_rd_valid;
  assign ub_rd_data = ub_mem_rd_data;

  always_ff @(posedge clk) begin
    if (!rst) begin
      if (dma_ub_wr_en && (tensor_ub_wr_en || vector_result_fire))
        $fatal(1, "multiple Unified Buffer write owners are active");
      if (tensor_ub_wr_en && vector_result_fire)
        $fatal(1, "tensor and vector write owners are active together");
      if (tensor_busy && (state_q != S_TENSOR_START) &&
          (state_q != S_TENSOR_WAIT))
        $fatal(1, "tensor controller is busy outside tensor top-level states");
      if (ep_busy && (state_q != S_EPILOGUE_START) &&
          (state_q != S_EPILOGUE_WAIT))
        $fatal(1, "epilogue controller is busy outside epilogue top-level states");
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= S_IDLE;
      op_q <= OP_LOAD;
      id_q <= '0;
      hartid_q <= '0;
      rd_q <= '0;
      mem_addr_q <= '0;
      ub_base_q <= '0;
      tile_count_q <= '0;
      vec_src_a_q <= '0;
      vec_src_b_q <= '0;
      vec_dst_q <= '0;
      vec_funct3_q <= '0;
      tensor_accumulate_q <= 1'b0;
      ep_config_addr_q <= '0;
      rs1_q <= '0;
      rs2_q <= '0;
      register_seen_q <= 1'b0;
      committed_q <= 1'b0;
      command_err_q <= 1'b0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (issue_fire) begin
            id_q <= xif.issue_req.id;
            hartid_q <= xif.issue_req.hartid;
            rd_q <= xif.issue_req.instr[11:7];
            op_q <= issue_load ? OP_LOAD :
                (issue_store ? OP_STORE :
                (issue_tensor ? OP_TENSOR :
                (issue_epilogue ? OP_EPILOGUE : OP_VECTOR)));
            vec_funct3_q <= xif.issue_req.instr[14:12];
            register_seen_q <= 1'b0;
            committed_q <= 1'b0;
            command_err_q <= 1'b0;
            state_q <= S_WAIT_COMMIT;
          end
        end
        S_WAIT_COMMIT: begin
          if (register_fire) begin
            rs1_q <= xif.register.rs[0];
            rs2_q <= xif.register.rs[1];
            mem_addr_q <= xif.register.rs[0];
            ub_base_q <= xif.register.rs[1][UB_ADDR_WIDTH-1:0];
            tile_count_q <= xif.register.rs[1][15:8];
            vec_src_a_q <= xif.register.rs[0][UB_ADDR_WIDTH-1:0];
            vec_src_b_q <= xif.register.rs[0][8 +: UB_ADDR_WIDTH];
            vec_dst_q <= xif.register.rs[1][UB_ADDR_WIDTH-1:0];
            tensor_accumulate_q <= xif.register.rs[1][TENSOR_GEMM_ACCUMULATE_BIT];
            ep_config_addr_q <= xif.register.rs[1][15:8];
            register_seen_q <= 1'b1;
            if (!register_match || !register_operands_valid)
              command_err_q <= 1'b1;
          end
          if (commit_fire)
            committed_q <= 1'b1;

          if (kill_fire) begin
            state_q <= S_IDLE;
            register_seen_q <= 1'b0;
            committed_q <= 1'b0;
          end else if ((register_seen_q || register_fire) &&
                       (committed_q || commit_fire)) begin
            state_q <= S_DISPATCH;
          end
        end
        S_DISPATCH: begin
          if (command_err_q || !operands_valid) begin
            command_err_q <= 1'b1;
            state_q <= S_RESULT;
          end else begin
            state_q <= (op_q == OP_VECTOR) ? S_VEC_READ_A :
                ((op_q == OP_TENSOR) ? S_TENSOR_START :
                ((op_q == OP_EPILOGUE) ? S_EPILOGUE_START : S_DMA_START));
          end
        end
        S_DMA_START: begin
          if (dma_cmd_valid && dma_cmd_ready)
            state_q <= S_DMA_WAIT;
        end
        S_DMA_WAIT: begin
          if (dma_done)
            state_q <= S_RESULT;
        end
        S_VEC_READ_A: state_q <= S_VEC_LOAD_A;
        S_VEC_LOAD_A: begin
          if (vector_load_valid && vector_load_ready)
            state_q <= S_VEC_READ_B;
        end
        S_VEC_READ_B: state_q <= S_VEC_LOAD_B;
        S_VEC_LOAD_B: begin
          if (vector_load_valid && vector_load_ready)
            state_q <= S_VEC_COMMAND;
        end
        S_VEC_COMMAND: begin
          if (vector_cmd_valid && vector_cmd_ready)
            state_q <= S_VEC_WAIT;
        end
        S_VEC_WAIT: begin
          if (vector_result_fire)
            state_q <= S_RESULT;
        end
        S_TENSOR_START: begin
          if (tensor_cmd_valid && tensor_cmd_ready)
            state_q <= S_TENSOR_WAIT;
        end
        S_TENSOR_WAIT: begin
          if (tensor_done)
            state_q <= S_RESULT;
        end
        S_EPILOGUE_START: begin
          if (ep_cmd_valid && ep_cmd_ready)
            state_q <= S_EPILOGUE_WAIT;
        end
        S_EPILOGUE_WAIT: begin
          if (ep_done)
            state_q <= S_RESULT;
        end
        S_RESULT: begin
          if (xif.result_valid && xif.result_ready)
            state_q <= S_IDLE;
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end
endmodule
