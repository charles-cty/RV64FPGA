`timescale 1ns / 1ps

module tb_rv64_core;
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
  integer trace_file;
  integer failures;
  integer commit_count;
  integer cycle_count;
  integer index;
  integer byte_index;

  rv64_core dut (.*);

  always #5 clk = ~clk;
  assign instruction_data = instruction_memory[instruction_address[6:2]];
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

  task automatic expect_commit(input logic [511:0] name, input logic [63:0] expected_pc);
    begin
      if (!commit_valid || commit_pc !== expected_pc || illegal_instruction) begin
        $display("FAIL %0s: valid=%b pc=%h expected=%h illegal=%b", name, commit_valid, commit_pc, expected_pc, illegal_instruction);
        failures = failures + 1;
      end
      commit_count = commit_count + 1;
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
    commit_count = 0;
    trace_file = $fopen("rtl_trace.jsonl", "w");
    if (trace_file == 0) begin
      $display("SIM FAIL: could not open rtl_trace.jsonl");
      $fatal(1);
    end
    for (index = 0; index < 32; index = index + 1) begin
      instruction_memory[index] = 32'h0000_0013;
    end
    for (index = 0; index < 16; index = index + 1) begin
      data_memory[index] = '0;
    end

    instruction_memory[0] = 32'h0050_0093; // addi x1, x0, 5
    instruction_memory[1] = 32'h0070_0113; // addi x2, x0, 7
    instruction_memory[2] = 32'h0020_81b3; // add x3, x1, x2
    instruction_memory[3] = 32'h0030_2023; // sw x3, 0(x0)
    instruction_memory[4] = 32'h0000_2203; // lw x4, 0(x0)
    instruction_memory[5] = 32'h0041_8463; // beq x3, x4, +8
    instruction_memory[6] = 32'h0630_0293; // addi x5, x0, 99 (skipped)
    instruction_memory[7] = 32'h0080_006f; // jal x0, +8
    instruction_memory[8] = 32'h04d0_0293; // addi x5, x0, 77 (skipped)
    instruction_memory[9] = 32'h02a0_0293; // addi x5, x0, 42

    @(posedge clk);
    #1;
    reset = 1'b0;

    for (cycle_count = 0; cycle_count < 24 && commit_count < 10;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
      if (commit_valid) begin
        if (commit_rd_write) begin
          $fdisplay(trace_file, "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":\"0x%016h\"}", commit_pc, commit_instruction, commit_next_pc, commit_rd, commit_rd_value);
        end else begin
          $fdisplay(trace_file, "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":null}", commit_pc, commit_instruction, commit_next_pc, commit_rd);
        end
        case (commit_count)
          0: expect_commit("addi x1", 64'd0);
          1: expect_commit("addi x2", 64'd4);
          2: expect_commit("add x3", 64'd8);
          3: expect_commit("store", 64'd12);
          4: expect_commit("load", 64'd16);
          5: expect_commit("taken branch", 64'd20);
          6: expect_commit("jal", 64'd28);
          7: expect_commit("target addi", 64'd36);
          default: expect_commit("post-program nop", commit_pc);
        endcase
      end
    end

    if (commit_count != 10) begin
      $display("FAIL core timeout: commits=%0d cycles=%0d", commit_count, cycle_count);
      failures = failures + 1;
    end

    if (dut.register_file.registers[3] !== 64'd12) begin
      $display("FAIL x3: got=%h expected=12", dut.register_file.registers[3]);
      failures = failures + 1;
    end
    if (dut.register_file.registers[4] !== 64'd12) begin
      $display("FAIL x4: got=%h expected=12", dut.register_file.registers[4]);
      failures = failures + 1;
    end
    if (dut.register_file.registers[5] !== 64'd42) begin
      $display("FAIL x5: got=%h expected=42", dut.register_file.registers[5]);
      failures = failures + 1;
    end
    if (data_memory[0] !== 64'd12) begin
      $display("FAIL memory[0]: got=%h expected=12", data_memory[0]);
      failures = failures + 1;
    end

    if (failures != 0) begin
      $fclose(trace_file);
      $display("SIM FAIL: %0d core checks failed", failures);
      $fatal(1);
    end else begin
      $fclose(trace_file);
      $display("SIM PASS: rv64_core BRAM program regression");
    end
    $finish;
  end
endmodule
