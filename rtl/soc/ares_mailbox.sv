`timescale 1ns/1ps
// 4-hart mailbox, doorbell and barrier.
module ares_mailbox #(
  parameter int unsigned HARTS = 4,
  parameter int unsigned SLOTS = 16
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

  output logic        mbox_irq,
  output logic        barrier_irq
);
  logic [31:0] slot_q [0:HARTS-1][0:SLOTS-1];
  logic [31:0] doorbell_q;
  logic [HARTS-1:0] barrier_q;
  logic        barrier_hit_q;

  integer h, s;

  assign req_ready = 1'b1;
  assign rsp_valid = req_valid;
  assign mbox_irq = |doorbell_q;
  assign barrier_irq = barrier_hit_q;

  always_comb begin
    rsp_rdata = 32'd0;
    if (req_addr < 32'h0000_1000) begin
      for (h = 0; h < HARTS; h = h + 1) begin
        for (s = 0; s < SLOTS; s = s + 1) begin
          if (req_addr == 32'(h * 32'h40 + s * 4))
            rsp_rdata = slot_q[h][s];
        end
      end
    end else if (req_addr >= 32'h0000_1000 && req_addr < 32'h0000_2000) begin
      rsp_rdata = doorbell_q;
    end else if (req_addr == 32'h0000_2000) begin
      rsp_rdata = {31'd0, barrier_hit_q};
    end else if (req_addr == 32'h0000_2004) begin
      rsp_rdata = {28'd0, barrier_q};
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      doorbell_q <= 32'd0;
      barrier_q <= '0;
      barrier_hit_q <= 1'b0;
      for (h = 0; h < HARTS; h = h + 1)
        for (s = 0; s < SLOTS; s = s + 1)
          slot_q[h][s] <= 32'd0;
    end else begin
      if (req_valid && req_ready) begin
        if (req_write) begin
          if (req_addr < 32'h0000_1000) begin
            for (h = 0; h < HARTS; h = h + 1) begin
              for (s = 0; s < SLOTS; s = s + 1) begin
                if (req_addr == 32'(h * 32'h40 + s * 4))
                  slot_q[h][s] <= req_wdata;
              end
            end
          end else if (req_addr >= 32'h0000_1000 && req_addr < 32'h0000_2000) begin
            doorbell_q <= doorbell_q | req_wdata;
          end else if (req_addr == 32'h0000_2000) begin
            barrier_q <= barrier_q | req_wdata[3:0];
            if ((barrier_q | req_wdata[3:0]) == 4'hF) begin
              barrier_hit_q <= 1'b1;
              barrier_q <= 4'h0;
            end
          end else if (req_addr == 32'h0000_2004) begin
            barrier_q <= 4'h0;
            barrier_hit_q <= 1'b0;
          end
        end else begin
          if (req_addr >= 32'h0000_1000 && req_addr < 32'h0000_2000) begin
            doorbell_q <= 32'd0; // read clears
          end
        end
      end
    end
  end
endmodule
