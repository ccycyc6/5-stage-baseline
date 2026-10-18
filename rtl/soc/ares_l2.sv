`timescale 1ns/1ps
// Shared L2: 128 KiB 4-way write-back cache + 192 KiB scratchpad.
// Five request ports (4 cores + video), one in-flight request, video priority.
// The L2 also decodes Boot ROM, CLINT/PLIC/Mailbox/MMIO and QSPI.
module ares_l2 #(
  parameter int unsigned CACHE_SETS = 1024,
  parameter int unsigned SCRATCH_WORDS = 12288, // 192 KiB / 16 B
  parameter int unsigned ROM_WORDS = 16384,     // 64 KiB / 4 B
  parameter int unsigned QSPI_WORDS = 16384     // 64 KiB simulation model
) (
  input  logic          clk,
  input  logic          rst,

  // Ports 0..3 = cores, port 4 = video.
  input  logic [4:0]         req_valid,
  output logic [4:0]         req_ready,
  input  logic [4:0]         req_write,
  input  logic [4:0][31:0]   req_addr,
  input  logic [4:0][127:0]  req_wdata,
  input  logic [4:0][15:0]   req_wstrb,
  output logic [4:0]         rsp_valid,
  input  logic [4:0]         rsp_ready,
  output logic [4:0][127:0]  rsp_rdata,
  output logic [4:0]         rsp_error,

  // DDR3 master (16-byte beats).
  output logic         ddr_req_valid,
  input  logic         ddr_req_ready,
  output logic         ddr_req_write,
  output logic [31:0]  ddr_req_addr,
  output logic [127:0] ddr_req_wdata,
  output logic [15:0]  ddr_req_wstrb,
  input  logic         ddr_rsp_valid,
  output logic         ddr_rsp_ready,
  input  logic [127:0] ddr_rsp_rdata,

  // 32-bit MMIO bus.
  output logic         mmio_req_valid,
  input  logic         mmio_req_ready,
  output logic         mmio_req_write,
  output logic [31:0]  mmio_req_addr,
  output logic [31:0]  mmio_req_wdata,
  output logic [3:0]   mmio_req_wstrb,
  input  logic         mmio_rsp_valid,
  output logic         mmio_rsp_ready,
  input  logic [31:0]  mmio_rsp_rdata
);
  import ares_pkg::*;

  localparam int unsigned INDEX_BITS = $clog2(CACHE_SETS);

  // ------------------------------------------------------------------ arrays
  logic [16:0]  tag_q [0:3][0:CACHE_SETS-1];
  logic         valid_q [0:3][0:CACHE_SETS-1];
  logic         dirty_q [0:3][0:CACHE_SETS-1];
  logic [255:0] data_q  [0:3][0:CACHE_SETS-1];
  logic [1:0]   lru_q   [0:CACHE_SETS-1];

  logic [127:0] sp_mem [0:SCRATCH_WORDS-1];
  logic [31:0]  rom_mem [0:ROM_WORDS-1];
  logic [31:0]  qspi_mem [0:QSPI_WORDS-1];

  initial begin
    // Boot ROM trampoline: lui x1, 0x80000 ; jalr x0, 0(x1)
    rom_mem[0] = 32'h8000_00b7;
    rom_mem[1] = 32'h0000_8067;
  end

  // --------------------------------------------------------------- port mux
  typedef enum logic [4:0] {
    S_IDLE,
    S_SCRATCH,
    S_ROM,
    S_QSPI,
    S_MMIO_REQ,
    S_MMIO_WAIT,
    S_DDR_REQ,
    S_DDR_WAIT,
    S_CACHE_CHECK,
    S_EVICT0,
    S_EVICT0_WAIT,
    S_EVICT1,
    S_EVICT1_WAIT,
    S_REFILL0,
    S_REFILL0_WAIT,
    S_REFILL1,
    S_REFILL1_WAIT,
    S_FILL,
    S_RESP,
    S_ERROR
  } state_t;
  state_t state_q;

  logic [2:0] sel_q;
  logic [1:0] rr_q;
  logic [2:0] port_q;

  logic        req_write_q;
  logic [31:0] req_addr_q;
  logic [127:0] req_wdata_q;
  logic [15:0] req_wstrb_q;
  logic [4:0]  req_valid_q;

  logic [127:0] rsp_data_q;
  logic         rsp_valid_q;

  logic [127:0] sp_rdata_q;
  logic [127:0] rom_rdata_q;
  logic [127:0] qspi_rdata_q;

  logic [1:0]   victim_way_q;
  logic [255:0] evict_line_q;
  logic [31:0]  line_base_q;
  logic [127:0] refill_lo_q, refill_hi_q;

  logic [1:0]   hit_way;
  logic         cache_hit;
  logic [255:0] rd_line_q [0:3];
  logic [16:0]  rd_tag_q [0:3];
  logic         rd_valid_q [0:3];
  logic         rd_dirty_q [0:3];

  logic [127:0] rd_line_hit;
  logic [127:0] merged_beat;
  logic [255:0] merged_line;
  logic [31:0]  evict_base_q;
  logic [127:0] sp_tmp;
  logic [255:0] fill_line;

  assign ddr_rsp_ready = (state_q == S_DDR_WAIT) ||
                         (state_q == S_EVICT0_WAIT) || (state_q == S_EVICT1_WAIT) ||
                         (state_q == S_REFILL0_WAIT) || (state_q == S_REFILL1_WAIT);
  assign mmio_rsp_ready = (state_q == S_MMIO_WAIT);

  // Request arbitration.
  always_comb begin
    req_ready = 5'b00000;
    sel_q = 3'd0;
    if (state_q == S_IDLE) begin
      if (req_valid[4]) begin
        sel_q = 3'd4;
      end else begin
        // Round-robin over the four core ports.
        case (rr_q)
          2'd0: sel_q = req_valid[0] ? 3'd0 : (req_valid[1] ? 3'd1 : (req_valid[2] ? 3'd2 : 3'd3));
          2'd1: sel_q = req_valid[1] ? 3'd1 : (req_valid[2] ? 3'd2 : (req_valid[3] ? 3'd3 : 3'd0));
          2'd2: sel_q = req_valid[2] ? 3'd2 : (req_valid[3] ? 3'd3 : (req_valid[0] ? 3'd0 : 3'd1));
          default: sel_q = req_valid[3] ? 3'd3 : (req_valid[0] ? 3'd0 : (req_valid[1] ? 3'd1 : 3'd2));
        endcase
      end
      if (req_valid[sel_q]) req_ready[sel_q] = 1'b1;
    end
  end

  wire req_fire = (state_q == S_IDLE) && req_valid[sel_q] && req_ready[sel_q];

  always_comb begin
    rsp_valid = 5'b00000;
    rsp_rdata = '0;
    rsp_error = 5'b00000;
    if (rsp_valid_q) begin
      rsp_valid[port_q] = 1'b1;
      rsp_rdata[port_q] = rsp_data_q;
    end
  end

  // Address classification.
  wire [31:0] cur_addr = req_addr_q;
  wire [31:0] new_addr = req_addr[sel_q];
  wire is_scratch = (cur_addr >= SCRATCH_BASE) && (cur_addr < (SCRATCH_BASE + SCRATCH_SIZE));
  wire is_rom     = (cur_addr < ROM_SIZE);
  wire is_qspi    = (cur_addr >= QSPI_BASE) && (cur_addr < (QSPI_BASE + QSPI_SIZE));
  wire is_mmio    = ((cur_addr >= CLINT_BASE) && (cur_addr < MBOX_BASE + 32'h1_0000)) ||
                    ((cur_addr >= MMIO_BASE) && (cur_addr < MMIO_BASE + MMIO_SIZE)) ||
                    ((cur_addr >= DEBUG_BASE) && (cur_addr < DEBUG_BASE + 32'h1_0000));
  wire is_ddr_unc = (cur_addr >= DDR_UNC_BASE) && (cur_addr < (DDR_UNC_BASE + DDR_UNC_SIZE));
  wire is_ddr_c   = (cur_addr >= DDR_BASE) && (cur_addr < (DDR_BASE + DDR_SIZE));

  wire new_is_scratch = (new_addr >= SCRATCH_BASE) && (new_addr < (SCRATCH_BASE + SCRATCH_SIZE));
  wire new_is_rom     = (new_addr < ROM_SIZE);
  wire new_is_qspi    = (new_addr >= QSPI_BASE) && (new_addr < (QSPI_BASE + QSPI_SIZE));
  wire new_is_mmio    = ((new_addr >= CLINT_BASE) && (new_addr < MBOX_BASE + 32'h1_0000)) ||
                        ((new_addr >= MMIO_BASE) && (new_addr < MMIO_BASE + MMIO_SIZE)) ||
                        ((new_addr >= DEBUG_BASE) && (new_addr < DEBUG_BASE + 32'h1_0000));
  wire new_is_ddr_unc = (new_addr >= DDR_UNC_BASE) && (new_addr < (DDR_UNC_BASE + DDR_UNC_SIZE));
  wire new_is_ddr_c   = (new_addr >= DDR_BASE) && (new_addr < (DDR_BASE + DDR_SIZE));

  wire [16:0] cur_tag = cur_addr[31:15];
  wire [9:0]  cur_set = cur_addr[14:5];
  wire        cur_beat = cur_addr[4];
  wire [31:0] ddr_phys_addr = is_ddr_unc ? (DDR_BASE + (cur_addr - DDR_UNC_BASE)) : cur_addr;
  wire [31:0] cache_line_base = {cur_addr[31:5], 5'b0};

  // Cache compare.
  always_comb begin
    cache_hit = 1'b0;
    hit_way = 2'd0;
    for (int unsigned w = 0; w < 4; w++) begin
      if (rd_valid_q[w] && (rd_tag_q[w] == cur_tag)) begin
        cache_hit = 1'b1;
        hit_way = 2'(w);
      end
    end
    rd_line_hit = rd_line_q[hit_way][cur_beat*128 +: 128];
  end

  always_comb begin
    merged_beat = rd_line_q[hit_way][cur_beat*128 +: 128];
    for (int unsigned b = 0; b < 16; b++) begin
      if (req_wstrb_q[b]) merged_beat[b*8 +: 8] = req_wdata_q[b*8 +: 8];
    end
    merged_line = rd_line_q[hit_way];
    merged_line[cur_beat*128 +: 128] = merged_beat;
  end

  // Victim selection: invalid first, otherwise round-robin.
  always_comb begin
    if (!rd_valid_q[0]) victim_way_q = 2'd0;
    else if (!rd_valid_q[1]) victim_way_q = 2'd1;
    else if (!rd_valid_q[2]) victim_way_q = 2'd2;
    else if (!rd_valid_q[3]) victim_way_q = 2'd3;
    else victim_way_q = lru_q[cur_set];
  end

  function automatic logic [31:0] tag_to_addr(input logic [16:0] tag, input logic [9:0] set);
    tag_to_addr = {tag, set, 5'b0};
  endfunction

  // DDR request mux.
  always_comb begin
    ddr_req_valid = 1'b0;
    ddr_req_write = 1'b0;
    ddr_req_addr  = 32'd0;
    ddr_req_wdata = 128'd0;
    ddr_req_wstrb = 16'd0;
    case (state_q)
      S_DDR_REQ: begin
        ddr_req_valid = 1'b1;
        ddr_req_write = req_write_q;
        ddr_req_addr  = {ddr_phys_addr[31:4], 4'b0};
        ddr_req_wdata = req_wdata_q;
        ddr_req_wstrb = req_wstrb_q;
      end
      S_EVICT0: begin
        ddr_req_valid = 1'b1; ddr_req_write = 1'b1;
        ddr_req_addr = evict_base_q;
        ddr_req_wdata = evict_line_q[127:0];
        ddr_req_wstrb = 16'hFFFF;
      end
      S_EVICT1: begin
        ddr_req_valid = 1'b1; ddr_req_write = 1'b1;
        ddr_req_addr = evict_base_q + 32'd16;
        ddr_req_wdata = evict_line_q[255:128];
        ddr_req_wstrb = 16'hFFFF;
      end
      S_REFILL0: begin
        ddr_req_valid = 1'b1; ddr_req_write = 1'b0;
        ddr_req_addr = line_base_q;
      end
      S_REFILL1: begin
        ddr_req_valid = 1'b1; ddr_req_write = 1'b0;
        ddr_req_addr = line_base_q + 32'd16;
      end
      default: ;
    endcase
  end

  // MMIO request.
  assign mmio_req_valid = (state_q == S_MMIO_REQ);
  assign mmio_req_write = req_write_q;
  assign mmio_req_addr  = {req_addr_q[31:2], 2'b00};
  assign mmio_req_wdata = req_wdata_q[31:0];
  assign mmio_req_wstrb = req_wstrb_q[3:0];

  // ------------------------------------------------------------------- FSM
  integer l2_stuck_cnt;
  always_ff @(posedge clk) begin
    if (rst) l2_stuck_cnt <= 0;
    else if (state_q != S_IDLE) begin
      l2_stuck_cnt <= l2_stuck_cnt + 1;
      if (l2_stuck_cnt == 2000) begin
        
      end
    end else l2_stuck_cnt <= 0;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= S_IDLE;
      rr_q <= 2'd0;
      port_q <= 3'd0;
      req_write_q <= 1'b0;
      req_addr_q <= 32'd0;
      req_wdata_q <= 128'd0;
      req_wstrb_q <= 16'd0;
      rsp_data_q <= 128'd0;
      rsp_valid_q <= 1'b0;
      sp_rdata_q <= 128'd0;
      rom_rdata_q <= 128'd0;
      qspi_rdata_q <= 128'd0;
      evict_line_q <= 256'd0;
      evict_base_q <= 32'd0;
      line_base_q <= 32'd0;
      refill_lo_q <= 128'd0;
      refill_hi_q <= 128'd0;
      for (int unsigned w = 0; w < 4; w++) begin
        rd_line_q[w] <= 256'd0;
        rd_tag_q[w] <= 17'd0;
        rd_valid_q[w] <= 1'b0;
        rd_dirty_q[w] <= 1'b0;
        for (int unsigned s = 0; s < CACHE_SETS; s++) begin
          tag_q[w][s] <= 17'd0;
          valid_q[w][s] <= 1'b0;
          dirty_q[w][s] <= 1'b0;
          data_q[w][s] <= 256'd0;
        end
      end
      for (int unsigned s = 0; s < CACHE_SETS; s++) lru_q[s] <= 2'd0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (req_fire) begin
            if ((req_addr[sel_q] & 32'hFFFF_FFE0) == 32'h8000_54A0) begin
              
            end
            port_q <= sel_q;
            req_write_q <= req_write[sel_q];
            req_addr_q <= req_addr[sel_q];
            req_wdata_q <= req_wdata[sel_q];
            req_wstrb_q <= req_wstrb[sel_q];
            if (sel_q != 3'd4) rr_q <= rr_q + 2'd1;

            if (new_is_rom) begin
              rom_rdata_q <= {rom_mem[req_addr[sel_q][15:2] + 3],
                              rom_mem[req_addr[sel_q][15:2] + 2],
                              rom_mem[req_addr[sel_q][15:2] + 1],
                              rom_mem[req_addr[sel_q][15:2]]};
              state_q <= S_ROM;
            end else if (new_is_scratch) begin
              sp_rdata_q <= sp_mem[(req_addr[sel_q] - SCRATCH_BASE) >> 4];
              if (req_write[sel_q]) begin
                sp_tmp = sp_mem[(req_addr[sel_q] - SCRATCH_BASE) >> 4];
                for (int unsigned b = 0; b < 16; b++) begin
                  if (req_wstrb[sel_q][b]) sp_tmp[b*8 +: 8] = req_wdata[sel_q][b*8 +: 8];
                end
                sp_mem[(req_addr[sel_q] - SCRATCH_BASE) >> 4] <= sp_tmp;
              end
              state_q <= S_SCRATCH;
            end else if (new_is_qspi) begin
              qspi_rdata_q <= {qspi_mem[((req_addr[sel_q] - QSPI_BASE) >> 2) + 3],
                               qspi_mem[((req_addr[sel_q] - QSPI_BASE) >> 2) + 2],
                               qspi_mem[((req_addr[sel_q] - QSPI_BASE) >> 2) + 1],
                               qspi_mem[((req_addr[sel_q] - QSPI_BASE) >> 2)]};
              state_q <= S_QSPI;
            end else if (new_is_mmio) begin
              state_q <= S_MMIO_REQ;
            end else if (new_is_ddr_unc) begin
              state_q <= S_DDR_REQ;
            end else if (new_is_ddr_c) begin
              for (int unsigned w = 0; w < 4; w++) begin
                rd_tag_q[w] <= tag_q[w][req_addr[sel_q][14:5]];
                rd_valid_q[w] <= valid_q[w][req_addr[sel_q][14:5]];
                rd_dirty_q[w] <= dirty_q[w][req_addr[sel_q][14:5]];
                rd_line_q[w] <= data_q[w][req_addr[sel_q][14:5]];
              end
              state_q <= S_CACHE_CHECK;
            end else begin
              state_q <= S_ERROR;
            end
          end
        end

        S_SCRATCH: begin
          rsp_data_q <= sp_rdata_q;
          state_q <= S_RESP;
        end
        S_ROM: begin
          rsp_data_q <= rom_rdata_q;
          state_q <= S_RESP;
        end
        S_QSPI: begin
          rsp_data_q <= qspi_rdata_q;
          state_q <= S_RESP;
        end
        S_MMIO_REQ: begin
          if (mmio_req_valid && mmio_req_ready) state_q <= S_MMIO_WAIT;
        end
        S_MMIO_WAIT: begin
          if (mmio_rsp_valid) begin
            rsp_data_q <= 128'd0;
            rsp_data_q[cur_addr[3:2]*32 +: 32] <= mmio_rsp_rdata;
            state_q <= S_RESP;
          end
        end
        S_DDR_REQ: begin
          if (ddr_req_valid && ddr_req_ready) state_q <= S_DDR_WAIT;
        end
        S_DDR_WAIT: begin
          if (ddr_rsp_valid) begin
            rsp_data_q <= ddr_rsp_rdata;
            state_q <= S_RESP;
          end
        end

        S_CACHE_CHECK: begin
          if ((cur_addr & 32'hFFFF_FFE0) == 32'h8000_54A0) begin
            
          end
          if (cache_hit) begin
            if (req_write_q) begin
              data_q[hit_way][cur_set] <= merged_line;
              dirty_q[hit_way][cur_set] <= 1'b1;
              rsp_data_q <= 128'd0;
            end else begin
              rsp_data_q <= rd_line_hit;
            end
            lru_q[cur_set] <= (hit_way == 2'd3) ? 2'd0 : hit_way + 2'd1;
            state_q <= S_RESP;
          end else begin
            line_base_q <= cache_line_base;
            if (rd_valid_q[victim_way_q] && rd_dirty_q[victim_way_q]) begin
              evict_line_q <= data_q[victim_way_q][cur_set];
              evict_base_q <= tag_to_addr(rd_tag_q[victim_way_q], cur_set);
              state_q <= S_EVICT0;
            end else begin
              state_q <= S_REFILL0;
            end
          end
        end
        S_EVICT0: if (ddr_req_valid && ddr_req_ready) state_q <= S_EVICT0_WAIT;
        S_EVICT0_WAIT: if (ddr_rsp_valid) state_q <= S_EVICT1;
        S_EVICT1: if (ddr_req_valid && ddr_req_ready) state_q <= S_EVICT1_WAIT;
        S_EVICT1_WAIT: if (ddr_rsp_valid) state_q <= S_REFILL0;
        S_REFILL0: if (ddr_req_valid && ddr_req_ready) state_q <= S_REFILL0_WAIT;
        S_REFILL0_WAIT: if (ddr_rsp_valid) begin
          refill_lo_q <= ddr_rsp_rdata;
          state_q <= S_REFILL1;
        end
        S_REFILL1: if (ddr_req_valid && ddr_req_ready) state_q <= S_REFILL1_WAIT;
        S_REFILL1_WAIT: if (ddr_rsp_valid) begin
          refill_hi_q <= ddr_rsp_rdata;
          state_q <= S_FILL;
        end
        S_FILL: begin
          fill_line = {refill_hi_q, refill_lo_q};
          if ((cur_addr & 32'hFFFF_FFE0) == 32'h8000_54A0) begin
            
          end
          if (req_write_q) begin
            for (int unsigned b = 0; b < 16; b++) begin
              if (req_wstrb_q[b]) fill_line[cur_beat*128 + b*8 +: 8] = req_wdata_q[b*8 +: 8];
            end
          end
          data_q[victim_way_q][cur_set] <= fill_line;
          tag_q[victim_way_q][cur_set]  <= cur_tag;
          valid_q[victim_way_q][cur_set] <= 1'b1;
          dirty_q[victim_way_q][cur_set] <= req_write_q;
          lru_q[cur_set] <= (victim_way_q == 2'd3) ? 2'd0 : victim_way_q + 2'd1;
          rsp_data_q <= fill_line[cur_beat*128 +: 128];
          state_q <= S_RESP;
        end
        S_ERROR: begin
          rsp_data_q <= 128'd0;
          state_q <= S_RESP;
        end
        S_RESP: begin
          if (rsp_valid_q && rsp_ready[port_q]) begin
            rsp_valid_q <= 1'b0;
            state_q <= S_IDLE;
          end else begin
            rsp_valid_q <= 1'b1;
          end
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end
endmodule