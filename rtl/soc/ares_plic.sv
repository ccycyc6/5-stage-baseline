`timescale 1ns/1ps
// PLIC: 32 sources, 4 contexts, standard priority/enable/threshold/claim map.
module ares_plic #(
  parameter int unsigned NUM_SOURCES  = 32,
  parameter int unsigned NUM_CONTEXTS = 4
) (
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

  input  logic [NUM_SOURCES-1:0] irq_src,
  output logic [NUM_CONTEXTS-1:0] ext_irq
);
  logic [31:0] prio_q  [0:NUM_SOURCES-1];
  logic [31:0] enable_q [0:NUM_CONTEXTS-1][0:NUM_SOURCES-1];
  logic [31:0] threshold_q [0:NUM_CONTEXTS-1];
  logic [NUM_SOURCES-1:0] pending_q;
  logic [NUM_SOURCES-1:0] claimed_q [0:NUM_CONTEXTS-1];

  integer i, c, s;

  // Best pending source per context.
  logic [5:0] best_id [0:NUM_CONTEXTS-1];
  logic [31:0] best_prio [0:NUM_CONTEXTS-1];
  always_comb begin
    for (c = 0; c < NUM_CONTEXTS; c = c + 1) begin
      best_id[c] = 6'd0;
      best_prio[c] = 32'd0;
      for (s = 1; s < NUM_SOURCES; s = s + 1) begin
        if (pending_q[s] && enable_q[c][s][0] &&
            (prio_q[s] > threshold_q[c]) && (prio_q[s] > best_prio[c])) begin
          best_id[c] = 6'(s);
          best_prio[c] = prio_q[s];
        end
      end
      ext_irq[c] = (best_id[c] != 6'd0);
    end
  end

  // ------------------------------------------------------------------- read
  always_comb begin
    rsp_rdata = 32'd0;
    if (req_addr < 32'h0000_1000) begin
      for (s = 0; s < NUM_SOURCES; s = s + 1) begin
        if (req_addr == 32'(s * 4)) rsp_rdata = prio_q[s];
      end
    end else if (req_addr == 32'h0000_1000) begin
      rsp_rdata = pending_q;
    end else if (req_addr >= 32'h0000_2000 && req_addr < 32'h0000_3000) begin
      for (c = 0; c < NUM_CONTEXTS; c = c + 1) begin
        for (s = 0; s < NUM_SOURCES; s = s + 1) begin
          if (req_addr == 32'(32'h2000 + c * 32'h80 + s * 4))
            rsp_rdata = {31'd0, enable_q[c][s][0]};
        end
      end
    end else if (req_addr >= 32'h0020_0000) begin
      for (c = 0; c < NUM_CONTEXTS; c = c + 1) begin
        if (req_addr == 32'(32'h200000 + c * 32'h1000))
          rsp_rdata = threshold_q[c];
        if (req_addr == 32'(32'h200004 + c * 32'h1000))
          rsp_rdata = {26'd0, best_id[c]};
      end
    end
  end

  assign req_ready = 1'b1;
  assign rsp_valid = req_valid;

  // ------------------------------------------------------------------ state
  always_ff @(posedge clk) begin
    if (rst) begin
      pending_q <= '0;
      for (s = 0; s < NUM_SOURCES; s = s + 1) prio_q[s] <= 32'd0;
      for (c = 0; c < NUM_CONTEXTS; c = c + 1) begin
        threshold_q[c] <= 32'd0;
        claimed_q[c] <= '0;
        for (s = 0; s < NUM_SOURCES; s = s + 1) enable_q[c][s] <= 32'd0;
      end
    end else begin
      // Level-sensitive source latch.
      pending_q <= pending_q | irq_src;

      if (req_valid && req_ready) begin
        if (req_write) begin
          if (req_addr < 32'h0000_1000) begin
            for (s = 0; s < NUM_SOURCES; s = s + 1) begin
              if (req_addr == 32'(s * 4)) prio_q[s] <= req_wdata;
            end
          end else if (req_addr >= 32'h0000_2000 && req_addr < 32'h0000_3000) begin
            for (c = 0; c < NUM_CONTEXTS; c = c + 1) begin
              for (s = 0; s < NUM_SOURCES; s = s + 1) begin
                if (req_addr == 32'(32'h2000 + c * 32'h80 + s * 4))
                  enable_q[c][s][0] <= req_wdata[0];
              end
            end
          end else if (req_addr >= 32'h0020_0000) begin
            for (c = 0; c < NUM_CONTEXTS; c = c + 1) begin
              if (req_addr == 32'(32'h200000 + c * 32'h1000))
                threshold_q[c] <= req_wdata;
              if (req_addr == 32'(32'h200004 + c * 32'h1000)) begin
                for (s = 0; s < NUM_SOURCES; s = s + 1) begin
                  if (req_wdata[5:0] == 6'(s)) claimed_q[c][s] <= 1'b0;
                end
              end
            end
          end
        end else begin
          // Claim read: clear the pending bit of the returned source.
          if (req_addr >= 32'h0020_0000) begin
            for (c = 0; c < NUM_CONTEXTS; c = c + 1) begin
              if (req_addr == 32'(32'h200004 + c * 32'h1000)) begin
                for (s = 1; s < NUM_SOURCES; s = s + 1) begin
                  if (best_id[c] == 6'(s)) begin
                    pending_q[s] <= 1'b0;
                    claimed_q[c][s] <= 1'b1;
                  end
                end
              end
            end
          end
        end
      end
    end
  end
endmodule
