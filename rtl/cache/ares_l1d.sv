`timescale 1ns/1ps
// 8 KiB, 2-way set-associative data cache, 32-byte lines.
// Write-back + write-allocate.  Addresses outside the 0x8000_0000..0xBFFF_FFFF
// window bypass the cache and are forwarded to the cluster MMIO/L2 router.
module ares_l1d #(
  parameter int unsigned SIZE_BYTES = 8192,
  parameter int unsigned LINE_BYTES = 32,
  parameter int unsigned WAYS       = 2
) (
  input  logic         clk,
  input  logic         rst,

  input  logic         cpu_req_valid,
  output logic         cpu_req_ready,
  input  logic         cpu_req_write,
  input  logic [31:0]  cpu_req_addr,
  input  logic [31:0]  cpu_req_wdata,
  input  logic [3:0]   cpu_req_wstrb,
  output logic         cpu_rsp_valid,
  output logic [31:0]  cpu_rsp_rdata,

  output logic         l2_req_valid,
  input  logic         l2_req_ready,
  output logic         l2_req_write,
  output logic [31:0]  l2_req_addr,
  output logic [127:0] l2_req_wdata,
  output logic [15:0]  l2_req_wstrb,
  input  logic         l2_rsp_valid,
  output logic         l2_rsp_ready,
  input  logic [127:0] l2_rsp_rdata,

  // Uncached / MMIO bypass port (32-bit).
  output logic         bypass_req_valid,
  input  logic         bypass_req_ready,
  output logic         bypass_req_write,
  output logic [31:0]  bypass_req_addr,
  output logic [31:0]  bypass_req_wdata,
  output logic [3:0]   bypass_req_wstrb,
  input  logic         bypass_rsp_valid,
  output logic         bypass_rsp_ready,
  input  logic [31:0]  bypass_rsp_rdata,
  input  logic         bypass_rsp_error,

  input  logic         flush_req,
  output logic         flush_done,
  output logic         busy
);
  localparam int unsigned SETS        = SIZE_BYTES / (WAYS * LINE_BYTES);
  localparam int unsigned OFFSET_BITS = $clog2(LINE_BYTES);
  localparam int unsigned INDEX_BITS  = $clog2(SETS);
  localparam int unsigned TAG_BITS    = 32 - OFFSET_BITS - INDEX_BITS;
  localparam int unsigned LINE_BITS   = LINE_BYTES * 8;
  localparam logic [31:0] CACHE_BASE  = 32'h8000_0000;
  localparam logic [31:0] CACHE_SIZE  = 32'h4000_0000;

  logic [TAG_BITS-1:0]  tag_q   [0:WAYS-1][0:SETS-1];
  logic                 valid_q [0:WAYS-1][0:SETS-1];
  logic                 dirty_q [0:WAYS-1][0:SETS-1];
  logic [LINE_BITS-1:0] data_q  [0:WAYS-1][0:SETS-1];
  logic                 lru_q   [0:SETS-1];

  typedef enum logic [4:0] {
    ST_IDLE,
    ST_LOOKUP,
    ST_RESP,
    ST_EVICT0,
    ST_EVICT0_WAIT,
    ST_EVICT1,
    ST_EVICT1_WAIT,
    ST_REFILL0,
    ST_REFILL0_WAIT,
    ST_REFILL1,
    ST_REFILL1_WAIT,
    ST_FILL,
    ST_BYPASS_REQ,
    ST_BYPASS_WAIT,
    ST_FLUSH_CHECK,
    ST_FLUSH_WB0,
    ST_FLUSH_WB0_WAIT,
    ST_FLUSH_WB1,
    ST_FLUSH_WB1_WAIT,
    ST_FLUSH_CLEAR,
    ST_FLUSH_ADV
  } state_t;
  state_t state_q;

  logic [31:0] req_addr_q;
  logic        req_write_q;
  logic [31:0] req_wdata_q;
  logic [3:0]  req_wstrb_q;
  logic [TAG_BITS-1:0] req_tag_q;
  logic [INDEX_BITS-1:0] req_set_q;
  logic [31:0] line_base_q;
  logic [1:0]  victim_way_q;

  logic [LINE_BITS-1:0] rd_line_q [0:WAYS-1];
  logic [127:0] refill_lo_q, refill_hi_q;
  logic [LINE_BITS-1:0] wb_line_q;
  logic [31:0] rsp_data_q;
  logic        rsp_valid_q;

  // Flush state
  logic flush_active_q, flush_done_q;
  logic [INDEX_BITS-1:0] flush_set_q;
  logic [1:0] flush_way_q;

  assign cpu_req_ready = (state_q == ST_IDLE) && !flush_active_q && !flush_done_q;
  assign cpu_rsp_valid = rsp_valid_q;
  assign cpu_rsp_rdata = rsp_data_q;
  assign flush_done    = flush_done_q;
  assign busy = (state_q != ST_IDLE) || flush_active_q;

  wire is_cached = (cpu_req_addr >= CACHE_BASE) &&
                   (cpu_req_addr < (CACHE_BASE + CACHE_SIZE));

  wire [TAG_BITS-1:0]   tag_f   = req_addr_q[31:OFFSET_BITS+INDEX_BITS];
  wire [INDEX_BITS-1:0] set_f   = req_addr_q[OFFSET_BITS +: INDEX_BITS];
  wire [4:0]            word_f  = req_addr_q[4:2];

  logic hit0, hit1, hit;
  logic [1:0] hit_way;
  always_comb begin
    hit0 = valid_q[0][set_f] && (tag_q[0][set_f] == tag_f);
    hit1 = valid_q[1][set_f] && (tag_q[1][set_f] == tag_f);
    hit  = hit0 || hit1;
    hit_way = hit0 ? 2'd0 : 2'd1;
  end

  logic [LINE_BITS-1:0] hit_line;
  logic [31:0] hit_word;
  logic [LINE_BITS-1:0] hit_write_line;
  always_comb begin
    hit_line = hit0 ? rd_line_q[0] : rd_line_q[1];
    hit_word = hit_line[word_f*32 +: 32];
    hit_write_line = hit_line;
    for (int unsigned b = 0; b < 4; b++) begin
      if (req_wstrb_q[b]) begin
        hit_write_line[word_f*32 + b*8 +: 8] = req_wdata_q[b*8 +: 8];
      end
    end
  end

  logic [1:0] victim_way;
  always_comb begin
    if (!valid_q[0][set_f])      victim_way = 2'd0;
    else if (!valid_q[1][set_f]) victim_way = 2'd1;
    else                          victim_way = lru_q[set_f] ? 2'd0 : 2'd1;
  end

  // Merge the pending store into a full line.
  logic [LINE_BITS-1:0] merged_line;
  always_comb begin
    merged_line = {refill_hi_q, refill_lo_q};
    if (req_write_q) begin
      for (int unsigned b = 0; b < 4; b++) begin
        if (req_wstrb_q[b]) begin
          merged_line[word_f*32 + b*8 +: 8] = req_wdata_q[b*8 +: 8];
        end
      end
    end
  end

  function automatic logic [31:0] line_base_of(input logic [31:0] a);
    line_base_of = {a[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
  endfunction

  function automatic logic [31:0] tag_to_addr(
      input logic [TAG_BITS-1:0] tag,
      input logic [INDEX_BITS-1:0] set
  );
    tag_to_addr = {tag, set, {OFFSET_BITS{1'b0}}};
  endfunction

  logic [31:0] flush_line_base;
  assign flush_line_base = tag_to_addr(tag_q[flush_way_q][flush_set_q], flush_set_q);

  assign l2_rsp_ready = (state_q == ST_EVICT0_WAIT) || (state_q == ST_EVICT1_WAIT) ||
                        (state_q == ST_REFILL0_WAIT) || (state_q == ST_REFILL1_WAIT) ||
                        (state_q == ST_FLUSH_WB0_WAIT) || (state_q == ST_FLUSH_WB1_WAIT);

  always_comb begin
    l2_req_valid = 1'b0;
    l2_req_write = 1'b0;
    l2_req_addr  = 32'd0;
    l2_req_wdata = 128'd0;
    l2_req_wstrb = 16'd0;
    case (state_q)
      ST_EVICT0: begin
        l2_req_valid = 1'b1; l2_req_write = 1'b1;
        l2_req_addr = line_base_q; l2_req_wdata = wb_line_q[127:0]; l2_req_wstrb = 16'hFFFF;
      end
      ST_EVICT1: begin
        l2_req_valid = 1'b1; l2_req_write = 1'b1;
        l2_req_addr = line_base_q + 32'd16; l2_req_wdata = wb_line_q[255:128]; l2_req_wstrb = 16'hFFFF;
      end
      ST_REFILL0: begin
        l2_req_valid = 1'b1; l2_req_write = 1'b0;
        l2_req_addr = line_base_q;
      end
      ST_REFILL1: begin
        l2_req_valid = 1'b1; l2_req_write = 1'b0;
        l2_req_addr = line_base_q + 32'd16;
      end
      ST_FLUSH_WB0: begin
        l2_req_valid = 1'b1; l2_req_write = 1'b1;
        l2_req_addr = flush_line_base; l2_req_wdata = wb_line_q[127:0]; l2_req_wstrb = 16'hFFFF;
      end
      ST_FLUSH_WB1: begin
        l2_req_valid = 1'b1; l2_req_write = 1'b1;
        l2_req_addr = flush_line_base + 32'd16; l2_req_wdata = wb_line_q[255:128]; l2_req_wstrb = 16'hFFFF;
      end
      default: ;
    endcase
  end

  assign bypass_req_valid = (state_q == ST_BYPASS_REQ);
  assign bypass_req_write = req_write_q;
  assign bypass_req_addr  = req_addr_q;
  assign bypass_req_wdata = req_wdata_q;
  assign bypass_req_wstrb = req_wstrb_q;
  assign bypass_rsp_ready = (state_q == ST_BYPASS_WAIT);

  integer stuck_cnt;
  always_ff @(posedge clk) begin
    if (rst) stuck_cnt <= 0;
    else if (state_q != ST_IDLE) begin
      stuck_cnt <= stuck_cnt + 1;
      if (stuck_cnt == 2000) begin
        
      end
    end else stuck_cnt <= 0;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= ST_IDLE;
      rsp_valid_q <= 1'b0;
      rsp_data_q <= 32'd0;
      req_addr_q <= 32'd0;
      req_write_q <= 1'b0;
      req_wdata_q <= 32'd0;
      req_wstrb_q <= 4'd0;
      line_base_q <= 32'd0;
      victim_way_q <= 2'd0;
      refill_lo_q <= 128'd0;
      refill_hi_q <= 128'd0;
      wb_line_q <= '0;
      flush_active_q <= 1'b0;
      flush_done_q <= 1'b0;
      flush_set_q <= '0;
      flush_way_q <= 2'd0;
      for (int unsigned w = 0; w < WAYS; w++) begin
        rd_line_q[w] <= '0;
        for (int unsigned s = 0; s < SETS; s++) begin
          tag_q[w][s] <= '0;
          valid_q[w][s] <= 1'b0;
          dirty_q[w][s] <= 1'b0;
          data_q[w][s] <= '0;
        end
      end
      for (int unsigned s = 0; s < SETS; s++) lru_q[s] <= 1'b0;
    end else begin
      rsp_valid_q <= 1'b0;
      flush_done_q <= 1'b0;

      case (state_q)
        ST_IDLE: begin
          if (flush_req && !flush_active_q) begin
            flush_active_q <= 1'b1;
            flush_set_q <= '0;
            flush_way_q <= 2'd0;
            state_q <= ST_FLUSH_CHECK;
          end else if (cpu_req_valid && cpu_req_ready) begin
            req_addr_q  <= cpu_req_addr;
            req_write_q <= cpu_req_write;
            req_wdata_q <= cpu_req_wdata;
            req_wstrb_q <= cpu_req_wstrb;
            req_tag_q   <= cpu_req_addr[31:OFFSET_BITS+INDEX_BITS];
            req_set_q   <= cpu_req_addr[OFFSET_BITS +: INDEX_BITS];
            line_base_q <= line_base_of(cpu_req_addr);
            for (int unsigned w = 0; w < WAYS; w++) begin
              rd_line_q[w] <= data_q[w][cpu_req_addr[OFFSET_BITS +: INDEX_BITS]];
            end
            if (is_cached) begin
              state_q <= ST_LOOKUP;
            end else begin
              state_q <= ST_BYPASS_REQ;
            end
          end
        end
        ST_LOOKUP: begin
          if ((req_addr_q & 32'hFFFF_FFE0) == 32'h8000_54A0) begin
            
          end
          if (hit) begin
            if (req_write_q) begin
              data_q[hit_way][req_set_q] <= hit_write_line;
              dirty_q[hit_way][req_set_q] <= 1'b1;
              lru_q[req_set_q] <= (hit_way == 2'd0) ? 1'b0 : 1'b1;
              rsp_data_q <= 32'd0;
            end else begin
              rsp_data_q <= hit_word;
              lru_q[req_set_q] <= (hit_way == 2'd0) ? 1'b0 : 1'b1;
            end
            rsp_valid_q <= 1'b1;
            state_q <= ST_RESP;
          end else begin
            victim_way_q <= victim_way;
            if (valid_q[victim_way][req_set_q] && dirty_q[victim_way][req_set_q]) begin
              wb_line_q <= data_q[victim_way][req_set_q];
              line_base_q <= tag_to_addr(tag_q[victim_way][req_set_q], req_set_q);
              state_q <= ST_EVICT0;
            end else begin
              state_q <= ST_REFILL0;
            end
          end
        end
        ST_RESP: state_q <= ST_IDLE;
        ST_EVICT0: if (l2_req_valid && l2_req_ready) state_q <= ST_EVICT0_WAIT;
        ST_EVICT0_WAIT: if (l2_rsp_valid) state_q <= ST_EVICT1;
        ST_EVICT1: if (l2_req_valid && l2_req_ready) state_q <= ST_EVICT1_WAIT;
        ST_EVICT1_WAIT: if (l2_rsp_valid) state_q <= ST_REFILL0;
        ST_REFILL0: if (l2_req_valid && l2_req_ready) state_q <= ST_REFILL0_WAIT;
        ST_REFILL0_WAIT: if (l2_rsp_valid) begin
          refill_lo_q <= l2_rsp_rdata;
          state_q <= ST_REFILL1;
        end
        ST_REFILL1: if (l2_req_valid && l2_req_ready) state_q <= ST_REFILL1_WAIT;
        ST_REFILL1_WAIT: if (l2_rsp_valid) begin
          refill_hi_q <= l2_rsp_rdata;
          state_q <= ST_FILL;
        end
        ST_FILL: begin
          if ((req_addr_q & 32'hFFFF_FFE0) == 32'h8000_54A0) begin
            
          end
          data_q[victim_way_q][req_set_q] <= merged_line;
          tag_q[victim_way_q][req_set_q]  <= req_tag_q;
          valid_q[victim_way_q][req_set_q] <= 1'b1;
          dirty_q[victim_way_q][req_set_q] <= req_write_q;
          lru_q[req_set_q] <= (victim_way_q == 2'd0) ? 1'b0 : 1'b1;
          rsp_data_q <= merged_line[word_f*32 +: 32];
          rsp_valid_q <= 1'b1;
          state_q <= ST_RESP;
        end
        ST_BYPASS_REQ: begin
          if (bypass_req_ready) state_q <= ST_BYPASS_WAIT;
        end
        ST_BYPASS_WAIT: begin
          if (bypass_rsp_valid) begin
            rsp_data_q <= bypass_rsp_rdata;
            rsp_valid_q <= 1'b1;
            state_q <= ST_RESP;
          end
        end
        ST_FLUSH_CHECK: begin
          if (valid_q[flush_way_q][flush_set_q] && dirty_q[flush_way_q][flush_set_q]) begin
            wb_line_q <= data_q[flush_way_q][flush_set_q];
            state_q <= ST_FLUSH_WB0;
          end else begin
            valid_q[flush_way_q][flush_set_q] <= 1'b0;
            dirty_q[flush_way_q][flush_set_q] <= 1'b0;
            state_q <= ST_FLUSH_ADV;
          end
        end
        ST_FLUSH_WB0: if (l2_req_valid && l2_req_ready) state_q <= ST_FLUSH_WB0_WAIT;
        ST_FLUSH_WB0_WAIT: if (l2_rsp_valid) state_q <= ST_FLUSH_WB1;
        ST_FLUSH_WB1: if (l2_req_valid && l2_req_ready) state_q <= ST_FLUSH_WB1_WAIT;
        ST_FLUSH_WB1_WAIT: if (l2_rsp_valid) state_q <= ST_FLUSH_CLEAR;
        ST_FLUSH_CLEAR: begin
          valid_q[flush_way_q][flush_set_q] <= 1'b0;
          dirty_q[flush_way_q][flush_set_q] <= 1'b0;
          state_q <= ST_FLUSH_ADV;
        end
        ST_FLUSH_ADV: begin
          if (flush_way_q == 2'(WAYS-1)) begin
            flush_way_q <= 2'd0;
            if (flush_set_q == INDEX_BITS'(SETS-1)) begin
              flush_active_q <= 1'b0;
              flush_done_q <= 1'b1;
              state_q <= ST_IDLE;
            end else begin
              flush_set_q <= flush_set_q + 1'b1;
              state_q <= ST_FLUSH_CHECK;
            end
          end else begin
            flush_way_q <= flush_way_q + 1'b1;
            state_q <= ST_FLUSH_CHECK;
          end
        end
        default: state_q <= ST_IDLE;
      endcase
    end
  end
endmodule