module rv64_core (
  input  logic        clk,
  input  logic        reset,
  input  logic        software_interrupt,
  input  logic        timer_interrupt,
  input  logic        external_interrupt,
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
  output logic [63:0] commit_next_pc,
  output logic        commit_rd_write,
  output logic [4:0]  commit_rd,
  output logic [63:0] commit_rd_value,
  output logic        commit_csr_write,
  output logic [11:0] commit_csr_address,
  output logic [63:0] commit_csr_value,
  output logic        commit_trap_valid,
  output logic [63:0] commit_trap_cause,
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
  logic [11:0] csr_read_address;
  logic [63:0] csr_read_data;
  logic        csr_write_enable;
  logic [11:0] csr_write_address;
  logic [63:0] csr_write_value;
  logic        return_from_machine;
  logic        trap_to_machine;
  logic [63:0] trap_cause;
  logic        system_instruction;
  logic        interrupt_pending;
  logic        machine_interrupt_enable;
  logic [63:0] machine_interrupt_enable_bits;
  logic [63:0] machine_interrupt_pending_bits;
  logic [63:0] machine_trap_vector;
  logic [63:0] machine_exception_pc;
  logic        atomic_instruction;
  logic        atomic_word_operation;
  logic        atomic_valid;
  logic        atomic_memory_write;
  logic [63:0] atomic_memory_write_data;
  logic [63:0] atomic_result;
  atomic_op_t  atomic_operation;

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

  rv64_csr csr_file (
    .clk(clk),
    .reset(reset),
    .read_address(csr_read_address),
    .read_data(csr_read_data),
    .write_enable(csr_write_enable),
    .write_address(csr_write_address),
    .write_data(csr_write_value),
    .trap_to_machine(trap_to_machine),
    .trap_pc(program_counter),
    .trap_cause(trap_cause),
    .trap_value({32'b0, instruction_data}),
    .current_privilege(2'b11),
    .return_from_machine(return_from_machine),
    .software_interrupt(software_interrupt),
    .timer_interrupt(timer_interrupt),
    .external_interrupt(external_interrupt),
    .machine_interrupt_enable(machine_interrupt_enable),
    .machine_interrupt_enable_bits(machine_interrupt_enable_bits),
    .machine_interrupt_pending_bits(machine_interrupt_pending_bits),
    .machine_trap_vector(machine_trap_vector),
    .machine_exception_pc(machine_exception_pc)
  );

  rv64_atomic_unit atomic_unit (
    .clk(clk),
    .reset(reset),
    .execute(atomic_valid),
    .operation(atomic_operation),
    .word_operation(atomic_word_operation),
    .address(register_a),
    .source_data(register_b),
    .memory_read_data(data_read_data),
    .memory_ready(data_ready),
    .memory_valid(),
    .memory_write(atomic_memory_write),
    .memory_write_data(atomic_memory_write_data),
    .result(atomic_result),
    .sc_success()
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
    system_instruction = opcode == 7'b1110011;
    atomic_instruction = opcode == 7'b0101111;
    atomic_word_operation = funct3 == 3'b010;
    atomic_operation = ATOMIC_LR;
    atomic_valid = 1'b0;
    csr_read_address = 12'h305;
    csr_write_enable = 1'b0;
    csr_write_address = instruction_data[31:20];
    csr_write_value = '0;
    return_from_machine = 1'b0;
    trap_to_machine = 1'b0;
    trap_cause = 64'd2;
    interrupt_pending = machine_interrupt_enable &&
      ((machine_interrupt_enable_bits[3] && machine_interrupt_pending_bits[3]) ||
       (machine_interrupt_enable_bits[7] && machine_interrupt_pending_bits[7]) ||
       (machine_interrupt_enable_bits[11] && machine_interrupt_pending_bits[11]));
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
      7'b0101111: begin
        instruction_is_memory = 1'b1;
        illegal_instruction = !((funct3 == 3'b010) || (funct3 == 3'b011));
        unique case (instruction_data[31:27])
          5'b00010: atomic_operation = ATOMIC_LR;
          5'b00011: atomic_operation = ATOMIC_SC;
          5'b00001: atomic_operation = ATOMIC_SWAP;
          5'b00000: atomic_operation = ATOMIC_ADD;
          5'b00100: atomic_operation = ATOMIC_XOR;
          5'b01100: atomic_operation = ATOMIC_AND;
          5'b01000: atomic_operation = ATOMIC_OR;
          5'b10000: atomic_operation = ATOMIC_MIN;
          5'b10100: atomic_operation = ATOMIC_MAX;
          5'b11000: atomic_operation = ATOMIC_MINU;
          5'b11100: atomic_operation = ATOMIC_MAXU;
          default: illegal_instruction = 1'b1;
        endcase
        atomic_valid = !illegal_instruction;
        data_valid = atomic_valid;
        data_write = atomic_memory_write;
        data_address = register_a;
        data_write_data = atomic_memory_write_data;
        data_write_strobe = atomic_word_operation ? 8'b0000_1111 : 8'b1111_1111;
        writeback_enable = atomic_valid;
        writeback_value = atomic_result;
        writeback_address = rd;
      end
      7'b1110011: begin
        if (instruction_data == 32'h3020_0073) begin
          illegal_instruction = 1'b0;
          return_from_machine = 1'b1;
          csr_read_address = 12'h341;
          next_program_counter = csr_read_data;
        end else if (instruction_data == 32'h0000_0073) begin
          illegal_instruction = 1'b0;
          trap_to_machine = 1'b1;
          trap_cause = 64'd11;
          csr_read_address = 12'h305;
          next_program_counter = csr_read_data;
        end else if ((funct3 >= 3'b001) && (funct3 <= 3'b011)) begin
          illegal_instruction = 1'b0;
          writeback_enable = 1'b1;
          csr_read_address = instruction_data[31:20];
          writeback_value = csr_read_data;
          csr_write_enable = rs1 != 5'd0 || funct3 == 3'b001;
          if (funct3 == 3'b001) begin
            csr_write_value = register_a;
          end else if (funct3 == 3'b010) begin
            csr_write_value = csr_read_data | register_a;
          end else begin
            csr_write_value = csr_read_data & ~register_a;
          end
        end else if ((funct3 >= 3'b101) && (funct3 <= 3'b111)) begin
          illegal_instruction = 1'b0;
          writeback_enable = 1'b1;
          csr_read_address = instruction_data[31:20];
          writeback_value = csr_read_data;
          csr_write_enable = rs1 != 5'd0 || funct3 == 3'b101;
          if (funct3 == 3'b101) begin
            csr_write_value = {59'b0, rs1};
          end else if (funct3 == 3'b110) begin
            csr_write_value = csr_read_data | {59'b0, rs1};
          end else begin
            csr_write_value = csr_read_data & ~{59'b0, rs1};
          end
        end
      end
      default: begin end
    endcase

    if (illegal_instruction) begin
      trap_to_machine = 1'b1;
      csr_read_address = 12'h305;
    end

    if (interrupt_pending) begin
      trap_to_machine = 1'b1;
      illegal_instruction = 1'b0;
      writeback_enable = 1'b0;
      csr_write_enable = 1'b0;
      data_valid = 1'b0;
      csr_read_address = 12'h305;
      next_program_counter = machine_trap_vector;
      if (machine_interrupt_pending_bits[11] && machine_interrupt_enable_bits[11]) begin
        trap_cause = 64'h8000_0000_0000_000b;
      end else if (machine_interrupt_pending_bits[7] && machine_interrupt_enable_bits[7]) begin
        trap_cause = 64'h8000_0000_0000_0007;
      end else begin
        trap_cause = 64'h8000_0000_0000_0003;
      end
    end

    if (instruction_is_memory && instruction_is_store && !atomic_instruction) begin
      data_write_data = register_b;
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      program_counter <= '0;
      commit_valid <= 1'b0;
      commit_pc <= '0;
      commit_instruction <= '0;
      commit_next_pc <= '0;
      commit_rd_write <= 1'b0;
      commit_rd <= '0;
      commit_rd_value <= '0;
      commit_csr_write <= 1'b0;
      commit_csr_address <= '0;
      commit_csr_value <= '0;
      commit_trap_valid <= 1'b0;
      commit_trap_cause <= '0;
    end else begin
      commit_valid <= 1'b0;
      if (!instruction_is_memory || data_ready) begin
        program_counter <= next_program_counter;
        commit_valid <= 1'b1;
        commit_pc <= program_counter;
        commit_instruction <= instruction_data;
        commit_next_pc <= next_program_counter;
        commit_rd_write <= writeback_enable && (writeback_address != 5'd0) && !illegal_instruction;
        commit_rd <= writeback_address;
        commit_rd_value <= writeback_value;
        commit_csr_write <= csr_write_enable;
        commit_csr_address <= csr_write_address;
        commit_csr_value <= csr_write_value;
        commit_trap_valid <= trap_to_machine;
        commit_trap_cause <= trap_cause;
      end
    end
  end
endmodule
