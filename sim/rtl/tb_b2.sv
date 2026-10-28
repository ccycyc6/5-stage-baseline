`timescale 1ns/1ps
// End-to-end check of B2: real SoC RTL + generated boot ROM + real firmware,
// decoded straight off the UART pin.  Run before every board trip.
module tb_b2;
    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    wire uart_tx;
    wire [7:0] led;

    localparam real BIT = 1.0e9 / 115200.0;

    always #18.5185 clk = ~clk;          // 27 MHz

    board_b2 dut (
        .clk_27m (clk),
        .rst_n   (rst_n),
        .uart_tx (uart_tx),
        .led     (led)
    );

    reg [7:0] rx;
    integer   i;
    integer   nerr = 0;
    reg       commit_seen = 1'b0;
    reg [7:0] want [0:12];

    // dbg_commit is a one-cycle pulse, so latch it instead of sampling it.
    always @(posedge clk) begin
        if (led[2]) commit_seen <= 1'b1;
    end

    initial begin
        want[0] = "B"; want[1] = "2";  want[2] = " ";
        want[3] = "O"; want[4] = "K";  want[5] = " ";
        want[6] = "m"; want[7] = "c";  want[8] = "y";
        want[9] = "c"; want[10] = "l"; want[11] = "e";
        want[12] = "=";
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

    task check_hex_digit(input [7:0] d, input integer idx);
        begin
            if (!((d >= "0" && d <= "9") || (d >= "a" && d <= "f"))) begin
                $display("ERROR: mcycle digit %0d is not hex: %02x", idx, d);
                nerr = nerr + 1;
            end
        end
    endtask

    initial begin
        #100;
        rst_n = 1'b1;
        for (i = 0; i < 13; i = i + 1) begin
            uart_rx_byte(rx);
            if (rx !== want[i]) begin
                $display("ERROR: byte %0d got %02x expected %02x", i, rx, want[i]);
                nerr = nerr + 1;
            end
        end
        for (i = 0; i < 8; i = i + 1) begin
            uart_rx_byte(rx);
            check_hex_digit(rx, i);
        end
        uart_rx_byte(rx);
        if (rx !== 8'h0D) begin nerr = nerr + 1; $display("ERROR: no CR"); end
        uart_rx_byte(rx);
        if (rx !== 8'h0A) begin nerr = nerr + 1; $display("ERROR: no LF"); end

        if (led[1] !== 1'b1) begin
            $display("ERROR: led[1] reset released is not high");
            nerr = nerr + 1;
        end
        if (commit_seen !== 1'b1) begin
            $display("ERROR: dbg_commit never pulsed - core not retiring");
            nerr = nerr + 1;
        end

        if (nerr == 0) $display("TB PASS: B2 banner decoded from the generated ROM");
        else           $display("TB FAIL: %0d errors", nerr);
        $finish;
    end
endmodule

