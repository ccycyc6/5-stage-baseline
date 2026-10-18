`timescale 1ns/1ps

module tb_tensor_epilogue;
  logic [511:0] c_data, bias_data;
  logic [127:0] config_data, output_data;
  tensor_epilogue_core dut (.c_data, .bias_data, .config_data, .output_data);

  initial begin
    c_data = '0;
    bias_data = '0;
    // Lanes: -200, -2, 0, 10, 100, 200, then zeros.
    c_data[31:0] = -200;
    c_data[63:32] = -2;
    c_data[95:64] = 0;
    c_data[127:96] = 10;
    c_data[159:128] = 100;
    c_data[191:160] = 200;
    // multiplier=1, shift=0, zero_point=0, ReLU disabled.
    config_data = '0;
    config_data[15:0] = 16'd1;
    #1;
    if ($signed(output_data[7:0]) !== -128 ||
        $signed(output_data[15:8]) !== -2 ||
        $signed(output_data[31:24]) !== 10 ||
        $signed(output_data[39:32]) !== 100 ||
        $signed(output_data[47:40]) !== 127)
      $fatal(1, "epilogue saturation mismatch: %h", output_data);

    // Add bias, apply right shift and ReLU.
    bias_data[31:0] = 8;
    bias_data[63:32] = -8;
    config_data[15:0] = 16'd2;
    config_data[20:16] = 1;
    config_data[29] = 1'b1;
    #1;
    if (output_data[7:0] !== 8'd0 || output_data[15:8] !== 8'd0 ||
        output_data[23:16] !== 8'd0 || output_data[31:24] !== 8'd10)
      $fatal(1, "epilogue requant/ReLU mismatch: %h", output_data);
    $display("PASS: epilogue bias, requantization, saturation and ReLU completed");
    $finish;
  end
endmodule
