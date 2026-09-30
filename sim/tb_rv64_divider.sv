`timescale 1ns / 1ps

module tb_rv64_divider;
  logic clk;
  logic reset;
  logic start;
  logic result_consumed;
  logic signed_operation;
  logic remainder_operation;
  logic word_operation;
  logic [63:0] dividend;
  logic [63:0] divisor;
  logic busy;
  logic result_valid;
  logic [63:0] result;
  integer failures;
  integer cycle_count;

  rv64_divider dut (.*);

  always #5 clk = ~clk;

  task automatic expect_result(
    input logic [255:0] name,
    input logic         is_signed,
    input logic         is_remainder,
    input logic         is_word,
    input logic [63:0]  lhs,
    input logic [63:0]  rhs,
    input logic [63:0]  expected
  );
    begin
      signed_operation = is_signed;
      remainder_operation = is_remainder;
      word_operation = is_word;
      dividend = lhs;
      divisor = rhs;
      start = 1'b1;
      @(posedge clk);
      #1;
      start = 1'b0;
      for (cycle_count = 0; cycle_count < 66 && !result_valid; cycle_count = cycle_count + 1) begin
        @(posedge clk);
        #1;
      end
      if (!result_valid || busy || result !== expected) begin
        $display("FAIL %0s: valid=%b busy=%b result=%h expected=%h cycles=%0d",
                 name, result_valid, busy, result, expected, cycle_count);
        failures = failures + 1;
      end
      result_consumed = 1'b1;
      @(posedge clk);
      #1;
      result_consumed = 1'b0;
      if (result_valid) begin
        $display("FAIL %0s: result was not consumed", name);
        failures = failures + 1;
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    start = 1'b0;
    result_consumed = 1'b0;
    signed_operation = 1'b0;
    remainder_operation = 1'b0;
    word_operation = 1'b0;
    dividend = '0;
    divisor = '0;
    failures = 0;

    @(posedge clk);
    #1;
    reset = 1'b0;

    expect_result("unsigned quotient", 1'b0, 1'b0, 1'b0, 64'd100, 64'd7, 64'd14);
    expect_result("unsigned remainder", 1'b0, 1'b1, 1'b0, 64'd100, 64'd7, 64'd2);
    expect_result("signed negative quotient", 1'b1, 1'b0, 1'b0, -64'sd100, 64'd7, -64'sd14);
    expect_result("signed negative remainder", 1'b1, 1'b1, 1'b0, -64'sd100, 64'd7, -64'sd2);
    expect_result("signed overflow quotient", 1'b1, 1'b0, 1'b0,
                  64'h8000_0000_0000_0000, 64'hffff_ffff_ffff_ffff,
                  64'h8000_0000_0000_0000);
    expect_result("signed overflow remainder", 1'b1, 1'b1, 1'b0,
                  64'h8000_0000_0000_0000, 64'hffff_ffff_ffff_ffff, 64'd0);
    expect_result("division by zero", 1'b0, 1'b0, 1'b0, 64'd7, 64'd0,
                  64'hffff_ffff_ffff_ffff);
    expect_result("remainder by zero", 1'b0, 1'b1, 1'b0, 64'hfedc_ba98_7654_3210, 64'd0,
                  64'hfedc_ba98_7654_3210);
    expect_result("unsigned word quotient sign extends", 1'b0, 1'b0, 1'b1,
                  64'h0000_0000_ffff_fffe, 64'd1, 64'hffff_ffff_ffff_fffe);
    expect_result("signed word quotient", 1'b1, 1'b0, 1'b1,
                  64'h0000_0000_ffff_fff6, 64'd3, 64'hffff_ffff_ffff_fffd);
    expect_result("signed word remainder", 1'b1, 1'b1, 1'b1,
                  64'h0000_0000_ffff_fff6, 64'd3, 64'hffff_ffff_ffff_ffff);

    if (failures != 0) begin
      $display("SIM FAIL: %0d rv64_divider checks failed", failures);
      $fatal(1);
    end else begin
      $display("SIM PASS: rv64_divider iterative boundary regression");
    end
    $finish;
  end
endmodule
