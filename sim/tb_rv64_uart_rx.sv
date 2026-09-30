`timescale 1ns / 1ps

module tb_rv64_uart_rx;
  localparam integer BIT_CYCLES = 16;
  logic clk;
  logic reset;
  logic request;
  logic write;
  logic [11:0] address;
  logic [63:0] write_data;
  logic [63:0] read_data;
  logic ready;
  logic tx;
  logic rx;
  logic interrupt;
  integer failures;

  rv64_uart #(.BIT_CYCLES(BIT_CYCLES)) dut (.*);
  always #5 clk = ~clk;

  task automatic write_reg(input logic [11:0] register_address,
                           input logic [7:0] value);
    begin
      address = register_address;
      write_data = {56'b0, value};
      request = 1'b1;
      write = 1'b1;
      while (!ready) begin
        @(posedge clk);
        #1;
      end
      @(posedge clk);
      #1;
      request = 1'b0;
      write = 1'b0;
    end
  endtask

  task automatic read_reg(input logic [11:0] register_address,
                          output logic [7:0] value);
    begin
      address = register_address;
      request = 1'b1;
      write = 1'b0;
      #1;
      value = read_data[7:0];
      @(posedge clk);
      #1;
      request = 1'b0;
    end
  endtask

  task automatic send_frame(input logic [7:0] value, input logic stop_bit);
    integer bit_number;
    begin
      rx = 1'b0;
      repeat (BIT_CYCLES) @(posedge clk);
      for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
        rx = value[bit_number];
        repeat (BIT_CYCLES) @(posedge clk);
      end
      rx = stop_bit;
      repeat (BIT_CYCLES) @(posedge clk);
      rx = 1'b1;
      repeat (BIT_CYCLES) @(posedge clk);
    end
  endtask

  task automatic check(input logic condition, input [511:0] message);
    begin
      if (!condition) begin
        $display("FAIL %0s", message);
        failures = failures + 1;
      end
    end
  endtask

  logic [7:0] status;
  logic [7:0] interrupt_id;
  logic [7:0] received;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    request = 1'b0;
    write = 1'b0;
    address = '0;
    write_data = '0;
    rx = 1'b1;
    failures = 0;

    @(posedge clk);
    #1;
    reset = 1'b0;
    write_reg(12'h001, 8'h01);
    send_frame(8'hA5, 1'b1);

    read_reg(12'h005, status);
    check(status[0] && !status[1] && !status[3], "RX data-ready status");
    check(interrupt, "RX interrupt asserted");
    read_reg(12'h002, interrupt_id);
    check(interrupt_id == 8'h04, "RX data interrupt identification");
    read_reg(12'h000, received);
    check(received == 8'hA5, "RX data byte");
    read_reg(12'h005, status);
    check(!status[0] && !interrupt, "RX read clears data-ready and interrupt");

    send_frame(8'h11, 1'b1);
    send_frame(8'h22, 1'b1);
    read_reg(12'h005, status);
    check(status[0] && status[1], "RX overrun status");
    read_reg(12'h000, received);
    check(received == 8'h11, "RX overrun preserves first byte");

    send_frame(8'h33, 1'b0);
    read_reg(12'h005, status);
    check(status[3], "RX framing error status");
    read_reg(12'h000, received);

    if (failures != 0) begin
      $fatal(1, "SIM FAIL: %0d UART RX checks failed", failures);
    end
    $display("SIM PASS: rv64_uart 8N1 receive and interrupt regression");
    $finish;
  end
endmodule
