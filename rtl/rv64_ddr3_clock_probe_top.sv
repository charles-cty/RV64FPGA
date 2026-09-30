module rv64_ddr3_clock_probe_top (
  input  logic       clk_50,
  input  logic       reset_n,
  input  logic       sys_clk_p,
  input  logic       sys_clk_n,
  output logic [2:0] led
);
  logic sys_clk;
  logic sys_clk_buf;
  logic [22:0] sys_counter;
  logic sys_toggle;
  logic sync_toggle_meta;
  logic sync_toggle;
  logic last_toggle;
  logic clock_seen;
  logic [25:0] window_counter;
  logic window_complete;

  IBUFDS #(.DIFF_TERM("FALSE"), .IBUF_LOW_PWR("FALSE")) sys_clock_buffer (
    .I(sys_clk_p),
    .IB(sys_clk_n),
    .O(sys_clk)
  );

  BUFG sys_clock_global_buffer (
    .I(sys_clk),
    .O(sys_clk_buf)
  );

  always_ff @(posedge sys_clk_buf or negedge reset_n) begin
    if (!reset_n) begin
      sys_counter <= '0;
      sys_toggle <= 1'b0;
    end else if (&sys_counter) begin
      sys_counter <= '0;
      sys_toggle <= ~sys_toggle;
    end else begin
      sys_counter <= sys_counter + 1'b1;
    end
  end

  always_ff @(posedge clk_50 or negedge reset_n) begin
    if (!reset_n) begin
      sync_toggle_meta <= 1'b0;
      sync_toggle <= 1'b0;
      last_toggle <= 1'b0;
      clock_seen <= 1'b0;
      window_counter <= '0;
      window_complete <= 1'b0;
    end else begin
      sync_toggle_meta <= sys_toggle;
      sync_toggle <= sync_toggle_meta;
      if (sync_toggle != last_toggle) begin
        clock_seen <= 1'b1;
        last_toggle <= sync_toggle;
      end
      if (!window_complete) begin
        window_counter <= window_counter + 1'b1;
        if (&window_counter) begin
          window_complete <= 1'b1;
        end
      end
    end
  end

  assign led = {window_complete, clock_seen, reset_n};
endmodule
