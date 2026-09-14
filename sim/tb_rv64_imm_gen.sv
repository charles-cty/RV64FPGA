`timescale 1ns / 1ps

module tb_rv64_imm_gen;
  import riscv_pkg::*;

  logic [31:0] instruction;
  immediate_kind_t kind;
  logic [63:0] immediate;
  integer failures;

  rv64_imm_gen dut (.*);

  task automatic expect_immediate(
    input logic [511:0] name,
    input logic [31:0] expected_instruction,
    input immediate_kind_t expected_kind,
    input logic [63:0] expected_immediate
  );
    begin
      instruction = expected_instruction;
      kind = expected_kind;
      #1;
      if (immediate !== expected_immediate) begin
        $display("FAIL %0s: inst=%h got=%h expected=%h", name, instruction, immediate, expected_immediate);
        failures = failures + 1;
      end
    end
  endtask

  initial begin
    failures = 0;
    expect_immediate("positive I immediate", 32'h07f0_0093, IMM_I, 64'h7f);
    expect_immediate("negative I immediate", 32'h8000_0093, IMM_I, 64'hffff_ffff_ffff_f800);
    expect_immediate("negative S immediate", 32'hfe20_8fa3, IMM_S, 64'hffff_ffff_ffff_ffff);
    expect_immediate("positive B immediate", 32'h0000_0863, IMM_B, 64'h10);
    expect_immediate("negative B immediate", 32'hfe00_0ee3, IMM_B, 64'hffff_ffff_ffff_fffc);
    expect_immediate("U immediate sign extends", 32'h8123_45b7, IMM_U, 64'hffff_ffff_8123_4000);
    expect_immediate("positive J immediate", 32'h0080_006f, IMM_J, 64'h8);
    expect_immediate("negative J immediate", 32'hffff_f06f, IMM_J, 64'hffff_ffff_ffff_fffe);

    if (failures != 0) begin
      $display("SIM FAIL: %0d immediate checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_imm_gen directed regression");
    $finish;
  end
endmodule
