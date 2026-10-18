`timescale 1ns/1ps
module tb_soc;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  logic uart_tx, uart_rx = 1'b1;
  logic [31:0] gpio_in = 32'd0, gpio_out, gpio_dir;
  logic spi_sck, spi_mosi, spi_miso = 1'b0, spi_cs_n;
  logic video_pixel_clk_en, video_hsync, video_vsync, video_de;
  logic [9:0] video_tmds_r, video_tmds_g, video_tmds_b;
  logic [3:0] mt_irq, dbg_halt, dbg_commit;
  logic [3:0][31:0] dbg_pc, dbg_pc_f;
  logic [3:0] dbg_ifid_valid, dbg_idex_valid, dbg_exmem_valid, dbg_memwb_valid, dbg_if_pending;

  ares_p4_soc #(
    .RESET_PC(32'h0000_0000),
    .DDR_FILE("")
  ) u_soc (
    .clk, .rst,
    .uart_rx, .uart_tx,
    .gpio_in, .gpio_out, .gpio_dir,
    .spi_sck, .spi_mosi, .spi_miso, .spi_cs_n,
    .video_pixel_clk_en, .video_hsync, .video_vsync, .video_de,
    .video_tmds_r, .video_tmds_g, .video_tmds_b,
    .mt_irq, .dbg_halt, .dbg_pc, .dbg_commit,
    .dbg_pc_f, .dbg_ifid_valid, .dbg_idex_valid, .dbg_exmem_valid, .dbg_memwb_valid, .dbg_if_pending
  );

  // UART receiver: 8N1, divisor 8 -> 80 ns per bit at 100 MHz.
  string log_line = "";
  int uart_chars = 0;
  int uart_fd;
  initial uart_fd = $fopen("build/uart.log", "w");
  initial begin
    forever begin
      @(negedge uart_tx);
      #120; // 1.5 bit times
      begin
        logic [7:0] ch;
        for (int i = 0; i < 8; i++) begin
          ch[i] = uart_tx;
          #80;
        end
        log_line = {log_line, ch};
        uart_chars++;
        $write("%c", ch);
        $fwrite(uart_fd, "%c", ch);
        $fflush(uart_fd);
        if (uart_chars % 1024 == 0) begin
          $fflush;
        end
      end
    end
  end

  initial begin
    repeat (20) @(negedge clk);
    rst = 0;
    $display("\n[TB] ARES-P4 SoC reset released");
  end

  initial begin
    #200_000_000; // 200 ms simulated
    $display("\n[TB] TIMEOUT: hart0 pc=%08x pf=%08x ifid=%b idex=%b exmem=%b memwb=%b halt=%b",
             dbg_pc[0], dbg_pc_f[0], dbg_ifid_valid[0], dbg_idex_valid[0],
             dbg_exmem_valid[0], dbg_memwb_valid[0], dbg_halt[0]);
    $finish;
  end

  always @(posedge clk) begin
    if (dbg_halt[0]) begin
      repeat (10) @(posedge clk);
      $display("\n[TB] hart0 halted, pc=%08x", dbg_pc[0]);
      $fclose(uart_fd);
      $finish;
    end
  end
endmodule