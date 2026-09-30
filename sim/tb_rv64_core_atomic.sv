`timescale 1ns / 1ps

module tb_rv64_core_atomic;
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
  logic [31:0] instruction_memory [0:31];
  logic [63:0] data_memory [0:15];
  integer failures;
  integer index;
  integer byte_index;
  integer atomic_index;
  integer width_index;
  logic [4:0] fault_operation;
  logic inject_page_fault;

  rv64_core dut (.*);
  always #5 clk = ~clk;
  assign instruction_data = instruction_memory[instruction_address[6:2]];
  assign data_read_data = data_memory[data_address[6:3]];
  assign data_ready = 1'b1;
  assign data_fault = inject_page_fault && data_valid;

  always_ff @(posedge clk) begin
    if (data_valid && data_write && !data_fault) begin
      for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
        if (data_write_strobe[byte_index]) begin
          data_memory[data_address[6:3]][byte_index*8 +: 8] <= data_write_data[byte_index*8 +: 8];
        end
      end
    end
  end

  task automatic check_page_fault(input logic [31:0] opcode,
                                  input logic [63:0] expected_cause);
    integer cycles;
    begin
      @(negedge clk);
      reset = 1'b1;
      inject_page_fault = 1'b1;
      instruction_memory[0] = opcode;
      repeat (2) @(posedge clk);
      @(negedge clk);
      reset = 1'b0;
      cycles = 0;
      while (!(commit_valid && commit_trap_valid) && cycles < 20) begin
        @(posedge clk);
        #1;
        cycles = cycles + 1;
      end
      if (!(commit_valid && commit_trap_valid) ||
          commit_trap_cause !== expected_cause || commit_rd_write ||
          dut.csr_file.mtval !== 64'd0) begin
        $display("FAIL atomic page fault opcode=%h cause=%h expected=%h cycles=%0d",
                 opcode, commit_trap_cause, expected_cause, cycles);
        failures = failures + 1;
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    software_interrupt = 1'b0;
    timer_interrupt = 1'b0;
    external_interrupt = 1'b0;
    instruction_ready = 1'b1;
    instruction_fault = 1'b0;
    inject_page_fault = 1'b0;
    failures = 0;
    for (index = 0; index < 32; index = index + 1) begin
      instruction_memory[index] = 32'h0000_0013;
    end
    for (index = 0; index < 16; index = index + 1) begin
      data_memory[index] = '0;
    end

    instruction_memory[0] = 32'h0050_0093; // addi x1, x0, 5
    instruction_memory[1] = 32'h1000_212f; // lr.w x2, (x0)
    instruction_memory[2] = 32'h1810_21af; // sc.w x3, x1, (x0)
    instruction_memory[3] = 32'h1000_22af; // lr.w x5, (x0)
    instruction_memory[4] = 32'h0010_22af; // amoadd.w x5, x1, (x0)

    data_memory[0] = 64'd10;
    @(posedge clk);
    #1;
    reset = 1'b0;
    fork
      begin
        // A completed SC must retain its reservation until the instruction can retire.
        wait (instruction_address == 64'd8 && dut.memory_pending);
        instruction_ready = 1'b0;
        @(posedge clk);
        #1;
        instruction_ready = 1'b1;
      end
    join_none
    repeat (12) @(posedge clk);
    #1;

    if (dut.register_file.registers[2] !== 64'd10) begin
      $display("FAIL lr.w old value: got=%h expected=10", dut.register_file.registers[2]);
      failures = failures + 1;
    end
    if (dut.register_file.registers[3] !== 64'd0) begin
      $display("FAIL sc.w success result: got=%h expected=0", dut.register_file.registers[3]);
      failures = failures + 1;
    end
    if (dut.register_file.registers[5] !== 64'd5) begin
      $display("FAIL amoadd.w old value: got=%h expected=5", dut.register_file.registers[5]);
      failures = failures + 1;
    end
    if (data_memory[0] !== 64'd10) begin
      $display("FAIL atomic memory result: got=%h expected=10", data_memory[0]);
      failures = failures + 1;
    end

    // All supported LR/SC/AMO operations, in both W and D widths. A fault
    // supplied by memory must retain the access type even for failed SC.
    for (atomic_index = 0; atomic_index < 11; atomic_index = atomic_index + 1) begin
      case (atomic_index)
        0: fault_operation = 5'b00010; // LR
        1: fault_operation = 5'b00011; // SC
        2: fault_operation = 5'b00001; // SWAP
        3: fault_operation = 5'b00000; // ADD
        4: fault_operation = 5'b00100; // XOR
        5: fault_operation = 5'b01100; // AND
        6: fault_operation = 5'b01000; // OR
        7: fault_operation = 5'b10000; // MIN
        8: fault_operation = 5'b10100; // MAX
        9: fault_operation = 5'b11000; // MINU
        default: fault_operation = 5'b11100; // MAXU
      endcase
      for (width_index = 0; width_index < 2; width_index = width_index + 1)
        check_page_fault({fault_operation, 2'b11, 5'd0, 5'd0,
                          (width_index == 0 ? 3'b010 : 3'b011), 5'd2, 7'b0101111},
                         atomic_index == 0 ? 64'd13 : 64'd15);
    end

    if (failures != 0) begin
      $display("SIM FAIL: %0d core atomic checks failed", failures);
      $fatal(1);
    end else begin
      $display("SIM PASS: rv64_core atomic BRAM regression");
    end
    $finish;
  end
endmodule
