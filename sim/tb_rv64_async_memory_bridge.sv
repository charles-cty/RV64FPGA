`timescale 1ns / 1ps

module tb_rv64_async_memory_bridge;
  logic cpu_clk;
  logic cpu_reset;
  logic cpu_request_valid;
  logic cpu_request_write;
  logic [63:0] cpu_request_address;
  logic [63:0] cpu_request_write_data;
  logic [7:0] cpu_request_write_strobe;
  logic cpu_request_ready;
  logic [63:0] cpu_response_read_data;
  logic cpu_response_error;
  logic ui_clk;
  logic ui_reset;
  logic ui_request_valid;
  logic ui_request_write;
  logic [63:0] ui_request_address;
  logic [63:0] ui_request_write_data;
  logic [7:0] ui_request_write_strobe;
  logic ui_request_ready;
  logic [63:0] ui_response_read_data;
  logic ui_response_error;
  integer failures;
  integer observed_requests;

  rv64_async_memory_bridge dut (.*);
  always #5 cpu_clk = ~cpu_clk;
  always #3.5 ui_clk = ~ui_clk;

  task automatic check_condition(input logic condition, input [511:0] message);
    begin
      if (!condition) begin
        $display("FAIL %0s", message);
        failures = failures + 1;
      end
    end
  endtask

  task automatic cpu_request(
    input logic write,
    input logic [63:0] address,
    input logic [63:0] write_data,
    input logic [7:0] write_strobe,
    input logic expected_error,
    input logic [63:0] expected_data
  );
    begin
      cpu_request_valid = 1'b1;
      cpu_request_write = write;
      cpu_request_address = address;
      cpu_request_write_data = write_data;
      cpu_request_write_strobe = write_strobe;
      @(posedge cpu_clk);
      #1;
      check_condition(!cpu_request_ready, "CPU request waits for UI response");
      while (!cpu_request_ready) begin
        @(posedge cpu_clk);
        #1;
      end
      check_condition(cpu_response_error === expected_error, "CPU response error");
      if (!write && !expected_error) begin
        check_condition(cpu_response_read_data === expected_data, "CPU response data");
      end
      @(posedge cpu_clk);
      #1;
      cpu_request_valid = 1'b0;
      @(posedge cpu_clk);
      #1;
    end
  endtask

  task automatic ui_respond(
    input logic expected_write,
    input logic [63:0] expected_address,
    input logic [63:0] expected_write_data,
    input logic [7:0] expected_write_strobe,
    input logic [63:0] response_data,
    input logic response_error
  );
    begin
      while (!ui_request_valid) begin
        @(posedge ui_clk);
        #1;
      end
      observed_requests = observed_requests + 1;
      check_condition(ui_request_write === expected_write &&
                      ui_request_address === expected_address &&
                      ui_request_write_data === expected_write_data &&
                      ui_request_write_strobe === expected_write_strobe,
                      "UI mailbox preserves every request field");
      repeat (3) begin
        @(posedge ui_clk);
        #1;
        check_condition(ui_request_valid, "UI request remains stable during backpressure");
      end
      ui_response_read_data = response_data;
      ui_response_error = response_error;
      ui_request_ready = 1'b1;
      @(posedge ui_clk);
      #1;
      ui_request_ready = 1'b0;
    end
  endtask

  initial begin
    cpu_clk = 1'b0;
    ui_clk = 1'b0;
    cpu_reset = 1'b1;
    ui_reset = 1'b1;
    cpu_request_valid = 1'b0;
    cpu_request_write = 1'b0;
    cpu_request_address = '0;
    cpu_request_write_data = '0;
    cpu_request_write_strobe = '0;
    ui_request_ready = 1'b0;
    ui_response_read_data = '0;
    ui_response_error = 1'b0;
    failures = 0;
    observed_requests = 0;

    @(posedge cpu_clk);
    #1;
    cpu_reset = 1'b0;
    @(posedge ui_clk);
    #1;
    ui_reset = 1'b0;

    fork
      cpu_request(1'b0, 64'h8000_0048, '0, '0, 1'b0, 64'h0123_4567_89ab_cdef);
      ui_respond(1'b0, 64'h8000_0048, '0, '0, 64'h0123_4567_89ab_cdef, 1'b0);
    join

    fork
      cpu_request(1'b1, 64'h8000_00a0, 64'hfeed_face_cafe_babe, 8'h3c, 1'b1, '0);
      ui_respond(1'b1, 64'h8000_00a0, 64'hfeed_face_cafe_babe, 8'h3c, '0, 1'b1);
    join

    cpu_request_valid = 1'b1;
    cpu_request_write = 1'b0;
    cpu_request_address = 64'h8000_0100;
    cpu_request_write_data = '0;
    cpu_request_write_strobe = '0;
    @(posedge cpu_clk);
    #1;
    while (!ui_request_valid) begin
      @(posedge ui_clk);
      #1;
    end
    observed_requests = observed_requests + 1;
    cpu_reset = 1'b1;
    ui_reset = 1'b1;
    #1;
    check_condition(!cpu_request_ready && !ui_request_valid, "asynchronous reset cancels pending request");
    @(posedge cpu_clk);
    #1;
    cpu_reset = 1'b0;
    @(posedge ui_clk);
    #1;
    ui_reset = 1'b0;
    cpu_request_valid = 1'b0;
    repeat (5) @(posedge cpu_clk);
    #1;
    check_condition(!cpu_request_ready && !ui_request_valid, "reset produces no duplicate response or request");
    check_condition(observed_requests == 3, "bridge accepts exactly one UI request per CPU request");

    if (failures != 0) $fatal(1, "SIM FAIL: %0d async bridge checks failed", failures);
    $display("SIM PASS: rv64_async_memory_bridge CDC regression");
    $finish;
  end
endmodule
