module rv64_cache #(
  parameter integer LINE_COUNT = 4
) (
  input  logic        clk,
  input  logic        reset,
  input  logic        invalidate,
  input  logic        request_valid,
  output logic        request_ready,
  input  logic        request_write,
  input  logic [63:0] request_address,
  input  logic [63:0] request_write_data,
  input  logic [7:0]  request_write_strobe,
  output logic        response_valid,
  output logic [63:0] response_read_data,
  input  logic        response_ready,
  output logic        memory_valid,
  input  logic        memory_ready,
  output logic        memory_write,
  output logic [63:0] memory_address,
  output logic [63:0] memory_write_data,
  output logic [7:0]  memory_write_strobe,
  input  logic [63:0] memory_read_data
);
  localparam integer INDEX_BITS = $clog2(LINE_COUNT);

  typedef enum logic [1:0] {IDLE, READ_MISS, WRITE_THROUGH, RESPONSE} state_t;
  state_t state;
  logic [LINE_COUNT-1:0] line_valid;
  logic [63:0] line_tag [0:LINE_COUNT-1];
  logic [63:0] line_data [0:LINE_COUNT-1];
  logic [63:0] pending_address;
  logic [63:0] pending_write_data;
  logic [7:0] pending_write_strobe;
  logic [INDEX_BITS-1:0] pending_index;
  logic [63:0] pending_tag;
  integer reset_index;
  integer byte_index;

  logic [INDEX_BITS-1:0] request_index;
  logic [63:0] request_tag;
  logic request_hit;

  always_comb begin
    request_index = request_address[3 + INDEX_BITS - 1:3];
    request_tag = request_address >> (3 + INDEX_BITS);
    request_hit = line_valid[request_index] && line_tag[request_index] == request_tag;

    request_ready = state == IDLE;
    response_valid = state == RESPONSE;
    memory_valid = state == READ_MISS || state == WRITE_THROUGH;
    memory_write = state == WRITE_THROUGH;
    memory_address = {pending_address[63:3], 3'b000};
    memory_write_data = pending_write_data;
    memory_write_strobe = pending_write_strobe;
  end

  always_ff @(posedge clk) begin
    if (reset || invalidate) begin
      state <= IDLE;
      line_valid <= '0;
      response_read_data <= '0;
      pending_address <= '0;
      pending_write_data <= '0;
      pending_write_strobe <= '0;
      pending_index <= '0;
      pending_tag <= '0;
      for (reset_index = 0; reset_index < LINE_COUNT; reset_index = reset_index + 1) begin
        line_tag[reset_index] <= '0;
        line_data[reset_index] <= '0;
      end
    end else begin
      case (state)
        IDLE: begin
          if (request_valid) begin
            pending_address <= request_address;
            pending_write_data <= request_write_data;
            pending_write_strobe <= request_write_strobe;
            pending_index <= request_index;
            pending_tag <= request_tag;
            if (request_write) begin
              if (request_hit) begin
                for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
                  if (request_write_strobe[byte_index]) begin
                    line_data[request_index][byte_index*8 +: 8] <=
                      request_write_data[byte_index*8 +: 8];
                  end
                end
              end else begin
                line_valid[request_index] <= 1'b0;
              end
              state <= WRITE_THROUGH;
            end else if (request_hit) begin
              response_read_data <= line_data[request_index];
              state <= RESPONSE;
            end else begin
              state <= READ_MISS;
            end
          end
        end
        READ_MISS: begin
          if (memory_ready) begin
            line_valid[pending_index] <= 1'b1;
            line_tag[pending_index] <= pending_tag;
            line_data[pending_index] <= memory_read_data;
            response_read_data <= memory_read_data;
            state <= RESPONSE;
          end
        end
        WRITE_THROUGH: begin
          if (memory_ready) begin
            response_read_data <= '0;
            state <= RESPONSE;
          end
        end
        RESPONSE: begin
          if (response_ready) begin
            state <= IDLE;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
