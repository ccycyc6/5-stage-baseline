`timescale 1ns/1ps
// 32-bit MMIO bus for the simulation SoC: CLINT, UART and GPIO.
// Every peripheral completes in one request/response pair.
module ares_mmio_bus (
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

  output logic        timer_irq,
  output logic        soft_irq,

  output logic        uart_tx,
  input  logic        uart_rx,
  input  logic [31:0] gpio_in,
  output logic [31:0] gpio_out,
  output logic [31:0] gpio_dir
);
  import ares_pkg::*;

  typedef enum logic [1:0] {M_IDLE, M_RESP} state_t;
  state_t state_q;
  logic [31:0] rsp_data_q;

  wire sel_clint = (req_addr[31:16] == 16'h0001);
  wire sel_uart  = (req_addr[31:16] == 16'hD000) && (req_addr[15:12] == 4'h0);
  wire sel_gpio  = (req_addr[31:16] == 16'hD000) && (req_addr[15:12] == 4'h1);
  wire periph_req = (state_q == M_IDLE) && req_valid;

  assign req_ready = (state_q == M_IDLE);
  assign rsp_valid = (state_q == M_RESP);
  assign rsp_rdata = rsp_data_q;

  logic [31:0] clint_rdata, uart_rdata, gpio_rdata;
  logic [0:0] clint_soft, clint_timer;

  ares_clint #(.HART_COUNT(1)) u_clint (
    .clk, .rst,
    .req_valid(periph_req && sel_clint), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - CLINT_BASE),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(clint_rdata),
    .soft_irq(clint_soft), .timer_irq(clint_timer)
  );

  ares_uart u_uart (
    .clk, .rst,
    .req_valid(periph_req && sel_uart), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - MMIO_BASE),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(uart_rdata),
    .uart_tx, .uart_rx, .uart_irq()
  );

  ares_gpio u_gpio (
    .clk, .rst,
    .req_valid(periph_req && sel_gpio), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - 32'hD000_1000),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(gpio_rdata),
    .gpio_in, .gpio_out, .gpio_dir, .gpio_irq()
  );

  assign timer_irq = clint_timer[0];
  assign soft_irq  = clint_soft[0];

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= M_IDLE;
      rsp_data_q <= 32'd0;
    end else begin
      case (state_q)
        M_IDLE: begin
          if (req_valid && req_ready) begin
            if (sel_clint) rsp_data_q <= clint_rdata;
            else if (sel_uart) rsp_data_q <= uart_rdata;
            else if (sel_gpio) rsp_data_q <= gpio_rdata;
            else rsp_data_q <= 32'd0;
            state_q <= M_RESP;
          end
        end
        M_RESP: if (rsp_ready) state_q <= M_IDLE;
        default: state_q <= M_IDLE;
      endcase
    end
  end
endmodule
