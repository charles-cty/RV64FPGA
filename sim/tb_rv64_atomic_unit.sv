`timescale 1ns / 1ps

module tb_rv64_atomic_unit;
  import riscv_pkg::*;

  logic clk;
  logic reset;
  logic execute;
  atomic_op_t operation;
  logic word_operation;
  logic [63:0] address;
  logic [63:0] source_data;
  logic [63:0] memory_read_data;
  logic memory_ready;
  logic memory_valid;
  logic memory_write;
  logic [63:0] memory_write_data;
  logic [63:0] result;
  logic sc_success;
  integer failures;

  rv64_atomic_unit dut (.*);
  always #5 clk = ~clk;

  task automatic expect_atomic(
    input logic [511:0] name,
    input atomic_op_t expected_operation,
    input logic expected_word,
    input logic [63:0] expected_address,
    input logic [63:0] expected_source,
    input logic [63:0] expected_memory,
    input logic expected_write,
    input logic [63:0] expected_write_data,
    input logic [63:0] expected_result
  );
    begin
      operation = expected_operation;
      word_operation = expected_word;
      address = expected_address;
      source_data = expected_source;
      memory_read_data = expected_memory;
      execute = 1'b1;
      #1;
      if ((memory_valid !== 1'b1) || (memory_write !== expected_write) ||
          (memory_write_data !== expected_write_data) || (result !== expected_result)) begin
        $display("FAIL %0s: valid=%b write=%b wdata=%h result=%h", name, memory_valid, memory_write, memory_write_data, result);
        failures = failures + 1;
      end
      @(posedge clk);
      #1;
      execute = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    execute = 1'b0;
    operation = ATOMIC_LR;
    word_operation = 1'b0;
    address = '0;
    source_data = '0;
    memory_read_data = '0;
    memory_ready = 1'b1;
    failures = 0;
    @(posedge clk);
    #1;
    reset = 1'b0;

    expect_atomic("lr establishes reservation", ATOMIC_LR, 1'b0, 64'h100, 64'd0, 64'd5, 1'b0, 64'd0, 64'd5);
    expect_atomic("sc succeeds at reserved address", ATOMIC_SC, 1'b0, 64'h100, 64'd7, 64'd5, 1'b1, 64'd7, 64'd0);
    expect_atomic("sc fails after reservation consumed", ATOMIC_SC, 1'b0, 64'h100, 64'd9, 64'd7, 1'b0, 64'd9, 64'd1);
    expect_atomic("amoadd returns old and writes new", ATOMIC_ADD, 1'b0, 64'h108, 64'd4, 64'd3, 1'b1, 64'd7, 64'd3);
    expect_atomic("amominw sign extends old word", ATOMIC_MIN, 1'b1, 64'h110, 64'hffff_ffff_0000_0001, 64'h0000_0000_8000_0000, 1'b1, 64'hffff_ffff_8000_0000, 64'hffff_ffff_8000_0000);
    expect_atomic("amo maxu chooses unsigned source", ATOMIC_MAXU, 1'b0, 64'h118, 64'd1, 64'h8000_0000_0000_0000, 1'b1, 64'h8000_0000_0000_0000, 64'h8000_0000_0000_0000);

    if (failures != 0) begin
      $display("SIM FAIL: %0d atomic checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_atomic_unit LR/SC/AMO regression");
    $finish;
  end
endmodule
