`timescale 1ns / 1ps

module tb_rv64_bram_soc;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;

  rv64_bram_soc dut (
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
    dut.instruction_memory[0] = 32'h0050_0093; // addi x1, x0, 5
    dut.instruction_memory[1] = 32'h1000_1137; // lui x2, 0x10001
    dut.instruction_memory[2] = 32'h0011_2023; // sw x1, 0(x2)
    dut.instruction_memory[3] = 32'h0000_006f; // jal x0, 0
    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (8) @(posedge clk);
    #1;

    if (led !== 3'b101) begin
      $display("FAIL LED store: got=%b expected=101", led);
      failures = failures + 1;
    end
    if (dut.core.register_file.registers[1] !== 64'd5) begin
      $display("FAIL x1: got=%h expected=5", dut.core.register_file.registers[1]);
      failures = failures + 1;
    end
    if (dut.core.register_file.registers[2] !== 64'h0000_0000_1000_1000) begin
      $display("FAIL x2 LED address: got=%h", dut.core.register_file.registers[2]);
      failures = failures + 1;
    end

    if (failures != 0) begin
      $display("SIM FAIL: %0d BRAM SoC checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_bram_soc LED memory-map regression");
    $finish;
  end
endmodule
