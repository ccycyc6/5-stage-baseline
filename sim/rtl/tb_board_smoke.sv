`timescale 1ns/1ps
// Behavioural check for rtl/board/board_smoke.v -- run before every board trip.
// Decodes the UART line at 115200 8N1 and compares the full 18-byte message.
module tb_board_smoke;
    reg        clk   = 1'b0;
    reg        rst_n = 1'b0;
    wire       uart_tx;
    wire [7:0] led;

    localparam real BIT = 1.0e9 / 115200.0;   // 8680.56 ns

    always #18.5185 clk = ~clk;               // 27 MHz

    // Short gap so the repeat path is exercised in milliseconds of sim time.
    board_smoke #(.GAP(20000)) dut (
        .clk_27m (clk),
        .rst_n   (rst_n),
        .uart_tx (uart_tx),
        .led     (led)
    );

    reg [7:0] msg [0:17];
    reg [7:0] rx;
    integer   i;
    integer   errors = 0;

    initial begin
        msg[0]  = "A"; msg[1]  = "R"; msg[2]  = "E"; msg[3]  = "S";
        msg[4]  = "-"; msg[5]  = "S"; msg[6]  = "1"; msg[7]  = " ";
        msg[8]  = "s"; msg[9]  = "m"; msg[10] = "o"; msg[11] = "k";
        msg[12] = "e"; msg[13] = " "; msg[14] = "O"; msg[15] = "K";
        msg[16] = 8'h0D; msg[17] = 8'h0A;
    end

    task uart_rx_byte(output [7:0] d);
        integer b;
        begin
            @(negedge uart_tx);          // start bit
            #(BIT * 1.5);                // middle of bit 0
            for (b = 0; b < 8; b = b + 1) begin
                d[b] = uart_tx;
                #(BIT);
            end
            if (uart_tx !== 1'b1) begin  // middle of stop bit
                $display("ERROR: stop bit low");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        #100 rst_n = 1'b1;

        for (i = 0; i < 18; i = i + 1) begin
            uart_rx_byte(rx);
            if (rx !== msg[i]) begin
                $display("ERROR: byte %0d got %02x expected %02x", i, rx, msg[i]);
                errors = errors + 1;
            end
        end

        // POR is 2^16 cycles (~2.4 ms); by now the reset must be released.
        if (led[1] !== 1'b1) begin
            $display("ERROR: led[1] (reset released) is not high");
            errors = errors + 1;
        end

        // Second message: the scheduler must wrap around after the gap.
        for (i = 0; i < 18; i = i + 1) begin
            uart_rx_byte(rx);
            if (rx !== msg[i]) begin
                $display("ERROR: repeat byte %0d got %02x expected %02x", i, rx, msg[i]);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("TB PASS: two full messages decoded at 115200");
        else             $display("TB FAIL: %0d errors", errors);
        $finish;
    end
endmodule
