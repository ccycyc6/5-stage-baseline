`timescale 1ns/1ps
// 32-bit MMIO bus.  All peripherals are one-cycle request/response; the bus
// registers the response so the L2 sees a clean req/ack pair.
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

  output logic [3:0]  timer_irq,
  output logic [3:0]  soft_irq,
  output logic [3:0]  ext_irq,

  output logic        uart_tx,
  input  logic        uart_rx,
  input  logic [31:0] gpio_in,
  output logic [31:0] gpio_out,
  output logic [31:0] gpio_dir,
  output logic        spi_sck,
  output logic        spi_mosi,
  input  logic        spi_miso,
  output logic        spi_cs_n,

  output logic        video_pixel_clk_en,
  output logic        video_hsync,
  output logic        video_vsync,
  output logic        video_de,
  output logic [9:0]  video_tmds_r,
  output logic [9:0]  video_tmds_g,
  output logic [9:0]  video_tmds_b,
  output logic        video_irq,

  input  logic [31:0] irq_src_ext,
  output logic [31:0] irq_src
);
  import ares_pkg::*;

  typedef enum logic [1:0] {M_IDLE, M_RESP} state_t;
  state_t state_q;
  logic [31:0] addr_q, wdata_q;
  logic        write_q;
  logic [3:0]  wstrb_q;
  logic [31:0] rsp_data_q;

  // Peripheral selects.
  wire sel_clint = (req_addr[31:16] == 16'h0001);
  wire sel_plic  = (req_addr[31:16] == 16'h0002);
  wire sel_mbox  = (req_addr[31:16] == 16'h0003);
  wire sel_uart  = (req_addr[31:16] == 16'hD000) && (req_addr[15:12] == 4'h0);
  wire sel_gpio  = (req_addr[31:16] == 16'hD000) && (req_addr[15:12] == 4'h1);
  wire sel_spi   = (req_addr[31:16] == 16'hD000) && (req_addr[15:12] == 4'h2);
  wire sel_i2c   = (req_addr[31:16] == 16'hD000) && (req_addr[15:12] == 4'h3);
  wire sel_sd    = (req_addr[31:16] == 16'hD000) && (req_addr[15:12] == 4'h4);
  wire sel_gbe   = (req_addr[31:16] == 16'hD000) && (req_addr[15:12] == 4'h5);
  wire sel_video = (req_addr[31:16] == 16'hD000) && (req_addr[15:12] == 4'h6);
  wire sel_dma   = (req_addr[31:16] == 16'hD000) && (req_addr[15:12] == 4'h7);
  wire sel_debug = (req_addr[31:16] == 16'hF000);

  assign req_ready = (state_q == M_IDLE);
  assign rsp_valid = (state_q == M_RESP);
  assign rsp_rdata = rsp_data_q;

  // Request strobes to the selected peripheral.
  wire periph_req = (state_q == M_IDLE) && req_valid;

  logic [31:0] clint_rdata, plic_rdata, mbox_rdata, uart_rdata;
  logic [31:0] gpio_rdata, spi_rdata, i2c_rdata, sd_rdata, gbe_rdata;
  logic [31:0] video_rdata, dma_rdata;

  logic [31:0] irq_src_int;
  logic [3:0] mbox_irq_v, barrier_irq_v;
  logic uart_irq_v, gpio_irq_v, spi_irq_v, i2c_irq_v, sd_irq_v, gbe_irq_v;

  logic [31:0] dma_regs [0:7];

  ares_clint u_clint (
    .clk, .rst,
    .req_valid(periph_req && sel_clint), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - CLINT_BASE),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(clint_rdata),
    .soft_irq(soft_irq), .timer_irq(timer_irq)
  );

  ares_plic u_plic (
    .clk, .rst,
    .req_valid(periph_req && sel_plic), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - PLIC_BASE),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(plic_rdata),
    .irq_src(irq_src), .ext_irq(ext_irq)
  );

  ares_mailbox u_mbox (
    .clk, .rst,
    .req_valid(periph_req && sel_mbox), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - MBOX_BASE),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(mbox_rdata),
    .mbox_irq(mbox_irq_v[0]), .barrier_irq(barrier_irq_v[0])
  );

  ares_uart u_uart (
    .clk, .rst,
    .req_valid(periph_req && sel_uart), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - 32'hD000_0000),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(uart_rdata),
    .uart_tx, .uart_rx, .uart_irq(uart_irq_v)
  );

  ares_gpio u_gpio (
    .clk, .rst,
    .req_valid(periph_req && sel_gpio), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - 32'hD000_1000),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(gpio_rdata),
    .gpio_in, .gpio_out, .gpio_dir, .gpio_irq(gpio_irq_v)
  );

  ares_spi u_spi (
    .clk, .rst,
    .req_valid(periph_req && sel_spi), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - 32'hD000_2000),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(spi_rdata),
    .spi_sck, .spi_mosi, .spi_miso, .spi_cs_n, .spi_irq(spi_irq_v)
  );

  ares_periph_stub u_i2c (
    .clk, .rst,
    .req_valid(periph_req && sel_i2c), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - 32'hD000_3000),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(i2c_rdata), .irq(i2c_irq_v)
  );

  ares_periph_stub u_sd (
    .clk, .rst,
    .req_valid(periph_req && sel_sd), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - 32'hD000_4000),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(sd_rdata), .irq(sd_irq_v)
  );

  ares_periph_stub u_gbe (
    .clk, .rst,
    .req_valid(periph_req && sel_gbe), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - 32'hD000_5000),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(gbe_rdata), .irq(gbe_irq_v)
  );

  // Video subsystem: timing, test pattern, OSD and TMDS.
  ares_video u_video (
    .clk, .rst,
    .req_valid(periph_req && sel_video), .req_ready(),
    .req_write(req_write), .req_addr(req_addr - 32'hD000_6000),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(), .rsp_ready(1'b1), .rsp_rdata(video_rdata),
    .vsync_irq(video_irq),
    .pixel_clk_en(video_pixel_clk_en), .hsync(video_hsync), .vsync(video_vsync),
    .de(video_de), .tmds_r(video_tmds_r), .tmds_g(video_tmds_g), .tmds_b(video_tmds_b)
  );

  // DMA registers (stub; the video DMA uses its own datapath).
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int unsigned i = 0; i < 8; i++) dma_regs[i] <= 32'd0;
    end else if (periph_req && sel_dma && req_write) begin
      for (int unsigned i = 0; i < 8; i++) begin
        if (req_addr[7:0] == 8'(i * 4)) dma_regs[i] <= req_wdata;
      end
    end
  end
  always_comb begin
    dma_rdata = 32'd0;
    for (int unsigned i = 0; i < 8; i++) begin
      if (req_addr[7:0] == 8'(i * 4)) dma_rdata = dma_regs[i];
    end
  end

  // Interrupt source map.
  assign irq_src_int[0]  = uart_irq_v;
  assign irq_src_int[1]  = gpio_irq_v;
  assign irq_src_int[2]  = spi_irq_v;
  assign irq_src_int[3]  = i2c_irq_v;
  assign irq_src_int[4]  = sd_irq_v;
  assign irq_src_int[5]  = video_irq;        // video vsync
  assign irq_src_int[6]  = irq_src_ext[6];   // DMA done
  assign irq_src_int[7]  = mbox_irq_v[0];
  assign irq_src_int[8]  = barrier_irq_v[0];
  assign irq_src_int[12:9] = irq_src_ext[12:9]; // MT0-3 done
  assign irq_src_int[13] = gbe_irq_v;
  assign irq_src_int[31:14] = irq_src_ext[31:14];
  assign irq_src = irq_src_int;

  // Response latching.
  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= M_IDLE;
      addr_q <= 32'd0;
      wdata_q <= 32'd0;
      write_q <= 1'b0;
      wstrb_q <= 4'd0;
      rsp_data_q <= 32'd0;
    end else begin
      case (state_q)
        M_IDLE: begin
          if (req_valid && req_ready) begin
            addr_q <= req_addr;
            wdata_q <= req_wdata;
            write_q <= req_write;
            wstrb_q <= req_wstrb;
            state_q <= M_RESP;
            if (sel_clint) rsp_data_q <= clint_rdata;
            else if (sel_plic) rsp_data_q <= plic_rdata;
            else if (sel_mbox) rsp_data_q <= mbox_rdata;
            else if (sel_uart) rsp_data_q <= uart_rdata;
            else if (sel_gpio) rsp_data_q <= gpio_rdata;
            else if (sel_spi) rsp_data_q <= spi_rdata;
            else if (sel_i2c) rsp_data_q <= i2c_rdata;
            else if (sel_sd) rsp_data_q <= sd_rdata;
            else if (sel_gbe) rsp_data_q <= gbe_rdata;
            else if (sel_video) rsp_data_q <= video_rdata;
            else if (sel_dma) rsp_data_q <= dma_rdata;
            else if (sel_debug) rsp_data_q <= 32'h4152_4553; // 'ARES'
            else rsp_data_q <= 32'd0;
          end
        end
        M_RESP: begin
          if (rsp_ready) state_q <= M_IDLE;
        end
        default: state_q <= M_IDLE;
      endcase
    end
  end
endmodule