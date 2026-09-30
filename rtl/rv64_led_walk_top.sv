module rv64_led_walk_top (
  input  logic       clk_50,
  output logic [2:0] led
);
  logic [25:0] counter = '0;

  always_ff @(posedge clk_50) begin
    counter <= counter + 1'b1;
  end

  always_comb begin
    unique case (counter[25:24])
      2'd0: led = 3'b001;
      2'd1: led = 3'b010;
      2'd2: led = 3'b100;
      default: led = 3'b000;
    endcase
  end
endmodule
