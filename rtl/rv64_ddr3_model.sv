module rv64_ddr3_model #(
  parameter integer WORD_COUNT = 1024,
  parameter integer RESPONSE_DELAY = 2
) (
  input  logic        clk,
  input  logic        reset,
  input  logic        calibrated,
  input  logic        request_valid,
  input  logic        request_write,
  input  logic [63:0] request_address,
  input  logic [63:0] request_write_data,
  input  logic [7:0]  request_write_strobe,
  output logic        request_ready,
  output logic [63:0] response_read_data,
  output logic        response_error
);
  typedef enum logic {IDLE, WAITING} state_t;

  state_t state;
  logic request_write_latched;
  logic [63:0] request_address_latched;
  logic [63:0] request_write_data_latched;
  logic [7:0] request_write_strobe_latched;
  integer delay_count;
  integer byte_index;
  logic [63:0] memory [0:WORD_COUNT-1];

  always_comb begin
    request_ready = state == WAITING && delay_count == 0;
    response_read_data = memory[request_address_latched[$clog2(WORD_COUNT)+2:3]];
    response_error = request_ready && !calibrated;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      state <= IDLE;
      delay_count <= 0;
      request_write_latched <= 1'b0;
      request_address_latched <= '0;
      request_write_data_latched <= '0;
      request_write_strobe_latched <= '0;
    end else if (state == IDLE) begin
      if (request_valid) begin
        request_write_latched <= request_write;
        request_address_latched <= request_address;
        request_write_data_latched <= request_write_data;
        request_write_strobe_latched <= request_write_strobe;
        delay_count <= RESPONSE_DELAY;
        state <= WAITING;
      end
    end else if (delay_count != 0) begin
      delay_count <= delay_count - 1;
    end else if (request_valid) begin
      if (calibrated && request_write_latched) begin
        for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
          if (request_write_strobe_latched[byte_index]) begin
            memory[request_address_latched[$clog2(WORD_COUNT)+2:3]][byte_index*8 +: 8] <=
              request_write_data_latched[byte_index*8 +: 8];
          end
        end
      end
      state <= IDLE;
    end
  end
endmodule
