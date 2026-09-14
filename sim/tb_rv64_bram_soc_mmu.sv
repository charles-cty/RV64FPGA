`timescale 1ns / 1ps

module tb_rv64_bram_soc_mmu;
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

  function automatic logic [31:0] encode_s(
    input logic [11:0] immediate,
    input logic [4:0] source_register,
    input logic [4:0] data_register,
    input logic [2:0] function_code,
    input logic [6:0] opcode
  );
    encode_s = {immediate[11:5], data_register, source_register, function_code,
                immediate[4:0], opcode};
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
    dut.instruction_memory[4] = encode_i(12'd1, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[5] = encode_i(12'd11, 5'd1, 3'b001, 5'd1, 7'b0010011);
    dut.instruction_memory[6] = encode_i(12'h300, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[7] = encode_i(12'h100, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[8] = encode_i(12'h341, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[9] = 32'h3020_0073;

    dut.instruction_memory[64] = encode_i(12'd2, 5'd0, 3'b000, 5'd2, 7'b0010011);
    dut.instruction_memory[65] = encode_u(20'd2, 5'd3);
    dut.instruction_memory[66] = encode_s(12'd0, 5'd3, 5'd2, 3'b011, 7'b0100011);
    dut.instruction_memory[67] = encode_i(12'd0, 5'd3, 3'b011, 5'd4, 7'b0000011);
    dut.instruction_memory[68] = 32'h0000_006f;

    dut.data_memory[512] = make_pte(44'd2, 8'h01);
    dut.data_memory[1024] = make_pte(44'd3, 8'h01);
    dut.data_memory[1536] = make_pte(44'd0, 8'h49);
    dut.data_memory[1538] = make_pte(44'd4, 8'hc7);

    @(posedge clk);
    #1;
    reset = 1'b0;
    repeat (140) begin
      @(posedge clk);
      #1;
    end

    if (dut.core.privilege_mode !== 2'b01) begin
      $display("FAIL MMU core did not remain in S-mode: privilege=%b", dut.core.privilege_mode);
      failures = failures + 1;
    end
    if (dut.core.register_file.registers[4] !== 64'd2) begin
      $display("FAIL translated load result: got=%h expected=2", dut.core.register_file.registers[4]);
      $display("DEBUG pc=%h x1=%h x2=%h x3=%h x4=%h data_va=%h data_pa=%h mmu_pa=%h done=%b",
               dut.core.instruction_address, dut.core.register_file.registers[1],
               dut.core.register_file.registers[2], dut.core.register_file.registers[3],
               dut.core.register_file.registers[4], dut.core.data_address,
               dut.data_physical_address, dut.data_mmu_physical_address,
               dut.data_translation_done);
      failures = failures + 1;
    end
    if (dut.data_memory[2048] !== 64'd2) begin
      $display("FAIL translated store physical location: got=%h expected=2", dut.data_memory[2048]);
      failures = failures + 1;
    end
    if (dut.core.commit_trap_valid !== 1'b0 || dut.instruction_translation_fault !== 1'b0 ||
        dut.data_translation_fault !== 1'b0) begin
      $display("FAIL unexpected MMU trap: commit_trap=%b instruction_fault=%b data_fault=%b",
               dut.core.commit_trap_valid, dut.instruction_translation_fault,
               dut.data_translation_fault);
      failures = failures + 1;
    end

    if (failures != 0) begin
      $display("SIM FAIL: %0d SoC MMU integration checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_bram_soc Sv39 core integration regression");
    $finish;
  end
endmodule
