`timescale 1ns / 1ps

module tb_rv64_ddr3_model;
  logic clk;
  logic reset;
  logic calibrated;
  logic request_valid;
  logic request_write;
  logic [63:0] request_address;
  logic [63:0] request_write_data;
  logic [7:0] request_write_strobe;
  logic request_ready;
  logic [63:0] response_read_data;
  logic response_error;
  integer failures;
  integer cycle_count;

  rv64_ddr3_model #(.WORD_COUNT(16), .RESPONSE_DELAY(2)) dut (.*);
  always #5 clk = ~clk;

  task automatic request(
    input logic write,
    input logic [63:0] address,
    input logic [63:0] write_data,
    input logic [7:0] write_strobe,
    input logic expected_error,
    input logic [63:0] expected_read_data
  );
    begin
      request_valid = 1'b1;
      request_write = write;
      request_address = address;
      request_write_data = write_data;
      request_write_strobe = write_strobe;
      cycle_count = 0;
      while (!request_ready && cycle_count < 8) begin
        @(posedge clk);
        #1;
        cycle_count = cycle_count + 1;
      end
      if (!request_ready || response_error !== expected_error ||
          (!write && !expected_error && response_read_data !== expected_read_data)) begin
        $display("FAIL DDR model ready=%b error=%b read=%h cycles=%0d", request_ready,
                 response_error, response_read_data, cycle_count);
        failures = failures + 1;
      end
      @(posedge clk);
      #1;
      request_valid = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    calibrated = 1'b1;
    request_valid = 1'b0;
    request_write = 1'b0;
    request_address = '0;
    request_write_data = '0;
    request_write_strobe = '0;
    failures = 0;
    @(posedge clk);
    #1;
    reset = 1'b0;

    request(1'b1, 64'h20, 64'h1122_3344_5566_7788, 8'hff, 1'b0, '0);
    request(1'b0, 64'h20, '0, '0, 1'b0, 64'h1122_3344_5566_7788);
    request(1'b1, 64'h20, 64'hffff_ffff_ffff_aabb, 8'h03, 1'b0, '0);
    request(1'b0, 64'h20, '0, '0, 1'b0, 64'h1122_3344_5566_aabb);

    calibrated = 1'b0;
    request(1'b0, 64'h20, '0, '0, 1'b1, '0);
    calibrated = 1'b1;
    request_valid = 1'b1;
    request_write = 1'b1;
    request_address = 64'h28;
    request_write_data = 64'hfeed_face_cafe_babe;
    request_write_strobe = 8'hff;
    @(posedge clk);
    #1;
    reset = 1'b1;
    @(posedge clk);
    #1;
    reset = 1'b0;
    request_valid = 1'b0;
    request(1'b1, 64'h28, 64'h0123_4567_89ab_cdef, 8'hff, 1'b0, '0);
    request(1'b0, 64'h28, '0, '0, 1'b0, 64'h0123_4567_89ab_cdef);

    if (failures != 0) $fatal(1, "SIM FAIL: %0d DDR3 model checks failed", failures);
    $display("SIM PASS: rv64_ddr3_model delayed memory regression");
    $finish;
  end
endmodule
