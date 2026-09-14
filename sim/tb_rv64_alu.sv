`timescale 1ns / 1ps

module tb_rv64_alu;
  import riscv_pkg::*;

  logic [63:0] lhs;
  logic [63:0] rhs;
  alu_op_t operation;
  logic [63:0] result;
  integer failures;

  rv64_alu dut (
    .lhs(lhs),
    .rhs(rhs),
    .operation(operation),
    .result(result)
  );

  task automatic expect_result(
    input logic [511:0] name,
    input alu_op_t expected_operation,
    input logic [63:0] expected_lhs,
    input logic [63:0] expected_rhs,
    input logic [63:0] expected_result
  );
    begin
      operation = expected_operation;
      lhs = expected_lhs;
      rhs = expected_rhs;
      #1;
      if (result !== expected_result) begin
        $display("FAIL %0s: lhs=%h rhs=%h got=%h expected=%h", name, lhs, rhs, result, expected_result);
        failures = failures + 1;
      end
    end
  endtask

  initial begin
    failures = 0;

    expect_result("add wraps at 64 bits", ALU_ADD, 64'hffff_ffff_ffff_ffff, 64'd1, 64'd0);
    expect_result("signed comparison sees negative", ALU_SLT, 64'hffff_ffff_ffff_ffff, 64'd1, 64'd1);
    expect_result("unsigned comparison rejects negative bit pattern", ALU_SLTU, 64'hffff_ffff_ffff_ffff, 64'd1, 64'd0);
    expect_result("rv64 shift amount uses six bits", ALU_SLL, 64'd1, 64'd64, 64'd1);
    expect_result("arithmetic right shift preserves sign", ALU_SRA, 64'h8000_0000_0000_0000, 64'd63, 64'hffff_ffff_ffff_ffff);
    expect_result("addw sign extends lower word", ALU_ADDW, 64'h0000_0000_7fff_ffff, 64'd1, 64'hffff_ffff_8000_0000);
    expect_result("sllw masks shift amount to five bits", ALU_SLLW, 64'd1, 64'd32, 64'd1);
    expect_result("sraw sign extends lower word", ALU_SRAW, 64'h0000_0000_8000_0000, 64'd31, 64'hffff_ffff_ffff_ffff);
    expect_result("mulh signed negative product", ALU_MULH, 64'hffff_ffff_ffff_ffff, 64'd2, 64'hffff_ffff_ffff_ffff);
    expect_result("mulhsu handles high unsigned operand", ALU_MULHSU, 64'hffff_ffff_ffff_ffff, 64'hffff_ffff_ffff_ffff, 64'hffff_ffff_ffff_ffff);
    expect_result("div by zero returns minus one", ALU_DIV, 64'd7, 64'd0, 64'hffff_ffff_ffff_ffff);
    expect_result("signed minimum divided by minus one", ALU_DIV, 64'h8000_0000_0000_0000, 64'hffff_ffff_ffff_ffff, 64'h8000_0000_0000_0000);
    expect_result("remainder of signed overflow is zero", ALU_REM, 64'h8000_0000_0000_0000, 64'hffff_ffff_ffff_ffff, 64'd0);
    expect_result("divw by zero sign extends", ALU_DIVW, 64'd7, 64'd0, 64'hffff_ffff_ffff_ffff);
    expect_result("divuw result sign extends", ALU_DIVUW, 64'h0000_0000_ffff_fffe, 64'd1, 64'hffff_ffff_ffff_fffe);
    expect_result("remw overflow is zero", ALU_REMW, 64'h0000_0000_8000_0000, 64'hffff_ffff_ffff_ffff, 64'd0);

    if (failures != 0) begin
      $display("SIM FAIL: %0d ALU checks failed", failures);
      $fatal(1);
    end

    $display("SIM PASS: rv64_alu directed boundary regression");
    $finish;
  end
endmodule
