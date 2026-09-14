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
  logic [1:0] privilege_mode;
  logic [63:0] satp_value;
  logic sum_enable;
  logic sfence_valid;
  logic [63:0] sfence_virtual_address;
  logic [31:0] instruction_memory [0:31];
  logic [63:0] data_memory [0:15];
  integer failures;
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

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    software_interrupt = 1'b0;
    timer_interrupt = 1'b0;
    external_interrupt = 1'b0;
    instruction_ready = 1'b1;
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
    repeat (7) @(posedge clk);
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

    if (failures != 0) begin
      $display("SIM FAIL: %0d core atomic checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_core atomic BRAM regression");
    $finish;
  end
endmodule
