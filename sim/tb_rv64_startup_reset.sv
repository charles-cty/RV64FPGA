`timescale 1ns / 1ps

module tb_rv64_startup_reset;
  logic clk;
  logic external_reset;
  logic reset;

  rv64_startup_reset #(.HOLD_CYCLES(256)) dut (.*);

  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    external_reset = 1'b0;
    #1;
    if (!reset) $fatal(1, "SIM FAIL: startup reset was not asserted at configuration");
    repeat (255) @(posedge clk);
    #1;
    if (!reset) $fatal(1, "SIM FAIL: startup reset ended before the hold interval");
    @(posedge clk);
    #1;
    if (reset) $fatal(1, "SIM FAIL: startup reset did not end after the hold interval");

    external_reset = 1'b1;
    #1;
    if (!reset) $fatal(1, "SIM FAIL: external reset did not assert startup reset");
    @(posedge clk);
    #1;
    external_reset = 1'b0;
    repeat (255) @(posedge clk);
    #1;
    if (!reset) $fatal(1, "SIM FAIL: external reset did not restart the hold interval");
    @(posedge clk);
    #1;
    if (reset) $fatal(1, "SIM FAIL: restarted hold interval did not end");
    $display("SIM PASS: rv64_startup_reset regression");
    $finish;
  end
endmodule
