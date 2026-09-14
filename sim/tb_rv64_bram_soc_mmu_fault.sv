`timescale 1ns / 1ps

module tb_rv64_bram_soc_mmu_fault;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;

  rv64_bram_soc #(.UART_BIT_CYCLES(2)) dut (.*);
  always #5 clk = ~clk;

  function automatic logic [31:0] encode_i(
    input logic [11:0] immediate,
    input logic [4:0] source_register,
    input logic [2:0] function_code,
    input logic [4:0] destination_register,
    input logic [6:0] opcode
  );
    encode_i = {immediate, source_register, function_code, destination_register, opcode};
  endfunction

  function automatic logic [31:0] encode_u(
    input logic [19:0] immediate,
    input logic [4:0] destination_register
  );
    encode_u = {immediate, destination_register, 7'b0110111};
  endfunction

  function automatic logic [63:0] make_pte(
    input logic [43:0] ppn,
    input logic [7:0] flags
  );
    make_pte = {10'b0, ppn, 2'b0, flags};
  endfunction

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    #1;
    for (index = 0; index < 16384; index = index + 1) begin
      dut.instruction_memory[index] = 32'h0000_0013;
    end
    for (index = 0; index < 8192; index = index + 1) begin
      dut.data_memory[index] = '0;
    end

    dut.instruction_memory[0] = encode_u(20'h80000, 5'd1);
    dut.instruction_memory[1] = encode_i(12'd32, 5'd1, 3'b001, 5'd1, 7'b0010011);
    dut.instruction_memory[2] = encode_i(12'd1, 5'd1, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[3] = encode_i(12'h180, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[4] = encode_i(12'd64, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[5] = encode_i(12'h305, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[6] = encode_i(12'd1, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[7] = encode_i(12'd11, 5'd1, 3'b001, 5'd1, 7'b0010011);
    dut.instruction_memory[8] = encode_i(12'h300, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[9] = encode_i(12'h100, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[10] = encode_i(12'h341, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[11] = 32'h3020_0073;

    dut.instruction_memory[16] = 32'h0000_006f;
    dut.instruction_memory[64] = encode_u(20'd2, 5'd3);
    dut.instruction_memory[65] = encode_i(12'd0, 5'd3, 3'b011, 5'd4, 7'b0000011);

    dut.data_memory[512] = make_pte(44'd2, 8'h01);
    dut.data_memory[1024] = make_pte(44'd3, 8'h01);
    dut.data_memory[1536] = make_pte(44'd0, 8'h49);
    dut.data_memory[1538] = make_pte(44'd4, 8'hc9);

    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (100) begin
      @(posedge clk);
      #1;
    end

    if (dut.core.privilege_mode !== 2'b11) begin
      $display("FAIL load page fault did not return to M-mode: privilege=%b", dut.core.privilege_mode);
      failures = failures + 1;
    end
    if (dut.core.csr_file.mcause !== 64'd13 || dut.core.csr_file.mtval !== 64'h2000 ||
        dut.core.csr_file.mepc !== 64'h104) begin
      $display("FAIL load page fault CSRs mcause=%h mtval=%h mepc=%h",
               dut.core.csr_file.mcause, dut.core.csr_file.mtval, dut.core.csr_file.mepc);
      failures = failures + 1;
    end
    if (dut.core.csr_file.mstatus[12:11] !== 2'b01 ||
        dut.core.instruction_address !== 64'h40) begin
      $display("FAIL load page fault return state mpp=%b pc=%h",
               dut.core.csr_file.mstatus[12:11], dut.core.instruction_address);
      failures = failures + 1;
    end
    if (dut.core.register_file.registers[4] !== 64'b0) begin
      $display("FAIL faulting load wrote x4=%h", dut.core.register_file.registers[4]);
      failures = failures + 1;
    end

    if (failures != 0) begin
      $display("SIM FAIL: %0d SoC Sv39 page fault checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_bram_soc Sv39 load page fault regression");
    $finish;
  end
endmodule
