`timescale 1ns / 1ps

module tb_rv64_clint;
  logic clk;
  logic reset;
  logic request;
  logic write;
  logic [15:0] address;
  logic [63:0] write_data;
  logic [7:0] write_strobe;
  logic [63:0] read_data;
  logic ready;
  logic timer_interrupt;
  logic software_interrupt;
  integer failures;

  rv64_clint dut (.*);
  always #5 clk = ~clk;

  task automatic write_register(input logic [15:0] target, input logic [63:0] value, input logic [7:0] strobe);
    begin
      address = target;
      write_data = value;
      write_strobe = strobe;
      request = 1'b1;
      write = 1'b1;
      @(posedge clk);
      #1;
      request = 1'b0;
      write = 1'b0;
    end
  endtask

  task automatic expect_read(input logic [511:0] name, input logic [15:0] target, input logic [63:0] expected);
    begin
      address = target;
      request = 1'b1;
      #1;
      if (!ready || read_data !== expected) begin
        $display("FAIL %0s: ready=%b got=%h expected=%h", name, ready, read_data, expected);
        failures = failures + 1;
      end
      request = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    request = 1'b0;
    write = 1'b0;
    address = '0;
    write_data = '0;
    write_strobe = '0;
    failures = 0;
    @(posedge clk);
    #1;
    reset = 1'b0;
    expect_read("msip reset", 16'h0000, 64'd0);
    expect_read("mtimecmp reset", 16'h4000, 64'hffff_ffff_ffff_ffff);
    if (timer_interrupt !== 1'b0 || software_interrupt !== 1'b0) begin
      $display("FAIL reset interrupt outputs: timer=%b software=%b", timer_interrupt, software_interrupt);
      failures = failures + 1;
    end

    write_register(16'h0000, 64'd1, 8'b0000_0001);
    if (software_interrupt !== 1'b1) begin
      $display("FAIL msip interrupt did not assert");
      failures = failures + 1;
    end
    write_register(16'h0000, 64'd0, 8'b0000_0001);
    if (software_interrupt !== 1'b0) begin
      $display("FAIL msip interrupt did not clear");
      failures = failures + 1;
    end

    write_register(16'h4000, 64'd4, 8'b1111_1111);
    repeat (4) @(posedge clk);
    #1;
    if (timer_interrupt !== 1'b1) begin
      $display("FAIL timer interrupt did not assert at mtimecmp");
      failures = failures + 1;
    end
    write_register(16'h4000, 64'hffff_ffff_ffff_ffff, 8'b1111_1111);
    if (timer_interrupt !== 1'b0) begin
      $display("FAIL timer interrupt did not clear");
      failures = failures + 1;
    end

    if (failures != 0) begin
      $display("SIM FAIL: %0d CLINT checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_clint timer/software interrupt regression");
    $finish;
  end
endmodule
