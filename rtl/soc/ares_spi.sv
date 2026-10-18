`timescale 1ns/1ps
// Byte-wide SPI master (mode 0).
module ares_spi (
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
  output logic        spi_sck,
  output logic        spi_mosi,
  input  logic        spi_miso,
  output logic        spi_cs_n,
  output logic        spi_irq
);
  logic [15:0] div_q;
  logic [31:0] ctrl_q;
  logic [7:0]  tx_q, rx_q;
  logic        busy_q, done_q;
  logic [7:0]  shift_q;
  logic [3:0]  bit_q;
  logic [15:0] cnt_q;
  logic        sck_q;

  assign req_ready = 1'b1;
  assign rsp_valid = req_valid;
  assign spi_sck   = sck_q;
  assign spi_mosi  = shift_q[7];
  assign spi_cs_n  = busy_q ? 1'b0 : ~ctrl_q[1];
  assign spi_irq   = done_q && ctrl_q[2];

  always_comb begin
    case (req_addr[7:0])
      8'h00: rsp_rdata = {24'd0, tx_q};
      8'h04: rsp_rdata = {24'd0, rx_q};
      8'h08: rsp_rdata = ctrl_q;
      8'h0C: rsp_rdata = {30'd0, done_q, busy_q};
      8'h10: rsp_rdata = {16'd0, div_q};
      default: rsp_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      div_q <= 16'd16;
      ctrl_q <= 32'h0000_0001;
      tx_q <= 8'd0;
      rx_q <= 8'd0;
      busy_q <= 1'b0;
      done_q <= 1'b0;
      shift_q <= 8'd0;
      bit_q <= 4'd0;
      cnt_q <= 16'd0;
      sck_q <= 1'b0;
    end else begin
      done_q <= 1'b0;

      if (busy_q) begin
        if (cnt_q >= (div_q == 16'd0 ? 16'd1 : div_q) - 16'd1) begin
          cnt_q <= 16'd0;
          if (sck_q == 1'b0) begin
            // Rising edge: sample MISO.
            sck_q <= 1'b1;
            rx_q <= {rx_q[6:0], spi_miso};
          end else begin
            // Falling edge: shift out the next bit or finish.
            sck_q <= 1'b0;
            if (bit_q == 4'd7) begin
              busy_q <= 1'b0;
              done_q <= 1'b1;
            end else begin
              bit_q <= bit_q + 4'd1;
              shift_q <= {shift_q[6:0], 1'b0};
            end
          end
        end else begin
          cnt_q <= cnt_q + 16'd1;
        end
      end

      if (req_valid && req_ready) begin
        if (req_write) begin
          case (req_addr[7:0])
            8'h00: begin
              tx_q <= req_wdata[7:0];
              if (ctrl_q[0] && !busy_q) begin
                busy_q <= 1'b1;
                done_q <= 1'b0;
                shift_q <= req_wdata[7:0];
                bit_q <= 4'd0;
                cnt_q <= 16'd0;
                sck_q <= 1'b0;
                rx_q <= 8'd0;
              end
            end
            8'h08: ctrl_q <= req_wdata;
            8'h10: div_q <= req_wdata[15:0];
            default: ;
          endcase
        end else if (req_addr[7:0] == 8'h0C) begin
          done_q <= 1'b0;
        end
      end
    end
  end
endmodule
