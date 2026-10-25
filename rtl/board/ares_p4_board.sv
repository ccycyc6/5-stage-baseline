`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// ARES-P4 board top for the Pangu 200Pro+ (PG2L200H-6IFBB676, MES2L676 core
// board + MES2L676-BASE-V1.2 baseboard).
//
// Pin map (see fpga/pango/board_pinmap.md):
//   clk     D18   27 MHz oscillator (U11 on the MES2L676 core board)
//   rst_n   C22   reset push button (active low)
//   uart_tx C24   USB-UART bridge RX
//   uart_rx B24   USB-UART bridge TX
//   led[3:0] E18, C19, C18, A20
//
// The board build instantiates the SoC without the miniTensor CV-X-IF cluster
// (Pango ADS cannot elaborate SV interfaces) and with the on-chip 256 KiB
// memory in place of the DDR3 controller, initialised from the firmware image.
// ---------------------------------------------------------------------------
module ares_p4_board #(
  parameter              DDR_FILE   = "fw.hex",
  parameter logic [31:0] RESET_PC   = 32'h8000_0000
) (
  input  wire       clk,
  input  wire       rst_n,
  input  wire       uart_rx,
  output wire       uart_tx,
  output wire [3:0] led
);

  // ------------------------------------------------------------- clock/reset
  (* ASYNC_REG = "TRUE" *) reg [1:0] rst_sync_q;
  reg [15:0] por_cnt;
  reg        por_done;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rst_sync_q <= 2'b00;
      por_cnt    <= 16'd0;
      por_done   <= 1'b0;
    end else begin
      rst_sync_q <= {rst_sync_q[0], 1'b1};
      if (!por_done) begin
        if (por_cnt == 16'hFFFF) por_done <= 1'b1;
        else                     por_cnt  <= por_cnt + 16'd1;
      end
    end
  end

  wire rst = !(rst_sync_q[1] && por_done);

  // ------------------------------------------------------------------- SoC
  wire        soc_uart_tx;
  wire [31:0] gpio_out, gpio_dir;
  wire [3:0]  mt_irq, dbg_halt, dbg_commit;
  wire [3:0][31:0] dbg_pc;

  ares_p4_soc #(
    .RESET_PC(RESET_PC),
    .DDR_FILE(DDR_FILE),
    .L1_BYTES(4096),          // 4 KiB L1I/L1D: ADS maps the 256-bit cache lines to
                              // LUTRAM, so the on-die budget needs smaller caches
    .CACHE_SETS(512),         // 64 KiB shared L2
    .SCRATCH_WORDS(4096),     // 64 KiB scratchpad
    .ROM_WORDS(512),          // board build boots straight from the on-chip image
    .QSPI_WORDS(1024),
    .ONCHIP_WORDS(8192)       // 128 KiB firmware/data memory (DRM budget)
  ) u_soc (
    .clk(clk),
    .rst(rst),
    .uart_rx(uart_rx),
    .uart_tx(soc_uart_tx),
    .gpio_in({28'd0, 4'b0000}),
    .gpio_out(gpio_out),
    .gpio_dir(gpio_dir),
    .spi_sck(),
    .spi_mosi(),
    .spi_miso(1'b1),
    .spi_cs_n(),
    .video_pixel_clk_en(),
    .video_hsync(),
    .video_vsync(),
    .video_de(),
    .video_tmds_r(),
    .video_tmds_g(),
    .video_tmds_b(),
    .mt_irq(mt_irq),
    .dbg_halt(dbg_halt),
    .dbg_pc(dbg_pc),
    .dbg_commit(dbg_commit),
    .dbg_pc_f(),
    .dbg_ifid_valid(),
    .dbg_idex_valid(),
    .dbg_exmem_valid(),
    .dbg_memwb_valid(),
    .dbg_if_pending()
  );

  assign uart_tx = soc_uart_tx;

  // ------------------------------------------------------------------- LEDs
  // led0: out of reset, led1: hart0 retiring instructions, led2: UART traffic,
  // led3: 1.5 Hz heartbeat off the 50 MHz clock.
  reg [23:0] beat;
  always @(posedge clk) beat <= beat + 24'd1;

  reg uart_act;
  always @(posedge clk) uart_act <= soc_uart_tx;

  assign led[0] = !rst;
  assign led[1] = dbg_commit[0];
  assign led[2] = soc_uart_tx ^ uart_act;
  assign led[3] = beat[23];

endmodule