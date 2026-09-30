module rv64_startup_reset #(
  parameter int unsigned HOLD_CYCLES = 256,
  parameter int unsigned COUNTER_WIDTH = $clog2(HOLD_CYCLES + 1)
) (
  input  logic clk,
  input  logic external_reset,
  output logic reset
);
  logic [COUNTER_WIDTH - 1:0] cycle_count = '0;

  always_comb begin
    reset = external_reset || cycle_count < HOLD_CYCLES;
  end

  always_ff @(posedge clk or posedge external_reset) begin
    if (external_reset) begin
      cycle_count <= '0;
    end else if (cycle_count < HOLD_CYCLES) begin
      cycle_count <= cycle_count + 1'b1;
    end
  end
endmodule
