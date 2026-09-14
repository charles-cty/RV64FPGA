`timescale 1ns / 1ps

module tb_rv64_bram_soc_interrupt;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;

  rv64_bram_soc #(.UART_BIT_CYCLES(2)) dut (.*);
  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    for (index = 0; index < 16384; index = index + 1) begin
      dut.instruction_memory[index] = 32'h0000_0013;
    end

    dut.instruction_memory[0] = 32'h0400_0093; // addi x1, x0, 64
    dut.instruction_memory[1] = 32'h3050_9073; // csrrw x0, mtvec, x1
    dut.instruction_memory[2] = 32'h0080_0093; // addi x1, x0, 8
    dut.instruction_memory[3] = 32'h3000_9073; // csrrw x0, mstatus, x1
    dut.instruction_memory[4] = 32'h0800_0093; // addi x1, x0, 128
    dut.instruction_memory[5] = 32'h3040_9073; // csrrw x0, mie, x1
    dut.instruction_memory[6] = 32'h0000_0013; // interrupted nop
    dut.instruction_memory[7] = 32'h0000_006f; // loop after return
    dut.instruction_memory[16] = 32'h0070_0113; // handler: addi x2, x0, 7
    dut.instruction_memory[17] = 32'h3020_0073; // mret
    @(posedge clk);
    #1;
    reset = 1'b0;
    dut.clint.mtimecmp = 64'd8;
    repeat (18) @(posedge clk);
    #1;

    if (dut.core.register_file.registers[2] !== 64'd7) begin
      $display("FAIL timer handler x2: got=%h expected=7", dut.core.register_file.registers[2]);
      failures = failures + 1;
    end
    if (dut.core.csr_file.mcause !== 64'h8000_0000_0000_0007) begin
      $display("FAIL timer mcause: got=%h", dut.core.csr_file.mcause);
      failures = failures + 1;
    end
    if (dut.core.csr_file.mepc !== 64'h0000_0000_0000_001c) begin
      $display("FAIL timer mepc: got=%h expected=1c", dut.core.csr_file.mepc);
      failures = failures + 1;
    end

    if (failures != 0) begin
      $display("SIM FAIL: %0d SoC interrupt checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_bram_soc CLINT timer interrupt regression");
    $finish;
  end
endmodule
