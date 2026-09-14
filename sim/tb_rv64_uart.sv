`timescale 1ns / 1ps

module tb_rv64_uart;
  localparam integer BIT_CYCLES = 2;
  logic clk;
  logic reset;
  logic request;
  logic write;
  logic [11:0] address;
  logic [63:0] write_data;
  logic [63:0] read_data;
  logic ready;
  logic tx;
  integer failures;
  integer bit_number;

  rv64_uart #(.BIT_CYCLES(BIT_CYCLES)) dut (.*);
  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    request = 1'b0;
    write = 1'b0;
    address = '0;
    write_data = '0;
    failures = 0;
    @(posedge clk);
    #1;
    reset = 1'b0;

    address = 12'h005;
    request = 1'b1;
    #1;
    if (!ready || read_data[0] !== 1'b1) begin
      $display("FAIL UART reset ready status: ready=%b data=%h", ready, read_data);
      failures = failures + 1;
    end
    request = 1'b0;

    address = 12'h000;
    write_data = 64'h41;
    request = 1'b1;
    write = 1'b1;
    @(posedge clk);
    #1;
    request = 1'b0;
    write = 1'b0;
    if (tx !== 1'b0) begin
      $display("FAIL UART start bit: tx=%b", tx);
      failures = failures + 1;
    end

    for (bit_number = 0; bit_number < 10; bit_number = bit_number + 1) begin
      repeat (BIT_CYCLES) @(posedge clk);
      #1;
      if (bit_number == 0 && tx !== 1'b1) begin
        $display("FAIL UART data bit %0d: tx=%b expected=1", bit_number, tx);
        failures = failures + 1;
      end
      if (bit_number == 1 && tx !== 1'b0) begin
        $display("FAIL UART data bit %0d: tx=%b expected=0", bit_number, tx);
        failures = failures + 1;
      end
      if (bit_number == 2 && tx !== 1'b0) begin
        $display("FAIL UART data bit %0d: tx=%b expected=0", bit_number, tx);
        failures = failures + 1;
      end
      if (bit_number == 3 && tx !== 1'b0) begin
        $display("FAIL UART data bit %0d: tx=%b expected=0", bit_number, tx);
        failures = failures + 1;
      end
      if (bit_number == 4 && tx !== 1'b0) begin
        $display("FAIL UART data bit %0d: tx=%b expected=0", bit_number, tx);
        failures = failures + 1;
      end
      if (bit_number == 5 && tx !== 1'b0) begin
        $display("FAIL UART data bit %0d: tx=%b expected=0", bit_number, tx);
        failures = failures + 1;
      end
      if (bit_number == 6 && tx !== 1'b1) begin
        $display("FAIL UART data bit %0d: tx=%b expected=1", bit_number, tx);
        failures = failures + 1;
      end
      if (bit_number == 7 && tx !== 1'b0) begin
        $display("FAIL UART data bit %0d: tx=%b expected=0", bit_number, tx);
        failures = failures + 1;
      end
      if (bit_number == 8 && tx !== 1'b1) begin
        $display("FAIL UART stop bit: tx=%b", tx);
        failures = failures + 1;
      end
    end

    if (tx !== 1'b1 || dut.busy !== 1'b0) begin
      $display("FAIL UART idle after frame: tx=%b busy=%b", tx, dut.busy);
      failures = failures + 1;
    end
    if (failures != 0) begin
      $display("SIM FAIL: %0d UART checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_uart 8N1 transmit regression");
    $finish;
  end
endmodule
