`timescale 1ns / 1ps

module tb_rv64_regfile;
  logic clk;
  logic reset;
  logic write_enable;
  logic [4:0] write_address;
  logic [63:0] write_data;
  logic [4:0] read_address_a;
  logic [4:0] read_address_b;
  logic [63:0] read_data_a;
  logic [63:0] read_data_b;
  integer failures;

  rv64_regfile dut (.*);

  always #5 clk = ~clk;

  task automatic expect_value(input logic [511:0] name, input logic [63:0] expected_a, input logic [63:0] expected_b);
    begin
      #1;
      if ((read_data_a !== expected_a) || (read_data_b !== expected_b)) begin
        $display("FAIL %0s: A=%h (expected %h), B=%h (expected %h)", name, read_data_a, expected_a, read_data_b, expected_b);
        failures = failures + 1;
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    write_enable = 1'b0;
    write_address = '0;
    write_data = '0;
    read_address_a = '0;
    read_address_b = '0;
    failures = 0;

    @(posedge clk);
    #1;
    reset = 1'b0;
    read_address_a = 5'd7;
    read_address_b = 5'd0;
    expect_value("reset clears registers and x0", 64'd0, 64'd0);

    write_enable = 1'b1;
    write_address = 5'd7;
    write_data = 64'h0123_4567_89ab_cdef;
    @(posedge clk);
    #1;
    write_enable = 1'b0;
    expect_value("write is visible after clock edge", 64'h0123_4567_89ab_cdef, 64'd0);

    write_enable = 1'b1;
    write_address = 5'd0;
    write_data = 64'hffff_ffff_ffff_ffff;
    @(posedge clk);
    #1;
    write_enable = 1'b0;
    read_address_a = 5'd0;
    read_address_b = 5'd7;
    expect_value("x0 ignores writes", 64'd0, 64'h0123_4567_89ab_cdef);

    if (failures != 0) begin
      $display("SIM FAIL: %0d register file checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_regfile directed regression");
    $finish;
  end
endmodule
