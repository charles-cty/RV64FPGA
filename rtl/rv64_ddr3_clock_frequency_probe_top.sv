module rv64_ddr3_clock_frequency_probe_top #(
  parameter integer COUNTER_WIDTH = 30,
  parameter integer SAMPLE_BITS = 25,
  parameter logic [COUNTER_WIDTH-1:0] MIN_TICKS = 30'd128000000,
  parameter logic [COUNTER_WIDTH-1:0] MAX_TICKS = 30'd140000000
) (
  input  logic       clk_50,
  input  logic       reset_n,
  input  logic       sys_clk_p,
  input  logic       sys_clk_n,
  output logic [2:0] led
);
  typedef enum logic [1:0] {
    ARM,
    MEASURE,
    CHECK,
    COMPLETE
  } state_t;

  logic sys_clk;
  logic sys_clk_buf;
  logic [COUNTER_WIDTH-1:0] sys_count;
  logic [COUNTER_WIDTH-1:0] sys_count_gray;
  logic [COUNTER_WIDTH-1:0] gray_sync_meta;
  logic [COUNTER_WIDTH-1:0] gray_sync;
  logic [COUNTER_WIDTH-1:0] start_count;
  logic [COUNTER_WIDTH-1:0] end_count;
  logic [SAMPLE_BITS-1:0] sample_counter;
  logic [3:0] arm_counter;
  logic frequency_valid;
  logic measurement_complete;
  state_t state;

  function automatic logic [COUNTER_WIDTH-1:0] gray_to_binary(
    input logic [COUNTER_WIDTH-1:0] gray_value
  );
    integer bit_index;
    begin
      gray_to_binary[COUNTER_WIDTH-1] = gray_value[COUNTER_WIDTH-1];
      for (bit_index = COUNTER_WIDTH - 2; bit_index >= 0; bit_index = bit_index - 1) begin
        gray_to_binary[bit_index] = gray_to_binary[bit_index + 1] ^ gray_value[bit_index];
      end
    end
  endfunction

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
      sys_count <= '0;
    end else begin
      sys_count <= sys_count + 1'b1;
    end
  end

  assign sys_count_gray = sys_count ^ (sys_count >> 1);

  always_ff @(posedge clk_50 or negedge reset_n) begin
    if (!reset_n) begin
      gray_sync_meta <= '0;
      gray_sync <= '0;
      start_count <= '0;
      end_count <= '0;
      sample_counter <= '0;
      arm_counter <= '0;
      frequency_valid <= 1'b0;
      measurement_complete <= 1'b0;
      state <= ARM;
    end else begin
      gray_sync_meta <= sys_count_gray;
      gray_sync <= gray_sync_meta;
      case (state)
        ARM: begin
          if (&arm_counter) begin
            start_count <= gray_to_binary(gray_sync);
            state <= MEASURE;
          end else begin
            arm_counter <= arm_counter + 1'b1;
          end
        end
        MEASURE: begin
          if (&sample_counter) begin
            end_count <= gray_to_binary(gray_sync);
            state <= CHECK;
          end else begin
            sample_counter <= sample_counter + 1'b1;
          end
        end
        CHECK: begin
          frequency_valid <= (end_count - start_count >= MIN_TICKS) &&
                             (end_count - start_count <= MAX_TICKS);
          measurement_complete <= 1'b1;
          state <= COMPLETE;
        end
        COMPLETE: state <= COMPLETE;
        default: state <= COMPLETE;
      endcase
    end
  end

  assign led = {measurement_complete, frequency_valid, reset_n};
endmodule
