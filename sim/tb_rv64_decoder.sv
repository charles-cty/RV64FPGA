`timescale 1ns / 1ps

module tb_rv64_decoder;
  import riscv_pkg::*;

  logic [31:0] instruction;
  alu_op_t operation;
  logic uses_immediate;
  logic writes_register;
  logic illegal;
  integer failures;

  rv64_decoder dut (.*);

  task automatic expect_decode(
    input logic [511:0] name,
    input logic [31:0] expected_instruction,
    input alu_op_t expected_operation,
    input logic expected_immediate,
    input logic expected_write,
    input logic expected_illegal
  );
    begin
      instruction = expected_instruction;
      #1;
      if ((operation !== expected_operation) ||
          (uses_immediate !== expected_immediate) ||
          (writes_register !== expected_write) ||
          (illegal !== expected_illegal)) begin
        $display("FAIL %0s: inst=%h op=%0d imm=%b wr=%b illegal=%b", name, instruction, operation, uses_immediate, writes_register, illegal);
        failures = failures + 1;
      end
    end
  endtask

  initial begin
    failures = 0;
    expect_decode("addi", 32'h0010_0093, ALU_ADD, 1'b1, 1'b1, 1'b0);
    expect_decode("srai", 32'h4010_d093, ALU_SRA, 1'b1, 1'b1, 1'b0);
    expect_decode("addw", 32'h0020_81bb, ALU_ADDW, 1'b0, 1'b1, 1'b0);
    expect_decode("mulhsu", 32'h0220_a233, ALU_MULHSU, 1'b0, 1'b1, 1'b0);
    expect_decode("divuw", 32'h0221_d23b, ALU_DIVUW, 1'b0, 1'b1, 1'b0);
    expect_decode("bad shift funct7", 32'h6010_9093, ALU_SLL, 1'b1, 1'b0, 1'b1);
    expect_decode("unsupported opcode", 32'h0000_0000, ALU_ADD, 1'b0, 1'b0, 1'b1);

    if (failures != 0) begin
      $display("SIM FAIL: %0d decoder checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_decoder directed regression");
    $finish;
  end
endmodule
