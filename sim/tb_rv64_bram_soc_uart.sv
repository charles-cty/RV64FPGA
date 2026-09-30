`timescale 1ns / 1ps

module tb_rv64_bram_soc_uart;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;

  rv64_bram_soc #(.UART_BIT_CYCLES(2)) dut (
    .clk(clk), .reset(reset), .led(led), .uart_tx(uart_tx), .uart_rx(1'b1),
    .external_ddr3_request_ready(1'b0),
    .external_ddr3_response_read_data(64'b0),
    .external_ddr3_response_error(1'b0)
  );
  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    #1;
    dut.instruction_memory[0] = 32'h0410_0093; // addi x1, x0, 0x41
    dut.instruction_memory[1] = 32'h1000_0137; // lui x2, 0x10000
    dut.instruction_memory[2] = 32'h0011_2023; // sw x1, 0(x2)
    dut.instruction_memory[3] = 32'h0000_006f; // jal x0, 0
    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (4) @(posedge clk);
    #1;
    if (uart_tx !== 1'b0) begin
      $display("FAIL UART MMIO start bit: tx=%b", uart_tx);
      failures = failures + 1;
    end
    repeat (20) @(posedge clk);
    #1;
    if (uart_tx !== 1'b1 || dut.uart.busy !== 1'b0) begin
      $display("FAIL UART MMIO frame completion: tx=%b busy=%b", uart_tx, dut.uart.busy);
      failures = failures + 1;
    end
    if (led !== 3'b000) begin
      $display("FAIL UART write changed LED unexpectedly: led=%b", led);
      failures = failures + 1;
    end

    if (failures != 0) begin
      $display("SIM FAIL: %0d SoC UART checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_bram_soc UART memory-map regression");
    $finish;
  end
endmodule
