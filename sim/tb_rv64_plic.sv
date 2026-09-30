`timescale 1ns / 1ps

module tb_rv64_plic;
  logic clk;
  logic reset;
  logic [31:0] interrupt_sources;
  logic request;
  logic write;
  logic [21:0] address;
  logic [63:0] write_data;
  logic [63:0] read_data;
  logic ready;
  logic external_interrupt;
  integer failures;

  rv64_plic dut (.*);
  always #5 clk = ~clk;

  task automatic write_register(input logic [21:0] target, input logic [63:0] value);
    begin
      address = target;
      write_data = value;
      request = 1'b1;
      write = 1'b1;
      @(posedge clk);
      #1;
      request = 1'b0;
      write = 1'b0;
    end
  endtask

  task automatic claim(input logic [5:0] expected, input logic supervisor_context);
    begin
      address = supervisor_context ? 22'h201004 : 22'h200004;
      request = 1'b1;
      write = 1'b0;
      #1;
      if (!ready || read_data[5:0] !== expected) begin
        $display("FAIL claim: ready=%b got=%0d expected=%0d", ready, read_data[5:0], expected);
        failures = failures + 1;
      end
      @(posedge clk);
      #1;
      request = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    interrupt_sources = '0;
    request = 1'b0;
    write = 1'b0;
    address = '0;
    write_data = '0;
    failures = 0;
    @(posedge clk);
    #1;
    reset = 1'b0;

    write_register(22'h000004, 64'd3);
    write_register(22'h000008, 64'd2);
    write_register(22'h002000, 64'h6);
    interrupt_sources[1] = 1'b1;
    interrupt_sources[2] = 1'b1;
    @(posedge clk);
    #1;
    if (external_interrupt !== 1'b1) begin
      $display("FAIL external interrupt did not assert");
      failures = failures + 1;
    end
    interrupt_sources = '0;
    claim(6'd1, 1'b0);
    @(posedge clk);
    #1;
    claim(6'd2, 1'b1);
    write_register(22'h201000, 64'd3);
    interrupt_sources[1] = 1'b1;
    @(posedge clk);
    #1;
    if (external_interrupt !== 1'b0) begin
      $display("FAIL threshold did not mask lower priority interrupt");
      failures = failures + 1;
    end

    write_register(22'h200000, 64'd0);
    write_register(22'h000004, 64'd1);
    write_register(22'h000008, 64'd7);
    write_register(22'h002000, 64'h6);
    interrupt_sources[1] = 1'b1;
    interrupt_sources[2] = 1'b1;
    @(posedge clk);
    #1;
    claim(6'd2, 1'b0);
    write_register(22'h000004, 64'd7);
    interrupt_sources = '0;
    interrupt_sources[1] = 1'b1;
    interrupt_sources[2] = 1'b1;
    @(posedge clk);
    #1;
    claim(6'd1, 1'b0);

    if (failures != 0) begin
      $display("SIM FAIL: %0d PLIC checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_plic arbitration regression");
    $finish;
  end
endmodule
