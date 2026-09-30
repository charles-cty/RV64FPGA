`timescale 1ns / 1ps

module tb_rv64_bram_soc_sbi;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;
  integer cycle_count;

  rv64_bram_soc #(.UART_BIT_CYCLES(2)) dut (
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

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    #1;
    for (index = 0; index < 16384; index = index + 1) begin
      dut.instruction_memory[index] = 32'h0000_0013;
    end

    // M-mode enters S-mode at 0x40 with mtvec at 0x100.
    dut.instruction_memory[0] = encode_i(12'h100, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[1] = encode_i(12'h305, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[2] = encode_i(12'd1, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[3] = encode_i(12'd11, 5'd1, 3'b001, 5'd1, 7'b0010011);
    dut.instruction_memory[4] = encode_i(12'h300, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[5] = encode_i(12'h040, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[6] = encode_i(12'h341, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[7] = 32'h3020_0073;

    // S-mode SBI-shaped call: a7=legacy console putchar, a0='A'.
    dut.instruction_memory[16] = encode_i(12'd1, 5'd0, 3'b000, 5'd17, 7'b0010011);
    dut.instruction_memory[17] = encode_i(12'd65, 5'd0, 3'b000, 5'd10, 7'b0010011);
    dut.instruction_memory[18] = 32'h0000_0073;
    dut.instruction_memory[19] = encode_i(12'd42, 5'd0, 3'b000, 5'd5, 7'b0010011);
    dut.instruction_memory[20] = 32'h0000_006f;

    // M-mode ecall handler advances mepc over ecall before mret.
    dut.instruction_memory[64] = encode_i(12'h341, 5'd0, 3'b010, 5'd6, 7'b1110011);
    dut.instruction_memory[65] = encode_i(12'd4, 5'd6, 3'b000, 5'd6, 7'b0010011);
    dut.instruction_memory[66] = encode_i(12'h341, 5'd6, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[67] = 32'h3020_0073;

    @(posedge clk);
    #1;
    reset = 1'b0;
    for (cycle_count = 0; cycle_count < 100 && dut.core.register_file.registers[5] !== 64'd42;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end

    if (dut.core.privilege_mode !== 2'b01 ||
        dut.core.register_file.registers[5] !== 64'd42 ||
        dut.core.register_file.registers[6] !== 64'h4c ||
        dut.core.csr_file.mcause !== 64'd9 ||
        dut.core.csr_file.mepc !== 64'h4c) begin
      $display("FAIL SBI ecall privilege=%b x5=%h x6=%h mcause=%h mepc=%h cycles=%0d",
               dut.core.privilege_mode, dut.core.register_file.registers[5],
               dut.core.register_file.registers[6], dut.core.csr_file.mcause,
               dut.core.csr_file.mepc, cycle_count);
      failures = failures + 1;
    end
    if (failures != 0) $fatal(1, "SIM FAIL: %0d SBI checks failed", failures);
    $display("SIM PASS: rv64_bram_soc S-mode SBI ecall smoke test");
    $finish;
  end
endmodule
