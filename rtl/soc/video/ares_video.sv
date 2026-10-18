`timescale 1ns/1ps
// Compact video subsystem: 640x480@60 timing, test pattern, 8-box OSD and
// TMDS encoding.  The capture/scaler path is register-reserved for the board
// OV5640/HDMI-IN integration.
module ares_video (
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

  output logic        vsync_irq,
  output logic        pixel_clk_en,
  output logic        hsync,
  output logic        vsync,
  output logic        de,
  output logic [9:0]  tmds_r,
  output logic [9:0]  tmds_g,
  output logic [9:0]  tmds_b,
  output logic [9:0]  dbg_hcnt,
  output logic [9:0]  dbg_vcnt,
  output logic [3:0]  dbg_div
);
  // 640x480@60, 25 MHz pixel clock (100 MHz / 4).
  localparam int H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_BP = 48;
  localparam int V_ACTIVE = 480, V_FP = 10, V_SYNC = 2, V_BP = 33;
  localparam int H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
  localparam int V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

  logic [31:0] ctrl_q, fbase_q, frame_count_q;
  logic [31:0] box_q [0:7][0:3];
  logic [3:0] div_q;
  logic [9:0] hcnt_q, vcnt_q;

  assign req_ready = 1'b1;
  assign rsp_valid = req_valid;
  assign vsync_irq = (vcnt_q == 10'd0) && (hcnt_q == 10'd0) && de == 1'b0;

  always_comb begin
    rsp_rdata = 32'd0;
    if (req_addr < 32'h0000_0010) begin
      case (req_addr[7:0])
        8'h00: rsp_rdata = ctrl_q;
        8'h04: rsp_rdata = fbase_q;
        8'h08: rsp_rdata = {28'd0, vsync, hsync, de, vsync_irq};
        8'h0C: rsp_rdata = frame_count_q;
        default: rsp_rdata = 32'd0;
      endcase
    end else if (req_addr < 32'h0000_0090) begin
      for (int unsigned b = 0; b < 8; b++) begin
        for (int unsigned f = 0; f < 4; f++) begin
          if (req_addr == 32'(32'h10 + b * 16 + f * 4))
            rsp_rdata = box_q[b][f];
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      ctrl_q <= 32'd0;
      fbase_q <= 32'd0;
      frame_count_q <= 32'd0;
      div_q <= 4'd0;
      hcnt_q <= 10'd0;
      vcnt_q <= 10'd0;
      for (int unsigned b = 0; b < 8; b++)
        for (int unsigned f = 0; f < 4; f++) box_q[b][f] <= 32'd0;
    end else begin
      // Pixel clock enable.
      if (div_q == 4'd3) div_q <= 4'd0;
      else div_q <= div_q + 4'd1;

      if (div_q == 4'd3) begin
        if (hcnt_q == H_TOTAL - 1) begin
          hcnt_q <= 10'd0;
          if (vcnt_q == V_TOTAL - 1) begin
            vcnt_q <= 10'd0;
            frame_count_q <= frame_count_q + 32'd1;
          end else begin
            vcnt_q <= vcnt_q + 10'd1;
          end
        end else begin
          hcnt_q <= hcnt_q + 10'd1;
        end
      end

      if (req_valid && req_ready && req_write) begin
        if (req_addr < 32'h0000_0010) begin
          case (req_addr[7:0])
            8'h00: ctrl_q <= req_wdata;
            8'h04: fbase_q <= req_wdata;
            8'h0C: frame_count_q <= req_wdata;
            default: ;
          endcase
        end else if (req_addr < 32'h0000_0090) begin
          for (int unsigned b = 0; b < 8; b++) begin
            for (int unsigned f = 0; f < 4; f++) begin
              if (req_addr == 32'(32'h10 + b * 16 + f * 4))
                box_q[b][f] <= req_wdata;
            end
          end
        end
      end
    end
  end

  assign pixel_clk_en = (div_q == 4'd3);
  assign dbg_hcnt = hcnt_q;
  assign dbg_vcnt = vcnt_q;
  assign dbg_div = div_q;
  assign hsync = ~((hcnt_q >= H_ACTIVE + H_FP) && (hcnt_q < H_ACTIVE + H_FP + H_SYNC));
  assign vsync = ~((vcnt_q >= V_ACTIVE + V_FP) && (vcnt_q < V_ACTIVE + V_FP + V_SYNC));
  assign de = (hcnt_q < H_ACTIVE) && (vcnt_q < V_ACTIVE);

  // 8x8 colour bars, plus a moving marker and OSD boxes.
  logic [7:0] r, g, b;
  always_comb begin
    r = 8'd0; g = 8'd0; b = 8'd0;
    if (ctrl_q[1]) begin
      case (hcnt_q[9:7])
        3'd0: begin r = 8'hFF; g = 8'hFF; b = 8'hFF; end
        3'd1: begin r = 8'hFF; g = 8'hFF; b = 8'h00; end
        3'd2: begin r = 8'h00; g = 8'hFF; b = 8'hFF; end
        3'd3: begin r = 8'h00; g = 8'hFF; b = 8'h00; end
        3'd4: begin r = 8'hFF; g = 8'h00; b = 8'hFF; end
        3'd5: begin r = 8'hFF; g = 8'h00; b = 8'h00; end
        3'd6: begin r = 8'h00; g = 8'h00; b = 8'hFF; end
        default: begin r = 8'h00; g = 8'h00; b = 8'h00; end
      endcase
      if ((hcnt_q >= 300) && (hcnt_q < 340) && (vcnt_q >= 220) && (vcnt_q < 260)) begin
        r = 8'hFF; g = 8'hFF; b = 8'hFF;
      end
    end

    if (ctrl_q[2]) begin
      for (int unsigned i = 0; i < 8; i++) begin
        if (box_q[i][3][0] &&
            (hcnt_q >= box_q[i][0][15:0]) && (hcnt_q <= box_q[i][1][15:0]) &&
            (vcnt_q >= box_q[i][0][31:16]) && (vcnt_q <= box_q[i][1][31:16]) &&
            ((hcnt_q <= box_q[i][0][15:0] + 2) || (hcnt_q + 2 >= box_q[i][1][15:0]) ||
             (vcnt_q <= box_q[i][0][31:16] + 2) || (vcnt_q + 2 >= box_q[i][1][31:16]))) begin
          r = box_q[i][2][7:0];
          g = box_q[i][2][15:8];
          b = box_q[i][2][23:16];
        end
      end
    end
  end

  tmds_encoder u_tr (.clk, .rst, .din(r), .cin(2'b00), .de(de), .dout(tmds_r));
  tmds_encoder u_tg (.clk, .rst, .din(g), .cin(2'b00), .de(de), .dout(tmds_g));
  tmds_encoder u_tb (.clk, .rst, .din(b), .cin(2'b00), .de(de), .dout(tmds_b));
endmodule

// HDMI TMDS 8b/10b encoder.
module tmds_encoder (
  input  logic        clk,
  input  logic        rst,
  input  logic [7:0]  din,
  input  logic [1:0]  cin,
  input  logic        de,
  output logic [9:0]  dout
);
  logic [3:0] n1d;
  logic [8:0] q_m;
  logic [4:0] q_m_ones;
  logic [9:0] q_out_q;
  logic signed [4:0] balance_q;

  always_comb begin
    n1d = 4'(din[0] + din[1] + din[2] + din[3] +
              din[4] + din[5] + din[6] + din[7]);
    q_m[0] = din[0];
    if (n1d > 4'd4) begin
      q_m[1] = ~din[1]; q_m[2] = ~din[2]; q_m[3] = ~din[3];
      q_m[4] = ~din[4]; q_m[5] = ~din[5]; q_m[6] = ~din[6];
      q_m[7] = ~din[7]; q_m[8] = 1'b0;
    end else if (n1d < 4'd4) begin
      q_m[1] = din[1]; q_m[2] = din[2]; q_m[3] = din[3];
      q_m[4] = din[4]; q_m[5] = din[5]; q_m[6] = din[6];
      q_m[7] = din[7]; q_m[8] = 1'b1;
    end else begin
      q_m[1] = din[1]; q_m[2] = din[2]; q_m[3] = din[3];
      q_m[4] = din[4]; q_m[5] = din[5]; q_m[6] = din[6];
      q_m[7] = din[7]; q_m[8] = din[0];
    end
    q_m_ones = 5'(q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] +
                   q_m[5] + q_m[6] + q_m[7] + q_m[8]);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      q_out_q <= 10'd0;
      balance_q <= 4'd0;
    end else if (!de) begin
      case (cin)
        2'b00: q_out_q <= 10'b1101010100;
        2'b01: q_out_q <= 10'b0010101011;
        2'b10: q_out_q <= 10'b0101010100;
        default: q_out_q <= 10'b1010101011;
      endcase
      balance_q <= 4'd0;
    end else begin
      if ((balance_q == 4'd0) || (q_m_ones == 5'd5)) begin
        q_out_q[9] <= ~q_m[8];
        q_out_q[8] <= q_m[8];
        for (int i = 0; i < 8; i++) q_out_q[i] <= (q_m[8] ? q_m[i] : ~q_m[i]);
        if (q_m[8]) balance_q <= balance_q + 5'(q_m_ones - 5'd5);
        else        balance_q <= balance_q - 5'(5'd5 - q_m_ones);
      end else begin
        if (((balance_q > 0) && (q_m_ones > 5)) ||
            ((balance_q < 0) && (q_m_ones < 5))) begin
          q_out_q[9] <= 1'b1;
          q_out_q[8] <= 1'b0;
          for (int i = 0; i < 8; i++) q_out_q[i] <= ~q_m[i];
          balance_q <= balance_q + 5'(q_m_ones - 5'd5);
        end else begin
          q_out_q[9] <= 1'b0;
          q_out_q[8] <= 1'b1;
          for (int i = 0; i < 8; i++) q_out_q[i] <= q_m[i];
          balance_q <= balance_q - 5'(5'd5 - q_m_ones);
        end
      end
    end
  end
  assign dout = q_out_q;
endmodule