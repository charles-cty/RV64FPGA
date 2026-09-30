module rv64_core (
  input  logic        clk,
  input  logic        reset,
  input  logic        software_interrupt,
  input  logic        timer_interrupt,
    input  logic        external_interrupt,
    output logic [63:0] instruction_address,
    input  logic [31:0] instruction_data,
    input  logic        instruction_ready,
    input  logic        instruction_fault,
  output logic        data_valid,
  output logic        data_write,
  output logic [63:0] data_address,
  output logic [63:0] data_write_data,
  output logic [7:0]  data_write_strobe,
  input  logic [63:0] data_read_data,
  input  logic        data_ready,
  input  logic        data_fault,
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
    output logic        illegal_instruction,
    output logic [1:0]  privilege_mode,
    output logic [1:0]  data_privilege,
    output logic [63:0] satp_value,
    output logic        sum_enable,
    output logic        mxr_enable,
    output logic        sfence_valid,
    output logic [63:0] sfence_virtual_address,
    output logic        sfence_all,
    output logic        fence_i_valid,
    output logic        atomic_access
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
  logic        memory_misaligned;
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
  logic        return_from_supervisor;
  logic        trap_to_machine;
  logic [63:0] trap_cause;
  logic [63:0] trap_value;
  logic        system_instruction;
  logic        interrupt_pending;
  logic        machine_interrupt_enable;
  logic [63:0] machine_interrupt_enable_bits;
  logic [63:0] machine_interrupt_pending_bits;
  logic [63:0] interrupt_delegation_bits;
  logic        supervisor_interrupt_enable;
  logic [63:0] supervisor_interrupt_enable_bits;
  logic [63:0] supervisor_interrupt_pending_bits;
  logic        machine_interrupt_pending;
  logic        supervisor_interrupt_pending;
  logic [63:0] interrupt_cause;
  logic [63:0] machine_trap_vector;
  logic [63:0] machine_exception_pc;
  logic [63:0] trap_vector;
  logic [63:0] trap_exception_pc;
  logic trap_delegated;
  logic        csr_access_illegal;
  logic        csr_write_attempt;
  logic        atomic_instruction;
  logic        atomic_word_operation;
  logic        atomic_valid;
  logic        atomic_memory_write;
  logic [63:0] atomic_memory_write_data;
  logic [63:0] atomic_result;
  atomic_op_t  atomic_operation;
  logic        instruction_commit;
  logic        division_operation;
  logic        division_signed;
  logic        division_remainder;
  logic        division_word;
  logic        divider_start;
  logic        divider_busy;
  logic        divider_result_valid;
  logic [63:0] divider_result;
  logic        memory_pending;
  logic        pending_atomic_access;
  logic        pending_data_write;
  logic [63:0] pending_data_address;
  logic [63:0] pending_data_write_data;
  logic [7:0]  pending_data_write_strobe;
  logic        decoded_data_write;
  logic [63:0] decoded_data_address;
  logic [63:0] decoded_data_write_data;
  logic [7:0]  decoded_data_write_strobe;
  logic        memory_request_start;

  assign atomic_access = memory_pending && pending_atomic_access;
  assign instruction_commit = instruction_ready &&
                            (!instruction_is_memory || (memory_pending && data_ready) || trap_to_machine) &&
                            (!division_operation || divider_result_valid || trap_to_machine);
  assign division_operation = (alu_operation == ALU_DIV) || (alu_operation == ALU_DIVU) ||
                              (alu_operation == ALU_REM) || (alu_operation == ALU_REMU) ||
                              (alu_operation == ALU_DIVW) || (alu_operation == ALU_DIVUW) ||
                              (alu_operation == ALU_REMW) || (alu_operation == ALU_REMUW);
  assign division_signed = (alu_operation == ALU_DIV) || (alu_operation == ALU_REM) ||
                           (alu_operation == ALU_DIVW) || (alu_operation == ALU_REMW);
  assign division_remainder = (alu_operation == ALU_REM) || (alu_operation == ALU_REMU) ||
                              (alu_operation == ALU_REMW) || (alu_operation == ALU_REMUW);
  assign division_word = (alu_operation == ALU_DIVW) || (alu_operation == ALU_DIVUW) ||
                         (alu_operation == ALU_REMW) || (alu_operation == ALU_REMUW);
  assign divider_start = instruction_ready && division_operation && !illegal_instruction &&
                         !trap_to_machine && !divider_busy && !divider_result_valid;
  assign memory_request_start = instruction_ready && instruction_is_memory && !memory_pending &&
                                !illegal_instruction && !memory_misaligned && !instruction_fault &&
                                !interrupt_pending && !trap_to_machine;

  logic [6:0] opcode;
  logic [4:0] rd;
  logic [4:0] rs1;
  logic [4:0] rs2;
  logic [2:0] funct3;

  rv64_regfile register_file (
    .clk(clk),
    .reset(reset),
    .write_enable(writeback_enable && instruction_commit),
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

  rv64_alu #(.ITERATIVE_DIVIDE(1'b1)) arithmetic_unit (
    .lhs(register_a),
    .rhs(alu_rhs),
    .operation(alu_operation),
    .result(alu_result)
  );

  rv64_divider divider (
    .clk(clk),
    .reset(reset),
    .start(divider_start),
    .result_consumed(instruction_commit && division_operation),
    .signed_operation(division_signed),
    .remainder_operation(division_remainder),
    .word_operation(division_word),
    .dividend(register_a),
    .divisor(register_b),
    .busy(divider_busy),
    .result_valid(divider_result_valid),
    .result(divider_result)
  );

  rv64_csr csr_file (
    .clk(clk),
    .reset(reset),
    .read_address(csr_read_address),
    .read_data(csr_read_data),
    .write_enable(csr_write_enable && instruction_commit),
    .write_address(csr_write_address),
    .write_data(csr_write_value),
    .trap_to_machine(trap_to_machine && instruction_commit),
    .trap_pc(program_counter),
    .trap_cause(trap_cause),
    .trap_value(trap_value),
    .current_privilege(privilege_mode),
    .return_from_machine(return_from_machine && instruction_commit),
    .return_from_supervisor(return_from_supervisor && instruction_commit),
    .software_interrupt(software_interrupt),
    .timer_interrupt(timer_interrupt),
    .external_interrupt(external_interrupt),
    .machine_interrupt_enable(machine_interrupt_enable),
    .machine_interrupt_enable_bits(machine_interrupt_enable_bits),
    .machine_interrupt_pending_bits(machine_interrupt_pending_bits),
    .interrupt_delegation_bits(interrupt_delegation_bits),
    .supervisor_interrupt_enable(supervisor_interrupt_enable),
    .supervisor_interrupt_enable_bits(supervisor_interrupt_enable_bits),
    .supervisor_interrupt_pending_bits(supervisor_interrupt_pending_bits),
    .machine_trap_vector(machine_trap_vector),
    .machine_exception_pc(machine_exception_pc),
    .privilege_mode(privilege_mode),
    .data_privilege(data_privilege),
    .satp_value(satp_value),
    .sum_enable(sum_enable),
    .mxr_enable(mxr_enable),
    .trap_vector(trap_vector),
    .trap_exception_pc(trap_exception_pc),
    .trap_delegated(trap_delegated)
  );

  rv64_atomic_unit atomic_unit (
    .clk(clk),
    .reset(reset),
    .execute(atomic_valid && memory_pending),
    .operation(atomic_operation),
    .word_operation(atomic_word_operation),
    .address(register_a),
    .source_data(register_b),
    .memory_read_data(data_read_data),
    .memory_ready(instruction_commit && !trap_to_machine),
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
    return_from_supervisor = 1'b0;
    trap_to_machine = 1'b0;
    trap_cause = 64'd2;
    trap_value = {32'b0, instruction_data};
    // A higher-privilege interrupt is globally enabled while lower-privilege
    // code runs, regardless of that higher level's xIE bit.  At the same
    // privilege level xIE applies.  Machine interrupts take precedence over
    // supervisor interrupts.
    machine_interrupt_pending = ((privilege_mode != 2'b11) || machine_interrupt_enable) &&
      (((machine_interrupt_enable_bits[11] && machine_interrupt_pending_bits[11]) && !interrupt_delegation_bits[11]) ||
       ((machine_interrupt_enable_bits[3] && machine_interrupt_pending_bits[3]) && !interrupt_delegation_bits[3]) ||
       ((machine_interrupt_enable_bits[7] && machine_interrupt_pending_bits[7]) && !interrupt_delegation_bits[7]) ||
       ((machine_interrupt_enable_bits[9] && machine_interrupt_pending_bits[9]) && !interrupt_delegation_bits[9]) ||
       ((machine_interrupt_enable_bits[1] && machine_interrupt_pending_bits[1]) && !interrupt_delegation_bits[1]) ||
       ((machine_interrupt_enable_bits[5] && machine_interrupt_pending_bits[5]) && !interrupt_delegation_bits[5]));
    supervisor_interrupt_pending = (privilege_mode != 2'b11) &&
      ((privilege_mode == 2'b00) || supervisor_interrupt_enable) &&
      (((supervisor_interrupt_enable_bits[9] && supervisor_interrupt_pending_bits[9])) ||
       ((supervisor_interrupt_enable_bits[1] && supervisor_interrupt_pending_bits[1])) ||
       ((supervisor_interrupt_enable_bits[5] && supervisor_interrupt_pending_bits[5])));
    interrupt_pending = machine_interrupt_pending || supervisor_interrupt_pending;
    interrupt_cause = 64'h8000_0000_0000_0005;
    if (machine_interrupt_pending) begin
      if (machine_interrupt_enable_bits[11] && machine_interrupt_pending_bits[11] && !interrupt_delegation_bits[11])
        interrupt_cause = 64'h8000_0000_0000_000b;
      else if (machine_interrupt_enable_bits[3] && machine_interrupt_pending_bits[3] && !interrupt_delegation_bits[3])
        interrupt_cause = 64'h8000_0000_0000_0003;
      else if (machine_interrupt_enable_bits[7] && machine_interrupt_pending_bits[7] && !interrupt_delegation_bits[7])
        interrupt_cause = 64'h8000_0000_0000_0007;
      else if (machine_interrupt_enable_bits[9] && machine_interrupt_pending_bits[9] && !interrupt_delegation_bits[9])
        interrupt_cause = 64'h8000_0000_0000_0009;
      else if (machine_interrupt_enable_bits[1] && machine_interrupt_pending_bits[1] && !interrupt_delegation_bits[1])
        interrupt_cause = 64'h8000_0000_0000_0001;
    end else if (supervisor_interrupt_pending) begin
      if (supervisor_interrupt_enable_bits[9] && supervisor_interrupt_pending_bits[9])
        interrupt_cause = 64'h8000_0000_0000_0009;
      else if (supervisor_interrupt_enable_bits[1] && supervisor_interrupt_pending_bits[1])
        interrupt_cause = 64'h8000_0000_0000_0001;
    end
    next_program_counter = program_counter + 64'd4;
    instruction_is_memory = 1'b0;
    instruction_is_store = 1'b0;
    instruction_is_branch = 1'b0;
    branch_taken = 1'b0;
    instruction_is_control_transfer = 1'b0;
    memory_function = funct3;
    memory_width = 3'd0;
    memory_unsigned = 1'b0;
    memory_misaligned = 1'b0;
    effective_address = '0;
    data_valid = 1'b0;
    data_write = 1'b0;
    data_address = '0;
    data_write_data = register_b;
    data_write_strobe = 8'b0;
    illegal_instruction = 1'b1;
    sfence_valid = 1'b0;
    sfence_virtual_address = register_a;
    sfence_all = 1'b0;
    fence_i_valid = 1'b0;
    csr_write_attempt = (funct3 == 3'b001) ||
                        ((funct3 == 3'b010 || funct3 == 3'b011) && rs1 != 5'd0) ||
                        (funct3 == 3'b101) ||
                        ((funct3 == 3'b110 || funct3 == 3'b111) && rs1 != 5'd0);
    csr_access_illegal = !csr_implemented(instruction_data[31:20]) ||
                         (privilege_mode < instruction_data[29:28]) ||
                         (instruction_data[29:28] == 2'b10) ||
                         (csr_write_attempt && instruction_data[31:30] == 2'b11);

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
        effective_address = register_a;
        data_write_data = atomic_memory_write_data;
        data_write_strobe = atomic_word_operation ? 8'b0000_1111 : 8'b1111_1111;
        writeback_enable = atomic_valid;
        writeback_value = atomic_result;
        writeback_address = rd;
      end
      7'b0001111: begin
        illegal_instruction = (funct3 != 3'b000) && (funct3 != 3'b001);
        fence_i_valid = funct3 == 3'b001 && !illegal_instruction;
      end
      7'b1110011: begin
        if ((instruction_data[31:25] == 7'b0001001) &&
            (funct3 == 3'b000)) begin
          if (privilege_mode != 2'b00) begin
            illegal_instruction = 1'b0;
            sfence_valid = 1'b1;
            sfence_all = rs1 == 5'd0;
          end
        end else if (instruction_data == 32'h3020_0073) begin
          if (privilege_mode == 2'b11) begin
            illegal_instruction = 1'b0;
            return_from_machine = 1'b1;
            csr_read_address = 12'h341;
            next_program_counter = csr_read_data;
          end
        end else if (instruction_data == 32'h1020_0073) begin
          if (privilege_mode != 2'b00) begin
            illegal_instruction = 1'b0;
            return_from_supervisor = 1'b1;
            csr_read_address = 12'h141;
            next_program_counter = csr_read_data;
          end
        end else if (instruction_data == 32'h1050_0073) begin
          illegal_instruction = 1'b0;
        end else if (instruction_data == 32'h0010_0073) begin
          // EBREAK is a synchronous breakpoint exception (cause 3).  It is
          // used by OpenSBI's semihosting probe; treating it as an illegal
          // instruction leaves the probe at the same PC forever because the
          // supervisor trap handler only handles the breakpoint cause.
          illegal_instruction = 1'b0;
          trap_to_machine = 1'b1;
          trap_cause = 64'd3;
          next_program_counter = trap_vector;
        end else if (instruction_data == 32'h0000_0073) begin
          illegal_instruction = 1'b0;
          trap_to_machine = 1'b1;
          trap_cause = privilege_mode == 2'b11 ? 64'd11 :
                       (privilege_mode == 2'b01 ? 64'd9 : 64'd8);
          next_program_counter = trap_vector;
        end else if ((funct3 >= 3'b001) && (funct3 <= 3'b011)) begin
          if (!csr_access_illegal) begin
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
          end
        end else if ((funct3 >= 3'b101) && (funct3 <= 3'b111)) begin
          if (!csr_access_illegal) begin
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
      end
      default: begin end
    endcase

    if (illegal_instruction) begin
      trap_to_machine = 1'b1;
      next_program_counter = trap_vector;
    end

    if (instruction_is_memory && !illegal_instruction) begin
      if (atomic_instruction) begin
        memory_misaligned = atomic_word_operation ? (effective_address[1:0] != 2'b0) :
                                                  (effective_address[2:0] != 3'b0);
      end else begin
        unique case (memory_width)
          3'd0: memory_misaligned = 1'b0;
          3'd1: memory_misaligned = effective_address[0] != 1'b0;
          3'd2: memory_misaligned = effective_address[1:0] != 2'b0;
          default: memory_misaligned = effective_address[2:0] != 3'b0;
        endcase
      end
      if (memory_misaligned) begin
        trap_to_machine = 1'b1;
        writeback_enable = 1'b0;
        data_valid = 1'b0;
        data_write = 1'b0;
        trap_cause = (instruction_is_store ||
                      (atomic_instruction && atomic_operation != ATOMIC_LR)) ? 64'd6 : 64'd4;
        trap_value = effective_address;
        next_program_counter = trap_vector;
      end
    end

    if (instruction_fault) begin
      trap_to_machine = 1'b1;
      illegal_instruction = 1'b0;
      writeback_enable = 1'b0;
      data_valid = 1'b0;
      trap_cause = 64'd12;
      trap_value = program_counter;
      next_program_counter = trap_vector;
    end

    if (data_fault && instruction_is_memory && !memory_misaligned) begin
      trap_to_machine = 1'b1;
      illegal_instruction = 1'b0;
      writeback_enable = 1'b0;
      // SC and read-modify-write AMOs need store fault handling (including
      // Linux COW). Only LR reports a load page fault among atomic opcodes.
      trap_cause = (instruction_is_store ||
                    (atomic_instruction && atomic_operation != ATOMIC_LR)) ? 64'd15 : 64'd13;
      trap_value = effective_address;
      next_program_counter = trap_vector;
    end

    if (interrupt_pending && !trap_to_machine && !memory_pending) begin
      trap_to_machine = 1'b1;
      illegal_instruction = 1'b0;
      writeback_enable = 1'b0;
      csr_write_enable = 1'b0;
      data_valid = 1'b0;
      next_program_counter = trap_vector;
      trap_cause = interrupt_cause;
    end

    if (instruction_is_memory && instruction_is_store && !atomic_instruction) begin
      data_write_data = register_b;
    end

    if (division_operation) begin
      writeback_value = divider_result;
    end

    decoded_data_write = data_write;
    decoded_data_address = data_address;
    decoded_data_write_data = data_write_data;
    decoded_data_write_strobe = data_write_strobe;
    data_valid = memory_pending;
    data_write = memory_pending ?
                 (pending_atomic_access ? atomic_memory_write : pending_data_write) : 1'b0;
    data_address = pending_data_address;
    data_write_data = pending_atomic_access ? atomic_memory_write_data : pending_data_write_data;
    data_write_strobe = pending_data_write_strobe;
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
      memory_pending <= 1'b0;
      pending_atomic_access <= 1'b0;
      pending_data_write <= 1'b0;
      pending_data_address <= '0;
      pending_data_write_data <= '0;
      pending_data_write_strobe <= '0;
    end else begin
      commit_valid <= 1'b0;
      if (memory_pending) begin
        if (instruction_commit) begin
          memory_pending <= 1'b0;
        end
      end else if (memory_request_start) begin
        memory_pending <= 1'b1;
        pending_atomic_access <= atomic_instruction;
        pending_data_write <= decoded_data_write;
        pending_data_address <= decoded_data_address;
        pending_data_write_data <= decoded_data_write_data;
        pending_data_write_strobe <= decoded_data_write_strobe;
      end
      if (instruction_commit) begin
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
