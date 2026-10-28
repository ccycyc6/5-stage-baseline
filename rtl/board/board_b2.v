// ---------------------------------------------------------------------------
// board_b2 - bring-up stage B2: the ARES-L core executes from an on-chip ROM.
//
// What it proves:
//   B1 already proved clock/reset/UART/pins.  B2 adds exactly ONE variable:
//   the CPU.  There is no BRAM, no DDR, no stack and no loader: the program
//   lives in a generated combinational ROM at 0x0000_0000 (the reset vector)
//   and only writes the UART.
//
// Observability while the CPU is suspect:
//   led[0]  free-running clock bit (no reset)
//   led[1]  reset released
//   led[2]  dbg_commit   -> the core is retiring instructions
//   led[3]  dbg_halt     -> the core took a fatal trap
//   led[7:4] dbg_pc[7:4] -> the PC is moving
//
//   "led[1] on, led[0] blinking, led[2] dark" means the clock is alive but the
//   core never retires: the failure is the core/ROM, not the board.
//
// Verilog-2001 on purpose; the SoC itself is SystemVerilog and goes through
// tools/pango_prep.py.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
module board_b2 (
    input  wire       clk_27m,      // D18
    input  wire       rst_n,        // C22
    output wire       uart_tx,      // C24
    output wire [7:0] led
);

    // ------------------------------------------------------- clock liveness
    reg [25:0] free_cnt;
    always @(posedge clk_27m) begin
        free_cnt <= free_cnt + 26'd1;
    end

    // ---------------------------------------------------------------- reset
    reg [1:0]  rst_sync;
    reg [15:0] por_cnt;
    reg        por_done;

    always @(posedge clk_27m or negedge rst_n) begin
        if (!rst_n) begin
            rst_sync <= 2'b00;
            por_cnt  <= 16'd0;
            por_done <= 1'b0;
        end else begin
            rst_sync <= {rst_sync[0], 1'b1};
            if (!por_done) begin
                if (por_cnt == 16'hFFFF) por_done <= 1'b1;
                else                     por_cnt  <= por_cnt + 16'd1;
            end
        end
    end

    wire rst = ~(rst_sync[1] & por_done);

    // ------------------------------------------------------------------ SoC
    wire        soc_uart_tx;
    wire [31:0] dbg_pc;
    wire        dbg_commit;
    wire        dbg_halt;

    ares_soc #(
        .RESET_PC      (32'h0000_0000),
        .L1_BYTES      (2048),
        .SCRATCH_WORDS (16),
        .ROM_WORDS     (4096)
    ) u_soc (
        .clk             (clk_27m),
        .rst             (rst),
        .uart_rx         (1'b1),
        .uart_tx         (soc_uart_tx),
        .gpio_in         (32'd0),
        .gpio_out        (),
        .gpio_dir        (),
        .mt_irq          (),
        .dbg_halt        (dbg_halt),
        .dbg_pc          (dbg_pc),
        .dbg_commit      (dbg_commit),
        .dbg_pc_f        (),
        .dbg_ifid_valid  (),
        .dbg_idex_valid  (),
        .dbg_exmem_valid (),
        .dbg_memwb_valid (),
        .dbg_if_pending  ()
    );

    assign uart_tx = soc_uart_tx;

    assign led[0]   = free_cnt[24];
    assign led[1]   = ~rst;
    assign led[2]   = dbg_commit;
    assign led[3]   = dbg_halt;
    assign led[7:4] = dbg_pc[7:4];

endmodule
