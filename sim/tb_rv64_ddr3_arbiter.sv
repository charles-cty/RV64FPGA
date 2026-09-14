`timescale 1ns / 1ps

module tb_rv64_ddr3_arbiter;
  logic clk;
  logic reset;
  logic i_valid;
  logic i_write;
  logic [63:0] i_address;
  logic [63:0] i_write_data;
  logic [7:0] i_write_strobe;
  logic i_ready;
  logic [63:0] i_read_data;
  logic i_error;
  logic d_valid;
  logic d_write;
  logic [63:0] d_address;
  logic [63:0] d_write_data;
  logic [7:0] d_write_strobe;
  logic d_ready;
  logic [63:0] d_read_data;
  logic d_error;
  logic memory_valid;
  logic memory_write;
  logic [63:0] memory_address;
  logic [63:0] memory_write_data;
  logic [7:0] memory_write_strobe;
  logic memory_ready;
  logic [63:0] memory_read_data;
  logic memory_error;
  integer failures;
  integer cycle_count;

  rv64_ddr3_arbiter dut (.*,
    .instruction_request_valid(i_valid), .instruction_request_write(i_write),
    .instruction_request_address(i_address), .instruction_request_write_data(i_write_data),
    .instruction_request_write_strobe(i_write_strobe), .instruction_request_ready(i_ready),
    .instruction_response_read_data(i_read_data), .instruction_response_error(i_error),
    .data_request_valid(d_valid), .data_request_write(d_write),
    .data_request_address(d_address), .data_request_write_data(d_write_data),
    .data_request_write_strobe(d_write_strobe), .data_request_ready(d_ready),
    .data_response_read_data(d_read_data), .data_response_error(d_error),
    .memory_request_valid(memory_valid), .memory_request_write(memory_write),
    .memory_request_address(memory_address), .memory_request_write_data(memory_write_data),
    .memory_request_write_strobe(memory_write_strobe), .memory_request_ready(memory_ready),
    .memory_response_read_data(memory_read_data), .memory_response_error(memory_error));

  rv64_ddr3_model #(.WORD_COUNT(16), .RESPONSE_DELAY(2)) memory_model (
    .clk(clk), .reset(reset), .calibrated(1'b1), .request_valid(memory_valid),
    .request_write(memory_write), .request_address(memory_address),
    .request_write_data(memory_write_data), .request_write_strobe(memory_write_strobe),
    .request_ready(memory_ready), .response_read_data(memory_read_data),
    .response_error(memory_error));

  always #5 clk = ~clk;

  task automatic issue_instruction(input logic [63:0] address, input logic [63:0] value);
    begin
      i_valid = 1'b1;
      i_write = 1'b1;
      i_address = address;
      i_write_data = value;
      i_write_strobe = 8'hff;
      while (!i_ready) @(posedge clk);
      @(posedge clk);
      i_valid = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    i_valid = 1'b0;
    i_write = 1'b0;
    i_address = '0;
    i_write_data = '0;
    i_write_strobe = '0;
    d_valid = 1'b0;
    d_write = 1'b0;
    d_address = '0;
    d_write_data = '0;
    d_write_strobe = '0;
    #1;
    @(posedge clk);
    #1;
    reset = 1'b0;

    i_valid = 1'b1;
    i_write = 1'b1;
    i_address = 64'd0;
    i_write_data = 64'h1122_3344_5566_7788;
    i_write_strobe = 8'hff;
    d_valid = 1'b1;
    d_write = 1'b1;
    d_address = 64'd8;
    d_write_data = 64'h8877_6655_4433_2211;
    d_write_strobe = 8'hff;
    while (!(i_ready || d_ready)) @(posedge clk);
    if (!i_ready || d_ready || memory_address !== 64'd0) begin
      $display("FAIL arbiter first grant i_ready=%b d_ready=%b address=%h", i_ready, d_ready, memory_address);
      failures = failures + 1;
    end
    @(posedge clk);
    while (!(i_ready || d_ready)) @(posedge clk);
    if (!d_ready || i_ready || memory_address !== 64'd8) begin
      $display("FAIL arbiter second grant i_ready=%b d_ready=%b address=%h", i_ready, d_ready, memory_address);
      failures = failures + 1;
    end
    @(posedge clk);
    i_valid = 1'b0;
    d_valid = 1'b0;

    d_valid = 1'b1;
    d_write = 1'b0;
    d_address = 64'd0;
    while (!d_ready) @(posedge clk);
    if (d_read_data !== 64'h1122_3344_5566_7788 || d_error) begin
      $display("FAIL data response data=%h error=%b", d_read_data, d_error);
      failures = failures + 1;
    end
    @(posedge clk);
    d_valid = 1'b0;

    i_valid = 1'b1;
    i_write = 1'b0;
    i_address = 64'd8;
    while (!i_ready) @(posedge clk);
    if (i_read_data !== 64'h8877_6655_4433_2211 || i_error) begin
      $display("FAIL instruction response data=%h error=%b", i_read_data, i_error);
      failures = failures + 1;
    end
    @(posedge clk);
    i_valid = 1'b0;

    for (cycle_count = 0; cycle_count < 4; cycle_count = cycle_count + 1) @(posedge clk);
    if (failures != 0) $fatal(1, "SIM FAIL: %0d DDR3 arbiter checks failed", failures);
    $display("SIM PASS: rv64_ddr3_arbiter serialization regression");
    $finish;
  end
endmodule
