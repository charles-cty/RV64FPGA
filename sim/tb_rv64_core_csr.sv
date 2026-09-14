`timescale 1ns / 1ps

module tb_rv64_core_csr;
  logic clk;
  logic reset;
  logic [63:0] instruction_address;
  logic [31:0] instruction_data;
  logic data_valid;
  logic data_write;
  logic [63:0] data_address;
  logic [63:0] data_write_data;
  logic [7:0] data_write_strobe;
  logic [63:0] data_read_data;
  logic data_ready;
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
  logic [31:0] instruction_memory [0:31];
  integer failures;
  integer index;

  rv64_core dut (.*);
  always #5 clk = ~clk;
  assign instruction_data = instruction_memory[instruction_address[6:2]];
  assign data_read_data = '0;
  assign data_ready = 1'b1;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    for (index = 0; index < 32; index = index + 1) begin
      instruction_memory[index] = 32'h0000_0013;
    end

    instruction_memory[0] = 32'h0400_0093; // addi x1, x0, 64
    instruction_memory[1] = 32'h3050_9073; // csrrw x0, mtvec, x1
    instruction_memory[2] = 32'h3050_2173; // csrrs x2, mtvec, x0
    instruction_memory[3] = 32'h0140_0213; // addi x4, x0, 20
    instruction_memory[4] = 32'h0000_0073; // ecall
    instruction_memory[5] = 32'h02a0_0293; // addi x5, x0, 42
    instruction_memory[16] = 32'h0090_0193; // handler: addi x3, x0, 9
    instruction_memory[17] = 32'h3412_1073; // csrrw x0, mepc, x4
    instruction_memory[18] = 32'h3020_0073; // mret

    @(posedge clk);
    #1;
    reset = 1'b0;

    repeat (10) @(posedge clk);
    #1;

    if (dut.register_file.registers[2] !== 64'd64) begin
      $display("FAIL CSRRS result x2: got=%h expected=64", dut.register_file.registers[2]);
      failures = failures + 1;
    end
    if (dut.register_file.registers[3] !== 64'd9) begin
      $display("FAIL trap handler x3: got=%h expected=9", dut.register_file.registers[3]);
      failures = failures + 1;
    end
    if (dut.register_file.registers[5] !== 64'd42) begin
      $display("FAIL post-mret x5: got=%h expected=42", dut.register_file.registers[5]);
      failures = failures + 1;
    end
    if (dut.csr_file.mtvec !== 64'd64 || dut.csr_file.mepc !== 64'd20) begin
      $display("FAIL CSR state: mtvec=%h mepc=%h", dut.csr_file.mtvec, dut.csr_file.mepc);
      failures = failures + 1;
    end

    if (failures != 0) begin
      $display("SIM FAIL: %0d core CSR checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_core CSR/trap/mret regression");
    $finish;
  end
endmodule
