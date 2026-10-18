`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mt_dma_bridge -- miniTensor 128-bit uncached DMA port -> DPI memory.
//
// miniTensor's DMA is request/response split for reads (single outstanding, no
// ID, no burst, one beat = 16 B) and a plain single-channel handshake for writes
// (no response channel, mem_wr_be hardwired all ones).  See
// miniTensor/handoff/dma_interface.md section 2.
//
// Under Verilator the JYD platform memory is a flat C++ byte array behind DPI
// (npc/csrc/wave/mem.cpp, reachable from RTL through vsrc/testbench/IP/BRAM.v),
// so the accelerator's second master port is simply a second DPI client -- no
// BRAM port arbitration is required in simulation.  On FPGA this becomes a real
// second memory port and needs a proper multi-port memory or a bus.
//
// The 128-bit beat is passed to C as four 32-bit words to keep the DPI signature
// free of 4-state vector types.
// -----------------------------------------------------------------------------
module mt_dma_bridge (
    input  logic         clk,
    input  logic         rst,           // synchronous, active high

    // miniTensor DMA master
    input  logic         mem_rd_valid,
    output logic         mem_rd_ready,
    input  logic [31:0]  mem_rd_addr,
    output logic         mem_rsp_valid,
    input  logic         mem_rsp_ready,
    output logic [127:0] mem_rsp_data,

    input  logic         mem_wr_valid,
    output logic         mem_wr_ready,
    input  logic [31:0]  mem_wr_addr,
    input  logic [127:0] mem_wr_data,
    input  logic [15:0]  mem_wr_be
);

  import "DPI-C" function void mt_dma_read (
      input  int addr, output int w0, output int w1, output int w2, output int w3);
  import "DPI-C" function void mt_dma_write(
      input  int addr, input  int w0, input  int w1, input  int w2, input  int w3);

  typedef enum logic { R_IDLE, R_RESP } rd_state_t;
  rd_state_t rd_state_q;

  logic [127:0] rd_data_q;
  int           w0, w1, w2, w3;

  // Request is accepted only when idle; the response is presented for exactly
  // one handshake, at least one cycle after the request was accepted.
  assign mem_rd_ready  = (rd_state_q == R_IDLE);
  assign mem_rsp_valid = (rd_state_q == R_RESP);
  assign mem_rsp_data  = rd_data_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      rd_state_q <= R_IDLE;
      rd_data_q  <= 128'd0;
    end else begin
      case (rd_state_q)
        R_IDLE: begin
          if (mem_rd_valid && mem_rd_ready) begin
            mt_dma_read(mem_rd_addr, w0, w1, w2, w3);
            rd_data_q  <= {w3, w2, w1, w0};
            rd_state_q <= R_RESP;
          end
        end
        R_RESP: begin
          if (mem_rsp_ready) rd_state_q <= R_IDLE;
        end
        default: rd_state_q <= R_IDLE;
      endcase
    end
  end

  // Write channel: address, data and be are valid together and a single
  // handshake completes the beat.  mem_wr_be is always all ones by contract, so
  // the DPI write covers the whole 16-byte line.
  assign mem_wr_ready = 1'b1;

  always_ff @(posedge clk) begin
    if (!rst && mem_wr_valid && mem_wr_ready) begin
      mt_dma_write(mem_wr_addr,
                   mem_wr_data[31:0], mem_wr_data[63:32],
                   mem_wr_data[95:64], mem_wr_data[127:96]);
    end
  end

endmodule
