`timescale 1ns / 1ps

module tb_rv64_core_privilege;
  logic clk;
  logic reset;
  logic software_interrupt;
  logic timer_interrupt;
  logic external_interrupt;
  logic [63:0] instruction_address;
  logic [31:0] instruction_data;
  logic instruction_ready;
  logic instruction_fault;
  logic data_valid;
  logic data_write;
  logic [63:0] data_address;
  logic [63:0] data_write_data;
  logic [7:0] data_write_strobe;
  logic [63:0] data_read_data;
  logic data_ready;
  logic data_fault;
  logic commit_valid;
  logic [63:0] commit_pc;
  logic [31:0] commit_instruction;
  logic [63:0] commit_next_pc;
  logic commit_rd_write;
  logic [4:0] commit_rd;
  logic [63:0] commit_rd_value;
  logic commit_csr_write;
  logic [11:0] commit_csr_address;
  logic [63:0] commit_csr_value;
  logic commit_trap_valid;
  logic [63:0] commit_trap_cause;
  logic illegal_instruction;
  logic [1:0] privilege_mode;
  logic [1:0] data_privilege;
  logic [63:0] satp_value;
  logic sum_enable;
  logic mxr_enable;
  logic sfence_valid;
  logic [63:0] sfence_virtual_address;
  logic sfence_all;
  logic fence_i_valid;
  logic atomic_access;
  logic [31:0] instruction_memory [0:63];
  integer failures;
  integer index;
  integer probe_index;
  integer operation_index;
  logic [11:0] probe_address;
  logic [2:0] probe_operation;
  logic [31:0] probe_instruction;

  rv64_core dut (.*);
  always #5 clk = ~clk;
  assign instruction_data = instruction_memory[instruction_address[7:2]];
  assign data_read_data = '0;
  assign data_ready = 1'b1;
  assign data_fault = 1'b0;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    software_interrupt = 1'b0;
    timer_interrupt = 1'b0;
    external_interrupt = 1'b0;
    instruction_ready = 1'b1;
    instruction_fault = 1'b0;
    failures = 0;
    for (index = 0; index < 64; index = index + 1) begin
      instruction_memory[index] = 32'h0000_0013;
    end

    instruction_memory[0] = 32'h0400_0093;
    instruction_memory[1] = 32'h3050_9073;
    instruction_memory[2] = 32'h0000_0093;
    instruction_memory[3] = 32'h3000_9073;
    instruction_memory[4] = 32'h0200_0093;
    instruction_memory[5] = 32'h3410_9073;
    instruction_memory[6] = 32'h3020_0073;
    instruction_memory[8] = 32'h3000_2173;
    instruction_memory[16] = 32'h0090_0193;
    instruction_memory[17] = 32'h0000_006f;

    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (30) begin
      @(posedge clk);
      #1;
    end

    if (privilege_mode !== 2'b11) begin
      $display("FAIL privilege did not return to M-mode: %b", privilege_mode);
      failures = failures + 1;
    end
    if (dut.register_file.registers[3] !== 64'd9) begin
      $display("FAIL illegal CSR trap handler did not run: x3=%h", dut.register_file.registers[3]);
      failures = failures + 1;
    end
    if (dut.csr_file.mcause !== 64'd2 || dut.csr_file.mepc !== 64'd32) begin
      $display("FAIL illegal CSR trap state: mcause=%h mepc=%h", dut.csr_file.mcause, dut.csr_file.mepc);
      failures = failures + 1;
    end
    if (dut.register_file.registers[2] !== 64'd0) begin
      $display("FAIL illegal CSR instruction wrote destination: x2=%h", dut.register_file.registers[2]);
      failures = failures + 1;
    end

    // OpenSBI probes optional extensions by attempting CSR accesses in M-mode.
    // An absent register must trap even when rd=x0 (write-only CSRRW).
    for (probe_index = 0; probe_index < 5; probe_index = probe_index + 1) begin
      case (probe_index)
        0: probe_address = 12'h14d; // stimecmp: Sstc is not implemented
        1: probe_address = 12'hfb0; // mtopi: AIA is not implemented
        2: probe_address = 12'h30c; // mstateen0
        3: probe_address = 12'h7a0; // tselect
        default: probe_address = 12'h5c0; // custom, unimplemented
      endcase
      for (operation_index = 0; operation_index < 8; operation_index = operation_index + 1) begin
        probe_operation = operation_index < 3 ? operation_index + 1 :
                          operation_index < 6 ? operation_index + 2 :
                          operation_index == 6 ? 3'b010 : 3'b110;
        probe_instruction = {probe_address, (operation_index >= 6 ? 5'd0 : 5'd1), probe_operation,
                             (operation_index == 0 ? 5'd0 : 5'd2), 7'h73};
        reset = 1'b1;
        for (index = 0; index < 64; index = index + 1)
          instruction_memory[index] = 32'h0000_0013;
        instruction_memory[0] = 32'h0400_0093; // li x1, 64
        instruction_memory[1] = 32'h3050_9073; // csrw mtvec, x1
        instruction_memory[2] = 32'h0550_0113; // li x2, 85 (must survive trap)
        instruction_memory[3] = probe_instruction;
        instruction_memory[4] = 32'h0000_006f;
        instruction_memory[16] = 32'h0090_0193;
        instruction_memory[17] = 32'h0000_006f;
        @(posedge clk); #1; reset = 1'b0;
        repeat (25) begin @(posedge clk); #1; end
        if (dut.csr_file.mcause !== 64'd2 || dut.csr_file.mepc !== 64'd12 ||
            dut.csr_file.mtval !== {32'b0, probe_instruction} ||
            dut.register_file.registers[2] !== 64'd85 ||
            dut.register_file.registers[3] !== 64'd9) begin
          $display("FAIL absent CSR %h funct3=%h cause=%h epc=%h tval=%h x2=%h",
            probe_address, probe_operation, dut.csr_file.mcause,
            dut.csr_file.mepc, dut.csr_file.mtval, dut.register_file.registers[2]);
          failures = failures + 1;
        end
      end
    end
    if (failures != 0) $fatal(1, "SIM FAIL: %0d privilege checks failed", failures);
    $display("SIM PASS: rv64_core CSR privilege checks");
    $finish;
  end
endmodule
