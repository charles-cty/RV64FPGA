`timescale 1ns / 1ps

module tb_rv64_bram_soc_uart_irq;
  localparam integer BIT_CYCLES = 16;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  logic uart_rx;
  integer failures;

  rv64_bram_soc #(.UART_BIT_CYCLES(BIT_CYCLES)) dut (
    .clk(clk), .reset(reset), .led(led), .uart_tx(uart_tx), .uart_rx(uart_rx),
    .external_ddr3_request_ready(1'b0),
    .external_ddr3_response_read_data(64'b0),
    .external_ddr3_response_error(1'b0)
  );
  always #5 clk = ~clk;

  task automatic send_frame(input logic [7:0] value);
    integer bit_number;
    begin
      uart_rx = 1'b0;
      repeat (BIT_CYCLES) @(posedge clk);
      for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
        uart_rx = value[bit_number];
        repeat (BIT_CYCLES) @(posedge clk);
      end
      uart_rx = 1'b1;
      repeat (BIT_CYCLES * 2) @(posedge clk);
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    uart_rx = 1'b1;
    failures = 0;
    @(posedge clk);
    #1;
    reset = 1'b0;
    dut.uart.interrupt_enable = 8'h01;
    dut.plic.priorities[1] = 3'd3;
    dut.plic.enable = 32'h0000_0002;
    dut.plic.threshold = 3'd0;

    send_frame(8'h5A);
    if (dut.uart.rx_data_register !== 8'h5A || !dut.uart.interrupt) begin
      $display("FAIL SoC UART RX interrupt source: data=%h irq=%b",
               dut.uart.rx_data_register, dut.uart.interrupt);
      failures = failures + 1;
    end
    if (dut.plic_sources[1] !== 1'b1 || dut.plic.pending[1] !== 1'b1 ||
        !dut.plic.external_interrupt || dut.plic.claim_id !== 6'd1) begin
      $display("FAIL SoC UART to PLIC route: source=%b pending=%b irq=%b claim=%0d",
               dut.plic_sources[1], dut.plic.pending[1],
               dut.plic.external_interrupt, dut.plic.claim_id);
      failures = failures + 1;
    end

    if (failures != 0) begin
      $fatal(1, "SIM FAIL: %0d SoC UART IRQ checks failed", failures);
    end
    $display("SIM PASS: rv64_bram_soc UART RX to PLIC regression");
    $finish;
  end
endmodule
