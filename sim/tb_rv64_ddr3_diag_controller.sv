`timescale 1ns/1ps

module tb_rv64_ddr3_diag_controller;
  logic clk = 1'b0;
  logic reset;
  logic init_calib_complete;
  logic request_valid;
  logic request_write;
  logic [63:0] request_address;
  logic [63:0] request_write_data;
  logic [7:0] request_write_strobe;
  logic request_ready;
  logic [63:0] response_read_data;
  logic response_error;
  logic done;
  logic failed;
  logic [1:0] pattern_phase;
  logic [7:0] word_index;
  logic [63:0] expected_data;
  logic [63:0] observed_data;
  logic [63:0] memory [0:255];
  logic pending;
  logic response_await_ack;
  logic pending_write;
  logic [7:0] pending_index;
  logic [63:0] pending_data;
  logic [1:0] response_delay;
  integer mode;
  integer test_index;

  rv64_ddr3_diag_controller dut (
    .*
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      request_ready <= 1'b0;
      response_read_data <= '0;
      response_error <= 1'b0;
      pending <= 1'b0;
      response_await_ack <= 1'b0;
      pending_write <= 1'b0;
      pending_index <= '0;
      pending_data <= '0;
      response_delay <= '0;
    end else begin
      request_ready <= 1'b0;
      response_error <= 1'b0;
      if (response_await_ack) begin
        if (request_valid) begin
          request_ready <= 1'b0;
          response_await_ack <= 1'b0;
        end else begin
          request_ready <= 1'b1;
        end
      end else if (!pending && request_valid) begin
        pending <= 1'b1;
        pending_write <= request_write;
        pending_index <= request_address[10:3];
        pending_data <= request_write_data;
        response_delay <= {1'b0, request_address[4:3]} + 1'b1;
      end else if (pending && response_delay != 0) begin
        response_delay <= response_delay - 1'b1;
      end else if (pending) begin
        pending <= 1'b0;
        response_await_ack <= 1'b1;
        request_ready <= 1'b1;
        if (pending_write) begin
          memory[pending_index] <= pending_data;
          response_error <= mode == 2;
        end else begin
          response_read_data <= mode == 1 ? ~memory[pending_index] : memory[pending_index];
          response_error <= mode == 2;
        end
      end
    end
  end

  task automatic start_test(input integer selected_mode);
    begin
      mode = selected_mode;
      reset = 1'b1;
      init_calib_complete = 1'b0;
      repeat (4) @(posedge clk);
      reset = 1'b0;
      repeat (3) @(posedge clk);
      init_calib_complete = 1'b1;
    end
  endtask

  task automatic wait_for_terminal(input logic expect_done);
    integer cycles;
    begin : wait_loop
      for (cycles = 0; cycles < 20000; cycles = cycles + 1) begin
        @(posedge clk);
        if (done || failed) begin
          if (failed) begin
            $display("DIAG_FAILURE mode=%0d phase=%0d index=%0d expected=%h observed=%h request_ready=%0b response_error=%0b", mode, pattern_phase, word_index, expected_data, observed_data, request_ready, response_error);
          end
          if (done != expect_done || failed == expect_done) begin
            $display("SIM FAIL: terminal state mismatch mode=%0d done=%0b failed=%0b", mode, done, failed);
            $finish;
          end
          disable wait_loop;
        end
      end
      $display("SIM FAIL: timeout mode=%0d phase=%0d index=%0d state=%0d req_valid=%0b req_ready=%0b pending=%0b ack=%0b delay=%0d", mode, pattern_phase, word_index, dut.state, request_valid, request_ready, pending, response_await_ack, response_delay);
      $finish;
    end
  endtask

  initial begin
    reset = 1'b1;
    init_calib_complete = 1'b0;
    mode = 0;
    for (test_index = 0; test_index < 256; test_index = test_index + 1) begin
      memory[test_index] = '0;
    end

    start_test(0);
    wait_for_terminal(1'b1);
    if (pattern_phase != 2'd3 || word_index != 8'd0) begin
      $display("SIM FAIL: success terminal counters phase=%0d index=%0d", pattern_phase, word_index);
      $finish;
    end

    start_test(1);
    wait_for_terminal(1'b0);

    start_test(2);
    wait_for_terminal(1'b0);

    $display("SIM PASS: DDR3 diagnostic controller success, data mismatch, and response error cases verified");
    $finish;
  end
endmodule
