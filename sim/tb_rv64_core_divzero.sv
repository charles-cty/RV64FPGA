`timescale 1ns / 1ps

module tb_rv64_core_divzero;
  logic clk=0, reset=1, software_interrupt=0, timer_interrupt=0, external_interrupt=0;
  logic [63:0] instruction_address;
  logic [31:0] instruction_data;
  logic instruction_ready=1, instruction_fault=0;
  logic data_valid, data_write; logic [63:0] data_address, data_write_data, data_read_data=0;
  logic [7:0] data_write_strobe; logic data_ready=1, data_fault=0;
  logic commit_valid, commit_rd_write, commit_csr_write, commit_trap_valid;
  logic [63:0] commit_pc, commit_next_pc, commit_rd_value, commit_csr_value, commit_trap_cause;
  logic [31:0] commit_instruction; logic [4:0] commit_rd; logic [11:0] commit_csr_address;
  logic illegal_instruction; logic [1:0] privilege_mode, data_privilege;
  logic [63:0] satp_value; logic sum_enable, mxr_enable, sfence_valid, sfence_all, fence_i_valid, atomic_access;
  logic [63:0] sfence_virtual_address;
  logic [31:0] imem [0:7]; integer cycles, commits;
  rv64_core dut (.*);
  always #5 clk = ~clk;
  assign instruction_data = imem[instruction_address[4:2]];
  initial begin
    imem[0] = 32'h0000_0093; // addi x1,x0,0
    imem[1] = 32'h0200_41b3; // div x3,x0,x0 (signed divide by zero)
    imem[2] = 32'h0010_0213; // addi x4,x0,1
    imem[3] = 32'h0000_0013;
    repeat (1) @(posedge clk); #1; reset=0;
    for (cycles=0; cycles<180; cycles=cycles+1) begin
      @(posedge clk); #1;
      if (commit_valid) begin
        commits=commits+1;
        $display("COMMIT pc=%h insn=%h rd=%0d val=%h trap=%b", commit_pc, commit_instruction, commit_rd, commit_rd_value, commit_trap_valid);
        if (commits==3 && dut.register_file.registers[4] !== 64'd1) $fatal(1,"DIV zero blocked following instruction");
      end
    end
    if (commits < 3) $fatal(1,"timeout commits=%0d pc=%h", commits, instruction_address);
    $display("SIM PASS: core div-by-zero forward progress"); $finish;
  end
endmodule
