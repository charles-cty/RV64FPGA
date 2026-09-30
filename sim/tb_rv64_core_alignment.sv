`timescale 1ns / 1ps

module tb_rv64_core_alignment;
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
  logic [63:0] data_memory [0:7];
  integer failures;
  integer index;
  integer byte_index;

  rv64_core dut (.*);
  always #5 clk = ~clk;
  assign instruction_data = instruction_memory[instruction_address[6:2]];
  assign data_read_data = data_memory[data_address[5:3]];
  assign data_ready = 1'b1;

  always_ff @(posedge clk) begin
    if (data_valid && data_write) begin
      for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
        if (data_write_strobe[byte_index]) begin
          data_memory[data_address[5:3]][byte_index*8 +: 8] <=
            data_write_data[byte_index*8 +: 8];
        end
      end
    end
  end

  task automatic initialize_program(input logic [1:0] test_kind);
    begin
      for (index = 0; index < 32; index = index + 1) begin
        instruction_memory[index] = 32'h0000_0013;
      end
      for (index = 0; index < 8; index = index + 1) begin
        data_memory[index] = '0;
      end
      instruction_memory[0] = 32'h0400_0093; // addi x1, x0, 64
      instruction_memory[1] = 32'h3050_9073; // csrrw x0, mtvec, x1
      instruction_memory[2] = test_kind == 2'd0 ? 32'h0010_0113 : 32'h0020_0113;
      if (test_kind == 2'd1) begin
        instruction_memory[3] = 32'h0070_0193; // addi x3, x0, 7
        instruction_memory[4] = 32'h0031_2023; // sw x3, 0(x2)
      end else if (test_kind == 2'd2) begin
        instruction_memory[3] = 32'h1001_21af; // lr.w x3, (x2)
      end else if (test_kind == 2'd3) begin
        instruction_memory[3] = 32'h0070_0213; // addi x4, x0, 7
        instruction_memory[4] = 32'h0041_21af; // amoadd.w x3, x4, (x2)
      end else begin
        instruction_memory[3] = 32'h0001_2183; // lw x3, 0(x2)
      end
      instruction_memory[16] = 32'h0000_006f; // handler loop
    end
  endtask

  task automatic expect_fault(
    input logic [63:0] expected_cause,
    input logic [63:0] expected_value,
    input logic [63:0] expected_pc,
    input logic [63:0] expected_register_value
  );
    begin
      if (dut.csr_file.mcause !== expected_cause || dut.csr_file.mtval !== expected_value ||
          dut.csr_file.mepc !== expected_pc || dut.instruction_address !== 64'h40) begin
        $display("FAIL alignment trap mcause=%h mtval=%h mepc=%h pc=%h",
                 dut.csr_file.mcause, dut.csr_file.mtval, dut.csr_file.mepc,
                 dut.instruction_address);
        failures = failures + 1;
      end
      if (dut.register_file.registers[3] !== expected_register_value ||
          data_memory[0] !== 64'b0) begin
        $display("FAIL alignment side effect x3=%h memory=%h",
                 dut.register_file.registers[3], data_memory[0]);
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
    data_fault = 1'b0;
    failures = 0;
    initialize_program(2'd0);
    data_fault = 1'b1;

    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (12) @(posedge clk);
    #1;
    expect_fault(64'd4, 64'd1, 64'd12, 64'b0);

    @(negedge clk);
    reset = 1'b1;
    data_fault = 1'b0;
    initialize_program(2'd1);
    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (14) @(posedge clk);
    #1;
    expect_fault(64'd6, 64'd2, 64'd16, 64'd7);

    @(negedge clk);
    reset = 1'b1;
    initialize_program(2'd2);
    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (12) @(posedge clk);
    #1;
    expect_fault(64'd4, 64'd2, 64'd12, 64'b0);
    if (dut.atomic_unit.reservation_valid !== 1'b0) begin
      $display("FAIL misaligned lr.w created a reservation");
      failures = failures + 1;
    end

    @(negedge clk);
    reset = 1'b1;
    initialize_program(2'd3);
    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (14) @(posedge clk);
    #1;
    expect_fault(64'd6, 64'd2, 64'd16, 64'b0);

    if (failures != 0) begin
      $display("SIM FAIL: %0d core alignment checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_core misaligned load/store regression");
    $finish;
  end
endmodule
