module rv64_ddr3_arbiter (
  input  logic        clk,
  input  logic        reset,
  input  logic        instruction_request_valid,
  input  logic        instruction_request_write,
  input  logic [63:0] instruction_request_address,
  input  logic [63:0] instruction_request_write_data,
  input  logic [7:0]  instruction_request_write_strobe,
  output logic        instruction_request_ready,
  output logic [63:0] instruction_response_read_data,
  output logic        instruction_response_error,
  input  logic        data_request_valid,
  input  logic        data_request_write,
  input  logic [63:0] data_request_address,
  input  logic [63:0] data_request_write_data,
  input  logic [7:0]  data_request_write_strobe,
  output logic        data_request_ready,
  output logic [63:0] data_response_read_data,
  output logic        data_response_error,
  output logic        memory_request_valid,
  output logic        memory_request_write,
  output logic [63:0] memory_request_address,
  output logic [63:0] memory_request_write_data,
  output logic [7:0]  memory_request_write_strobe,
  input  logic        memory_request_ready,
  input  logic [63:0] memory_response_read_data,
  input  logic        memory_response_error
);
  typedef enum logic {IDLE, WAITING} state_t;

  state_t state;
  logic selected_instruction;
  logic last_grant_instruction;
  logic request_write_latched;
  logic [63:0] request_address_latched;
  logic [63:0] request_write_data_latched;
  logic [7:0] request_write_strobe_latched;
  logic selected_request_ready;

  always_comb begin
    selected_request_ready = state == WAITING && memory_request_ready;
    instruction_request_ready = selected_request_ready && selected_instruction;
    data_request_ready = selected_request_ready && !selected_instruction;
    instruction_response_read_data = memory_response_read_data;
    data_response_read_data = memory_response_read_data;
    instruction_response_error = instruction_request_ready && memory_response_error;
    data_response_error = data_request_ready && memory_response_error;
    memory_request_valid = state == WAITING;
    memory_request_write = request_write_latched;
    memory_request_address = request_address_latched;
    memory_request_write_data = request_write_data_latched;
    memory_request_write_strobe = request_write_strobe_latched;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      state <= IDLE;
      selected_instruction <= 1'b0;
      last_grant_instruction <= 1'b0;
      request_write_latched <= 1'b0;
      request_address_latched <= '0;
      request_write_data_latched <= '0;
      request_write_strobe_latched <= '0;
    end else begin
      case (state)
        IDLE: begin
          if (instruction_request_valid && data_request_valid) begin
            selected_instruction <= !last_grant_instruction;
            request_write_latched <= last_grant_instruction ? data_request_write : instruction_request_write;
            request_address_latched <= last_grant_instruction ? data_request_address : instruction_request_address;
            request_write_data_latched <= last_grant_instruction ? data_request_write_data : instruction_request_write_data;
            request_write_strobe_latched <= last_grant_instruction ? data_request_write_strobe : instruction_request_write_strobe;
            last_grant_instruction <= !last_grant_instruction;
            state <= WAITING;
          end else if (instruction_request_valid) begin
            selected_instruction <= 1'b1;
            request_write_latched <= instruction_request_write;
            request_address_latched <= instruction_request_address;
            request_write_data_latched <= instruction_request_write_data;
            request_write_strobe_latched <= instruction_request_write_strobe;
            last_grant_instruction <= 1'b1;
            state <= WAITING;
          end else if (data_request_valid) begin
            selected_instruction <= 1'b0;
            request_write_latched <= data_request_write;
            request_address_latched <= data_request_address;
            request_write_data_latched <= data_request_write_data;
            request_write_strobe_latched <= data_request_write_strobe;
            last_grant_instruction <= 1'b0;
            state <= WAITING;
          end
        end
        WAITING: begin
          if (memory_request_ready) begin
            state <= IDLE;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
