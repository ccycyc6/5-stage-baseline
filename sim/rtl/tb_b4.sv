`timescale 1ns/1ps
// B4 check: drive the UART receive pin with a real image and verify that
// (a) the loader accepts it and (b) the loaded firmware actually runs.
// The image is read with $readmemh; pass its length as +LEN=<bytes>.
module tb_b4;
    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    reg  uart_rx = 1'b1;
    wire uart_tx;
    wire [7:0] led;

    localparam real BIT = 1.0e9 / 115200.0;
    always #18.5185 clk = ~clk;

    board_cpu dut (
        .clk_27m (clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx),
        .led     (led)
    );

    reg [7:0] img [0:131071];
    reg [7:0] rx;
    integer   len;
    integer   i;
    integer   sum;
    integer   nbyte;
    reg [127:0] win;
    reg       found = 1'b0;

    // 16-byte sliding window compared against "B4: hello from l"
    localparam [127:0] MARK = {"B","4",":"," ","h","e","l","l","o"," ","f","r","o","m"," ","l"};

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

    task uart_tx_byte(input [7:0] d);
        integer b;
        begin
            uart_rx = 1'b0;
            #(BIT);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rx = d[b];
                #(BIT);
            end
            uart_rx = 1'b1;
            #(BIT);
        end
    endtask

    task send_frame;
        integer k;
        begin
            uart_tx_byte("A"); uart_tx_byte("R");
            uart_tx_byte("S"); uart_tx_byte("1");
            uart_tx_byte(len[7:0]);   uart_tx_byte(len[15:8]);
            uart_tx_byte(len[23:16]); uart_tx_byte(len[31:24]);
            sum = 0;
            for (k = 0; k < len; k = k + 1) begin
                uart_tx_byte(img[k]);
                sum = (sum + img[k]) & 32'hFFFFFFFF;
            end
            uart_tx_byte(sum[7:0]);   uart_tx_byte(sum[15:8]);
            uart_tx_byte(sum[23:16]); uart_tx_byte(sum[31:24]);
        end
    endtask

    initial begin
        if (!$value$plusargs("LEN=%d", len)) begin
            $display("ERROR: +LEN=<bytes> is required");
            $finish;
        end
        $readmemh("build/fw/b4_hello.hex", img);
    end

    initial begin
        win = 128'd0;
        #100;
        rst_n = 1'b1;

        // 1. consume the loader banner (30 chars + CR LF)
        for (i = 0; i < 32; i = i + 1) begin
            uart_rx_byte(rx);
            $write("%02x ", rx);
        end
        $write("\n");
        $display("loader banner seen, sending %0d bytes", len);

        // 2. image
        send_frame;

        // 3. look for the application banner in the following stream
        for (nbyte = 0; nbyte < 400; nbyte = nbyte + 1) begin
            uart_rx_byte(rx);
            if (nbyte < 80) $write("%02x ", rx);
            win = {win[119:0], rx};
            if (win == MARK) begin
                found = 1'b1;
                nbyte = 400;
            end
        end

        if (found) $display("TB PASS: loader accepted the image and the new firmware ran");
        else       $display("TB FAIL: application banner never appeared");
        $finish;
    end
endmodule
