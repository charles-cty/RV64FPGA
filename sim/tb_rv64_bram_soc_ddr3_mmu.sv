`timescale 1ns / 1ps

module tb_rv64_bram_soc_ddr3_mmu;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;
  integer cycle_count;

  rv64_bram_soc #(.USE_DDR3_MODEL(1'b1),
                  .DDR3_MODEL_WORD_COUNT(4096),
                  .DDR3_MODEL_RESPONSE_DELAY(3)) dut (
    .clk(clk), .reset(reset), .led(led), .uart_tx(uart_tx), .uart_rx(1'b1),
    .external_ddr3_request_ready(1'b0),
    .external_ddr3_response_read_data(64'b0),
    .external_ddr3_response_error(1'b0)
  );
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

  function automatic logic [31:0] encode_r(
    input logic [6:0] function_code_high,
    input logic [4:0] source_register2,
    input logic [4:0] source_register1,
    input logic [2:0] function_code,
    input logic [4:0] destination_register
  );
    encode_r = {function_code_high, source_register2, source_register1,
                function_code, destination_register, 7'b0110011};
  endfunction

  function automatic logic [31:0] encode_s(
    input logic [11:0] immediate,
    input logic [4:0] source_register,
    input logic [4:0] data_register,
    input logic [2:0] function_code
  );
    encode_s = {immediate[11:5], data_register, source_register, function_code,
                immediate[4:0], 7'b0100011};
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
    for (index = 0; index < 4096; index = index + 1) begin
      dut.ddr3_model.memory[index] = 64'b0;
    end

    // M-mode setup: satp = Sv39 root at physical 0x80000000.
    dut.instruction_memory[0] = encode_u(20'h80000, 5'd1);
    dut.instruction_memory[1] = encode_i(12'd32, 5'd1, 3'b001, 5'd1, 7'b0010011);
    dut.instruction_memory[2] = encode_u(20'h00080, 5'd2);
    dut.instruction_memory[3] = encode_r(7'b0, 5'd2, 5'd1, 3'b110, 5'd1); // or x1,x1,x2
    dut.instruction_memory[4] = encode_i(12'h180, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[5] = encode_i(12'd1, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[6] = encode_i(12'd11, 5'd1, 3'b001, 5'd1, 7'b0010011);
    dut.instruction_memory[7] = encode_i(12'h300, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[8] = encode_i(12'h100, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[9] = encode_i(12'h341, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[10] = 32'h3020_0073; // mret

    // S-mode access at VA 0x2000, mapped to DDR3 PA 0x80000000.
    dut.instruction_memory[64] = encode_u(20'h00002, 5'd3);
    dut.instruction_memory[65] = encode_i(12'd7, 5'd0, 3'b000, 5'd2, 7'b0010011);
    dut.instruction_memory[66] = encode_s(12'd0, 5'd3, 5'd2, 3'b011);
    dut.instruction_memory[67] = encode_i(12'd0, 5'd3, 3'b011, 5'd4, 7'b0000011);
    dut.instruction_memory[68] = 32'h0000_006f;

    // Root 0x80000000 -> L1 0x80001000 -> L0 0x80002000.
    dut.ddr3_model.memory[0] = make_pte(44'h80001, 8'h01);
    dut.ddr3_model.memory[512] = make_pte(44'h80002, 8'h01);
    dut.ddr3_model.memory[1024] = make_pte(44'd0, 8'h4b); // VA page 0: BRAM X/R
    dut.ddr3_model.memory[1026] = make_pte(44'h80000, 8'h07); // VA page 2: DDR3 R/W

    @(posedge clk);
    #1;
    reset = 1'b0;
    for (cycle_count = 0; cycle_count < 500 && dut.core.register_file.registers[4] !== 64'd7;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end

    if (dut.core.privilege_mode !== 2'b01 ||
        dut.core.register_file.registers[4] !== 64'd7 ||
        dut.ddr3_model.memory[0] !== 64'd7 ||
        dut.ddr3_model.memory[1026][6] !== 1'b1 ||
        dut.ddr3_model.memory[1026][7] !== 1'b1) begin
      $display("FAIL DDR3 Sv39 x4=%h privilege=%b data=%h leaf=%h cycles=%0d",
               dut.core.register_file.registers[4], dut.core.privilege_mode,
               dut.ddr3_model.memory[0], dut.ddr3_model.memory[1026], cycle_count);
      failures = failures + 1;
    end
    if (failures != 0) $fatal(1, "SIM FAIL: %0d DDR3 Sv39 checks failed", failures);
    $display("SIM PASS: rv64_bram_soc DDR3-backed Sv39 integration");
    $finish;
  end
endmodule
