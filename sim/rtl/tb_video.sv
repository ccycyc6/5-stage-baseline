`timescale 1ns/1ps
module tb_video;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  logic req_valid = 0, req_ready, req_write = 0;
  logic [31:0] req_addr = 0, req_wdata = 0;
  logic [3:0] req_wstrb = 4'hF;
  logic rsp_valid, rsp_ready = 1;
  logic [31:0] rsp_rdata;
  logic vsync_irq, pixel_clk_en, hsync, vsync, de;
  logic [9:0] tmds_r, tmds_g, tmds_b;
  logic [9:0] dbg_hcnt, dbg_vcnt;
  logic [3:0] dbg_div;

  ares_video dut (
    .clk, .rst,
    .req_valid, .req_ready, .req_write, .req_addr, .req_wdata, .req_wstrb,
    .rsp_valid, .rsp_ready, .rsp_rdata,
    .vsync_irq, .pixel_clk_en, .hsync, .vsync, .de,
    .tmds_r, .tmds_g, .tmds_b, .dbg_hcnt, .dbg_vcnt, .dbg_div
  );

  task automatic wr(input logic [31:0] a, input logic [31:0] d);
    begin
      @(negedge clk);
      req_valid = 1; req_write = 1; req_addr = a; req_wdata = d;
      @(negedge clk);
      req_valid = 0;
    end
  endtask

  int de_count = 0, line_count = 0, frame_count = 0;
  logic hsync_d = 1, vsync_d = 1;
  int errors = 0;
  always @(posedge clk) begin
    if (!rst) begin
      if (de) de_count++;
      hsync_d <= hsync;
      vsync_d <= vsync;
      if (hsync && !hsync_d) line_count++;
      if (vsync && !vsync_d) begin
        frame_count++;
        if (frame_count == 1) begin
          if (de_count < 600 * 400) begin
            $display("FAIL: too few active pixels %0d", de_count);
            errors++;
          end
          $display("frame1 active=%0d lines=%0d", de_count, line_count);
        end
      end
      if (de && (^tmds_r === 1'bx)) begin
        $display("FAIL: TMDS X");
        errors++;
      end
    end
  end

  initial begin
    forever #1_000_000 $display("h=%0d v=%0d div=%0d de=%b hs=%b vs=%b", dbg_hcnt, dbg_vcnt, dbg_div, de, hsync, vsync);
  end

  initial begin
    repeat (5) @(negedge clk);
    rst = 0;
    wr(32'hD000_6000, 32'h0000_0007); // enable, test pattern, OSD
    wr(32'hD000_6010, 32'h00F0_0028); // box0 x0=40,y0=240
    wr(32'hD000_6014, 32'h0140_01E0); // box0 x1=480,y1=320
    wr(32'hD000_6018, 32'h0000_FF00); // box0 colour
    wr(32'hD000_601C, 32'h0000_0001); // box0 enable
    #30_000_000;
    if (errors == 0) $display("*** VIDEO TEST PASS ***");
    else             $display("*** VIDEO TEST FAILED %0d ***", errors);
    $finish;
  end
endmodule