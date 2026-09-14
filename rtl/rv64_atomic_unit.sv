module rv64_atomic_unit (
  input  logic                  clk,
  input  logic                  reset,
  input  logic                  execute,
  input  riscv_pkg::atomic_op_t operation,
  input  logic                  word_operation,
  input  logic [63:0]           address,
  input  logic [63:0]           source_data,
  input  logic [63:0]           memory_read_data,
  input  logic                  memory_ready,
  output logic                  memory_valid,
  output logic                  memory_write,
  output logic [63:0]           memory_write_data,
  output logic [63:0]           result,
  output logic                  sc_success
);
  import riscv_pkg::*;

  logic        reservation_valid;
  logic [63:0] reservation_address;
  logic        reservation_matches;
  logic [63:0] old_value;
  logic [63:0] operation_value;

  always_comb begin
    old_value = word_operation ? {{32{memory_read_data[31]}}, memory_read_data[31:0]} : memory_read_data;
    reservation_matches = reservation_valid && (reservation_address == address);
    memory_valid = execute;
    memory_write = 1'b0;
    memory_write_data = source_data;
    result = old_value;
    sc_success = 1'b0;

    if (execute) begin
      unique case (operation)
        ATOMIC_LR: begin end
        ATOMIC_SC: begin
          sc_success = reservation_matches;
          memory_write = reservation_matches;
          result = reservation_matches ? 64'd0 : 64'd1;
        end
        default: begin
          memory_write = 1'b1;
          if (word_operation) begin
            operation_value = memory_read_data[31:0];
            unique case (operation)
              ATOMIC_SWAP: operation_value = source_data[31:0];
              ATOMIC_ADD: operation_value = memory_read_data[31:0] + source_data[31:0];
              ATOMIC_XOR: operation_value = memory_read_data[31:0] ^ source_data[31:0];
              ATOMIC_AND: operation_value = memory_read_data[31:0] & source_data[31:0];
              ATOMIC_OR: operation_value = memory_read_data[31:0] | source_data[31:0];
              ATOMIC_MIN: operation_value = ($signed(memory_read_data[31:0]) < $signed(source_data[31:0])) ? memory_read_data[31:0] : source_data[31:0];
              ATOMIC_MAX: operation_value = ($signed(memory_read_data[31:0]) > $signed(source_data[31:0])) ? memory_read_data[31:0] : source_data[31:0];
              ATOMIC_MINU: operation_value = (memory_read_data[31:0] < source_data[31:0]) ? memory_read_data[31:0] : source_data[31:0];
              ATOMIC_MAXU: operation_value = (memory_read_data[31:0] > source_data[31:0]) ? memory_read_data[31:0] : source_data[31:0];
              default: operation_value = memory_read_data[31:0];
            endcase
            memory_write_data = {{32{operation_value[31]}}, operation_value[31:0]};
          end else begin
            unique case (operation)
              ATOMIC_SWAP: operation_value = source_data;
              ATOMIC_ADD: operation_value = memory_read_data + source_data;
              ATOMIC_XOR: operation_value = memory_read_data ^ source_data;
              ATOMIC_AND: operation_value = memory_read_data & source_data;
              ATOMIC_OR: operation_value = memory_read_data | source_data;
              ATOMIC_MIN: operation_value = ($signed(memory_read_data) < $signed(source_data)) ? memory_read_data : source_data;
              ATOMIC_MAX: operation_value = ($signed(memory_read_data) > $signed(source_data)) ? memory_read_data : source_data;
              ATOMIC_MINU: operation_value = (memory_read_data < source_data) ? memory_read_data : source_data;
              ATOMIC_MAXU: operation_value = (memory_read_data > source_data) ? memory_read_data : source_data;
              default: operation_value = memory_read_data;
            endcase
            memory_write_data = operation_value;
          end
        end
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      reservation_valid <= 1'b0;
      reservation_address <= '0;
    end else if (execute && memory_ready) begin
      if (operation == ATOMIC_LR) begin
        reservation_valid <= 1'b1;
        reservation_address <= address;
      end else if (operation == ATOMIC_SC) begin
        reservation_valid <= 1'b0;
      end
    end
  end
endmodule
