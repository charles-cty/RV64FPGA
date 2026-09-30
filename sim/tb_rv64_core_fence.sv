`timescale 1ns / 1ps

module tb_rv64_core_fence;
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
  logic [31:0] instruction_memory [0:4];
  integer failures;
  integer index;

  rv64_core dut (.*);
  always #5 clk = ~clk;
  assign instruction_data = instruction_memory[instruction_address[3:2]];
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
    for (index = 0; index < 5; index = index + 1) begin
      instruction_memory[index] = 32'h0000_0013;
    end
    instruction_memory[0] = 32'h0000_000f;
    instruction_memory[1] = 32'h0000_100f;
    instruction_memory[2] = 32'h0000_200f;
    instruction_memory[3] = 32'h1050_0073;

    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (4) begin
      @(posedge clk);
      #1;
      if (!commit_valid) failures = failures + 1;
      if (commit_pc == 64'd0 || commit_pc == 64'd4) begin
        if (commit_trap_valid) failures = failures + 1;
        if ((commit_pc == 64'd0 && commit_instruction !== 32'h0000_000f) ||
            (commit_pc == 64'd4 && commit_instruction !== 32'h0000_100f)) failures = failures + 1;
      end
      if (commit_pc == 64'd8 && !commit_trap_valid) failures = failures + 1;
      if (commit_pc == 64'd12 && commit_trap_valid) failures = failures + 1;
    end

    if (failures != 0) $fatal(1, "SIM FAIL: %0d fence checks failed", failures);
    $display("SIM PASS: rv64_core FENCE, FENCE.I and WFI regression");
    $finish;
  end
endmodule
