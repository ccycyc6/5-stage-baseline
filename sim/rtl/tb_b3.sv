`timescale 1ns/1ps
// B3 check: the real SoC + BRAM memory model + B3 firmware must print
// "BRAM PASS mcycle=XXXXXXXX" and never take the failure path.
module tb_b3;
    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    wire uart_tx;
    wire [7:0] led;

    localparam real BIT = 1.0e9 / 115200.0;
    always #18.5185 clk = ~clk;

    board_cpu dut (
        .clk_27m (clk),
        .rst_n   (rst_n),
        .uart_tx (uart_tx),
        .led     (led)
    );

    reg [7:0] rx;
    integer   i;
    integer   nerr = 0;
    reg [7:0] want [0:8];
    reg       commit_seen = 1'b0;

    always @(posedge clk) begin
        if (led[2]) commit_seen <= 1'b1;
    end

    initial begin
        want[0]="B"; want[1]="R"; want[2]="A"; want[3]="M"; want[4]=" ";
        want[5]="P"; want[6]="A"; want[7]="S"; want[8]="S";
    end

    task uart_rx_byte(output [7:0] d);
        integer b;
        begin
            @(negedge uart_tx);
            #(BIT * 1.5);
            for (b = 0; b < 8; b = b + 1) begin
                d[b] = uart_tx;
                #(BIT);
            end
        end
    endtask

    initial begin
        #100;
        rst_n = 1'b1;
        for (i = 0; i < 9; i = i + 1) begin
            uart_rx_byte(rx);
            if (rx !== want[i]) begin
                $display("ERROR: byte %0d got %02x want %02x", i, rx, want[i]);
                nerr = nerr + 1;
            end
        end
        uart_rx_byte(rx);
        if (rx !== " ") begin nerr = nerr + 1; $display("ERROR: no space after PASS"); end
        // consume "mcycle="
        for (i = 0; i < 7; i = i + 1) begin
            uart_rx_byte(rx);
        end
        for (i = 0; i < 8; i = i + 1) begin
            uart_rx_byte(rx);
            if (!((rx >= "0" && rx <= "9") || (rx >= "a" && rx <= "f"))) begin
                $display("ERROR: mcycle digit %0d not hex: %02x", i, rx);
                nerr = nerr + 1;
            end
        end
        uart_rx_byte(rx); if (rx !== 8'h0D) nerr = nerr + 1;
        uart_rx_byte(rx); if (rx !== 8'h0A) nerr = nerr + 1;

        if (commit_seen !== 1'b1) begin
            $display("ERROR: dbg_commit never pulsed");
            nerr = nerr + 1;
        end

        if (nerr == 0) $display("TB PASS: BRAM read-back verified by the CPU");
        else           $display("TB FAIL: %0d errors", nerr);
        $finish;
    end
endmodule
