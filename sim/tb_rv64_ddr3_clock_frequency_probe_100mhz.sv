`timescale 1ns / 1ps

module tb_rv64_ddr3_clock_frequency_probe_100mhz;
  logic clk_50 = 1'b0;
  logic reset_n = 1'b0;
  logic sys_clk_p = 1'b0;
  logic sys_clk_n = 1'b1;
  logic [2:0] led;

  rv64_ddr3_clock_frequency_probe_top #(
    .SAMPLE_BITS(4),
    .MIN_TICKS(30'd55),
    .MAX_TICKS(30'd75)
  ) dut (
    .clk_50(clk_50),
    .reset_n(reset_n),
    .sys_clk_p(sys_clk_p),
    .sys_clk_n(sys_clk_n),
    .led(led)
  );

  always #10 clk_50 = ~clk_50;
  always #5 begin
    sys_clk_p = ~sys_clk_p;
    sys_clk_n = ~sys_clk_n;
  end

  initial begin
    #100;
    reset_n = 1'b1;
    wait (led[2]);
    if (led !== 3'b101) begin
      $fatal(1, "100 MHz clock must fail the 200 MHz frequency check");
    end
    $display("SIM_PASS clock-frequency-probe-100mhz");
    $finish;
  end
endmodule
