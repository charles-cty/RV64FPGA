module rv64_core (
  input  logic        clk,
  input  logic        reset,
  output logic [63:0] instruction_address,
  input  logic [31:0] instruction_data,
  output logic        data_valid,
  output logic        data_write,
  output logic [63:0] data_address,
  output logic [63:0] data_write_data,
  output logic [7:0]  data_write_strobe,
  input  logic [63:0] data_read_data,
  input  logic        data_ready,
  output logic        commit_valid,
  output logic [63:0] commit_pc,
  output logic [31:0] commit_instruction,
  output logic        commit_rd_write,
  output logic [4:0]  commit_rd,
  output logic [63:0] commit_rd_value,
  output logic        illegal_instruction
);
  import riscv_pkg::*;

  logic [63:0] program_counter;
  logic [63:0] register_a;
  logic [63:0] register_b;
  logic [63:0] writeback_value;
  logic        writeback_enable;
  logic [4:0]  writeback_address;
  logic [63:0] next_program_counter;
  logic        instruction_is_memory;
  logic        instruction_is_store;
  logic        instruction_is_branch;
  logic        branch_taken;
  logic        instruction_is_control_transfer;
  logic [2:0]  memory_function;
  logic [2:0]  memory_width;
  logic        memory_unsigned;
  logic [63:0] effective_address;
  logic [63:0] immediate;
  immediate_kind_t immediate_kind;
  alu_op_t alu_operation;
  logic [63:0] alu_rhs;
  logic [63:0] alu_result;
  logic        decoded_illegal;

  logic [6:0] opcode;
  logic [4:0] rd;
  logic [4:0] rs1;
  logic [4:0] rs2;
  logic [2:0] funct3;

  rv64_regfile register_file (
    .clk(clk),
    .reset(reset),
    .write_enable(writeback_enable && (!instruction_is_memory || data_ready)),
    .write_address(writeback_address),
    .write_data(writeback_value),
    .read_address_a(rs1),
    .read_address_b(rs2),
    .read_data_a(register_a),
    .read_data_b(register_b)
  );

  rv64_decoder decoder (
    .instruction(instruction_data),
    .operation(alu_operation),
    .uses_immediate(),
    .writes_register(),
    .illegal(decoded_illegal)
  );

  rv64_imm_gen immediate_generator (
    .instruction(instruction_data),
    .kind(immediate_kind),
    .immediate(immediate)
  );

  rv64_alu arithmetic_unit (
    .lhs(register_a),
    .rhs(alu_rhs),
    .operation(alu_operation),
    .result(alu_result)
  );

  assign instruction_address = program_counter;

  always_comb begin
    opcode = instruction_data[6:0];
    rd = instruction_data[11:7];
    funct3 = instruction_data[14:12];
    rs1 = instruction_data[19:15];
    rs2 = instruction_data[24:20];

    immediate_kind = IMM_I;
    alu_rhs = register_b;
    writeback_value = alu_result;
    writeback_enable = 1'b0;
    writeback_address = rd;
    next_program_counter = program_counter + 64'd4;
    instruction_is_memory = 1'b0;
    instruction_is_store = 1'b0;
    instruction_is_branch = 1'b0;
    branch_taken = 1'b0;
    instruction_is_control_transfer = 1'b0;
    memory_function = funct3;
    memory_width = 3'd0;
    memory_unsigned = 1'b0;
    effective_address = '0;
    data_valid = 1'b0;
    data_write = 1'b0;
    data_address = '0;
    data_write_data = register_b;
    data_write_strobe = 8'b0;
    illegal_instruction = 1'b1;

    unique case (opcode)
      7'b0110111: begin
        illegal_instruction = 1'b0;
        writeback_enable = 1'b1;
        writeback_value = {{32{instruction_data[31]}}, instruction_data[31:12], 12'b0};
      end
      7'b0010111: begin
        illegal_instruction = 1'b0;
        writeback_enable = 1'b1;
        writeback_value = program_counter + {{32{instruction_data[31]}}, instruction_data[31:12], 12'b0};
      end
      7'b0010011, 7'b0011011, 7'b0110011, 7'b0111011: begin
        illegal_instruction = decoded_illegal;
        writeback_enable = !decoded_illegal;
        if (opcode == 7'b0010011 || opcode == 7'b0011011) begin
          immediate_kind = IMM_I;
          alu_rhs = immediate;
        end
      end
      7'b0000011: begin
        immediate_kind = IMM_I;
        instruction_is_memory = 1'b1;
        effective_address = register_a + immediate;
        illegal_instruction = funct3 == 3'b111;
        data_valid = !illegal_instruction;
        data_address = effective_address;
        memory_unsigned = funct3[2];
        unique case (funct3[1:0])
          2'b00: memory_width = 3'd0;
          2'b01: memory_width = 3'd1;
          2'b10: memory_width = 3'd2;
          2'b11: memory_width = 3'd3;
          default: begin memory_width = 3'd0; illegal_instruction = 1'b1; end
        endcase
        if (funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111) begin
          memory_width = (funct3 == 3'b011) ? 3'd3 : 3'd2;
        end
        writeback_enable = !illegal_instruction;
        if (data_read_data !== 'x) begin
          unique case (memory_width)
            3'd0: writeback_value = memory_unsigned ? {56'b0, data_read_data[7:0]} : {{56{data_read_data[7]}}, data_read_data[7:0]};
            3'd1: writeback_value = memory_unsigned ? {48'b0, data_read_data[15:0]} : {{48{data_read_data[15]}}, data_read_data[15:0]};
            3'd2: writeback_value = memory_unsigned ? {32'b0, data_read_data[31:0]} : {{32{data_read_data[31]}}, data_read_data[31:0]};
            default: writeback_value = data_read_data;
          endcase
        end
      end
      7'b0100011: begin
        immediate_kind = IMM_S;
        instruction_is_memory = 1'b1;
        instruction_is_store = 1'b1;
        effective_address = register_a + immediate;
        illegal_instruction = !((funct3 == 3'b000) || (funct3 == 3'b001) ||
                                 (funct3 == 3'b010) || (funct3 == 3'b011));
        data_valid = !illegal_instruction;
        data_write = data_valid;
        data_address = effective_address;
        unique case (funct3)
          3'b000: begin memory_width = 3'd0; data_write_strobe = 8'b0000_0001; end
          3'b001: begin memory_width = 3'd1; data_write_strobe = 8'b0000_0011; end
          3'b010: begin memory_width = 3'd2; data_write_strobe = 8'b0000_1111; end
          3'b011: begin memory_width = 3'd3; data_write_strobe = 8'b1111_1111; end
          default: begin illegal_instruction = 1'b1; data_valid = 1'b0; data_write = 1'b0; end
        endcase
      end
      7'b1100011: begin
        immediate_kind = IMM_B;
        illegal_instruction = !((funct3 == 3'b000) || (funct3 == 3'b001) ||
                                 (funct3 == 3'b100) || (funct3 == 3'b101) ||
                                 (funct3 == 3'b110) || (funct3 == 3'b111));
        instruction_is_branch = 1'b1;
        unique case (funct3)
          3'b000: branch_taken = register_a == register_b;
          3'b001: branch_taken = register_a != register_b;
          3'b100: branch_taken = $signed(register_a) < $signed(register_b);
          3'b101: branch_taken = $signed(register_a) >= $signed(register_b);
          3'b110: branch_taken = register_a < register_b;
          3'b111: branch_taken = register_a >= register_b;
          default: branch_taken = 1'b0;
        endcase
        if (branch_taken) begin
          next_program_counter = program_counter + immediate;
        end
      end
      7'b1101111: begin
        illegal_instruction = 1'b0;
        immediate_kind = IMM_J;
        writeback_enable = 1'b1;
        writeback_value = program_counter + 64'd4;
        next_program_counter = program_counter + immediate;
        instruction_is_control_transfer = 1'b1;
      end
      7'b1100111: begin
        immediate_kind = IMM_I;
        writeback_enable = funct3 == 3'b000;
        writeback_value = program_counter + 64'd4;
        next_program_counter = (register_a + immediate) & ~64'd1;
        instruction_is_control_transfer = 1'b1;
        illegal_instruction = funct3 != 3'b000;
      end
      default: begin end
    endcase

    if (instruction_is_memory && instruction_is_store) begin
      data_write_data = register_b;
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      program_counter <= '0;
      commit_valid <= 1'b0;
      commit_pc <= '0;
      commit_instruction <= '0;
      commit_rd_write <= 1'b0;
      commit_rd <= '0;
      commit_rd_value <= '0;
    end else begin
      commit_valid <= 1'b0;
      if (!instruction_is_memory || data_ready) begin
        program_counter <= next_program_counter;
        commit_valid <= 1'b1;
        commit_pc <= program_counter;
        commit_instruction <= instruction_data;
        commit_rd_write <= writeback_enable && (writeback_address != 5'd0) && !illegal_instruction;
        commit_rd <= writeback_address;
        commit_rd_value <= writeback_value;
      end
    end
  end
endmodule
