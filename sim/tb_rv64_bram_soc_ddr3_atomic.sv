`timescale 1ns / 1ps

module tb_rv64_bram_soc_ddr3_atomic;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;
  integer cycle_count;

  rv64_bram_soc #(.UART_BIT_CYCLES(2), .USE_DDR3_MODEL(1'b1),
                  .DDR3_MODEL_RESPONSE_DELAY(3)) dut (
    .clk(clk), .reset(reset), .led(led), .uart_tx(uart_tx), .uart_rx(1'b1),
    .external_ddr3_request_ready(1'b0),
    .external_ddr3_response_read_data(64'b0),
    .external_ddr3_response_error(1'b0)
  );
  always #5 clk = ~clk;

  function automatic logic [31:0] encode_atomic(
    input logic [4:0] funct5,
    input logic [4:0] source_register,
    input logic [4:0] address_register,
    input logic [4:0] destination_register,
    input logic word_operation = 1'b0
  );
    encode_atomic = {funct5, 2'b00, source_register, address_register,
                     (word_operation ? 3'b010 : 3'b011), destination_register, 7'b0101111};
  endfunction

  function automatic logic [31:0] encode_i(
    input logic [11:0] immediate,
    input logic [4:0] source_register,
    input logic [2:0] function_code,
    input logic [4:0] destination_register,
    input logic [6:0] opcode
  );
    encode_i = {immediate, source_register, function_code, destination_register, opcode};
  endfunction

  always @(posedge clk) begin
    if (!reset && dut.atomic_ddr3_request_valid &&
        dut.atomic_ddr3_request_address[2:0] != 3'b000) begin
      $fatal(1, "SIM FAIL: unaligned atomic request reached the DDR port");
    end
  end

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    #1;
    for (index = 0; index < 16384; index = index + 1) begin
      dut.instruction_memory[index] = 32'h0000_0013;
    end
    dut.instruction_memory[0] = 32'h8000_00b7; // lui x1, 0x80000
    dut.instruction_memory[1] = 32'h0200_9093; // slli x1, x1, 32
    dut.instruction_memory[2] = 32'h0200_d093; // srli x1, x1, 32
    dut.instruction_memory[3] = 32'h0050_0113; // addi x2, x0, 5
    dut.instruction_memory[4] = encode_i(12'd0, 5'd1, 3'b011, 5'd7, 7'b0000011); // ld x7
    dut.instruction_memory[5] = encode_atomic(5'b00010, 5'd0, 5'd1, 5'd3); // lr.d x3
    dut.instruction_memory[6] = encode_atomic(5'b00011, 5'd2, 5'd1, 5'd4); // sc.d x4
    dut.instruction_memory[7] = encode_atomic(5'b00000, 5'd2, 5'd1, 5'd5); // amoadd.d x5
    dut.instruction_memory[8] = encode_i(12'd0, 5'd1, 3'b011, 5'd6, 7'b0000011); // ld x6
    // Exercise both 32-bit lanes with distinct adjacent data and sign extension.
    dut.instruction_memory[9] = encode_i(12'd20, 5'd1, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[10] = encode_atomic(5'b01000, 5'd2, 5'd1, 5'd8, 1'b1); // amoor.w upper
    dut.instruction_memory[11] = encode_i(12'hffc, 5'd1, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[12] = encode_atomic(5'b00000, 5'd2, 5'd1, 5'd9, 1'b1); // amoadd.w lower
    dut.instruction_memory[13] = encode_i(12'd4, 5'd1, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[14] = encode_atomic(5'b00010, 5'd0, 5'd1, 5'd10, 1'b1); // lr.w upper
    dut.instruction_memory[15] = encode_atomic(5'b00011, 5'd2, 5'd1, 5'd11, 1'b1); // sc.w upper
    dut.instruction_memory[16] = encode_i(12'hffc, 5'd1, 3'b011, 5'd12, 7'b0000011);
    dut.instruction_memory[17] = 32'h0000_006f; // loop
    dut.ddr3_model.memory[2] = 64'h80000002_12345678;
    dut.ddr3_model.memory[0] = 64'd7;

    @(posedge clk);
    #1;
    reset = 1'b0;
    for (cycle_count = 0; cycle_count < 1000 && dut.core.register_file.registers[12] !== 64'h00000005_1234567d;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end

    if (dut.core.register_file.registers[7] !== 64'd7 ||
        dut.core.register_file.registers[3] !== 64'd7 ||
        dut.core.register_file.registers[4] !== 64'd0 ||
        dut.core.register_file.registers[5] !== 64'd5 ||
        dut.core.register_file.registers[6] !== 64'd10 ||
        dut.ddr3_model.memory[0] !== 64'd10) begin
      $display("FAIL DDR3 atomic x7=%h x3=%h x4=%h x5=%h x6=%h memory=%h cycles=%0d",
               dut.core.register_file.registers[7], dut.core.register_file.registers[3],
               dut.core.register_file.registers[4], dut.core.register_file.registers[5],
               dut.core.register_file.registers[6], dut.ddr3_model.memory[0], cycle_count);
      failures = failures + 1;
    end
    if (dut.core.register_file.registers[8] !== 64'hffffffff80000002 ||
        dut.core.register_file.registers[9] !== 64'h0000000012345678 ||
        dut.core.register_file.registers[10] !== 64'hffffffff80000007 ||
        dut.core.register_file.registers[11] !== 64'd0 ||
        dut.core.register_file.registers[12] !== 64'h00000005_1234567d ||
        dut.ddr3_model.memory[2] !== 64'h00000005_1234567d) begin
      $display("FAIL word atomic lanes x8=%h x9=%h x10=%h x11=%h x12=%h memory=%h",
               dut.core.register_file.registers[8], dut.core.register_file.registers[9],
               dut.core.register_file.registers[10], dut.core.register_file.registers[11],
               dut.core.register_file.registers[12], dut.ddr3_model.memory[2]);
      failures = failures + 1;
    end
    if (failures != 0) $fatal(1, "SIM FAIL: %0d DDR3 atomic checks failed", failures);
    $display("SIM PASS: rv64_bram_soc DDR3 LR/SC/AMO read-modify-write");
    $finish;
  end
endmodule
