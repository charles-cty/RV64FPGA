`timescale 1ns / 1ps

module tb_rv64_core_random;
  localparam integer PROGRAM_LENGTH = 96;
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
  logic [31:0] instruction_memory [0:127];
  logic [63:0] data_memory [0:15];
  integer trace_file;
  integer failures;
  integer instruction_index;
  integer byte_index;
  integer commit_count;
  integer cycle_count;

  rv64_core dut (.*);
  always #5 clk = ~clk;
  assign instruction_data = instruction_memory[instruction_address[8:2]];
  assign data_read_data = data_memory[data_address[6:3]];
  assign data_ready = 1'b1;

  always_ff @(posedge clk) begin
    if (data_valid && data_write) begin
      for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
        if (data_write_strobe[byte_index]) begin
          data_memory[data_address[6:3]][byte_index*8 +: 8] <= data_write_data[byte_index*8 +: 8];
        end
      end
    end
  end

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
    trace_file = $fopen("rtl_trace.jsonl", "w");
    if (trace_file == 0) begin
      $display("SIM FAIL: could not open rtl_trace.jsonl");
      $fatal(1);
    end
    for (instruction_index = 0; instruction_index < 128; instruction_index = instruction_index + 1) begin
      instruction_memory[instruction_index] = 32'h0000_0013;
    end
    for (instruction_index = 0; instruction_index < 16; instruction_index = instruction_index + 1) begin
      data_memory[instruction_index] = '0;
    end
    $readmemh("sim/random_program.hex", instruction_memory);

    @(posedge clk);
    #1;
    reset = 1'b0;
    commit_count = 0;
    for (cycle_count = 0; cycle_count < 7000 && commit_count < PROGRAM_LENGTH;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
      if (commit_valid) begin
        if (illegal_instruction || commit_trap_valid) begin
          $display("FAIL random commit: valid=%b illegal=%b trap=%b pc=%h", commit_valid, illegal_instruction, commit_trap_valid, commit_pc);
          failures = failures + 1;
        end else begin
        if (commit_rd_write) begin
          $fdisplay(trace_file, "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":\"0x%016h\"}", commit_pc, commit_instruction, commit_next_pc, commit_rd, commit_rd_value);
        end else begin
          $fdisplay(trace_file, "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":null}", commit_pc, commit_instruction, commit_next_pc, commit_rd);
        end
        end
        commit_count = commit_count + 1;
      end
    end
    if (commit_count != PROGRAM_LENGTH) begin
      $display("FAIL random core timeout: commits=%0d cycles=%0d", commit_count, cycle_count);
      failures = failures + 1;
    end
    if (failures != 0) begin
      $fclose(trace_file);
      $display("SIM FAIL: %0d random core checks failed", failures);
      $fatal(1);
    end
    $fclose(trace_file);
    $display("SIM PASS: rv64_core structured-random regression");
    $finish;
  end
endmodule
