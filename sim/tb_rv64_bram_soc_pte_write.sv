`timescale 1ns / 1ps

module rv64_pte_write_case #(parameter bit DATA_TEST = 0)(output logic done);
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;
  integer cycle_count;
  logic overlap_seen;

  rv64_bram_soc #(.USE_DDR3_MODEL(1'b1),
                  .DDR3_MODEL_WORD_COUNT(4096),
                  .DDR3_MODEL_RESPONSE_DELAY(40)) dut (
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
    done = 1'b0;
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    overlap_seen = 0;
    #1;
    for (index = 0; index < 16384; index = index + 1) begin
      dut.instruction_memory[index] = 32'h0000_0013;
    end
    for (index = 0; index < 4096; index = index + 1) begin
      dut.ddr3_model.memory[index] = 64'b0;
    end

    // Page-table writes are slower than the intervening BRAM accesses.
    // Both cases use valid, nonidentity mappings with initially clear A bits.
    dut.instruction_memory[0] = encode_u(20'h80000, 5'd1);
    dut.instruction_memory[1] = encode_i(12'd32, 5'd1, 3'b001, 5'd1, 7'b0010011);
    dut.instruction_memory[2] = encode_u(20'h00080, 5'd2);
    dut.instruction_memory[3] = encode_r(7'b0, 5'd2, 5'd1, 3'b110, 5'd1);
    dut.instruction_memory[4] = encode_i(12'h180, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[5] = encode_i(12'd1, 5'd0, 3'b000, 5'd1, 7'b0010011);
    dut.instruction_memory[6] = encode_i(12'd11, 5'd1, 3'b001, 5'd1, 7'b0010011);
    dut.instruction_memory[7] = encode_i(12'h300, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[10] = encode_i(12'h341, 5'd1, 3'b001, 5'd0, 7'b1110011);
    dut.instruction_memory[11] = 32'h30200073;
    dut.ddr3_model.memory[0] = make_pte(44'h80001, 8'h01);
    dut.ddr3_model.memory[512] = make_pte(44'h80002, 8'h01);
    if (DATA_TEST) begin
      dut.instruction_memory[8] = encode_i(12'h100, 5'd0, 3'b000, 5'd1, 7'b0010011);
      dut.instruction_memory[9] = 32'h00000013;
      dut.instruction_memory[64] = encode_u(20'h00002, 5'd3);
      dut.instruction_memory[65] = encode_i(12'd0, 5'd3, 3'b011, 5'd5, 7'b0000011);
      dut.instruction_memory[66] = encode_u(20'h00003, 5'd3);
      dut.instruction_memory[67] = encode_i(12'd0, 5'd3, 3'b011, 5'd4, 7'b0000011);
      dut.instruction_memory[68] = 32'h0000006f;
      dut.ddr3_model.memory[1024] = make_pte(44'd0, 8'h4b);
      dut.ddr3_model.memory[1026] = make_pte(44'd6, 8'h03);
      dut.ddr3_model.memory[1027] = make_pte(44'd7, 8'h43);
      dut.data_memory[3072] = 64'd3;
      dut.data_memory[3584] = 64'd7;
    end else begin
      dut.instruction_memory[8] = encode_u(20'h00001, 5'd1);
      dut.instruction_memory[9] = encode_i(12'hffc, 5'd1, 3'b000, 5'd1, 7'b0010011);
      dut.instruction_memory[3071] = 32'h00000013;
      dut.instruction_memory[4096] = encode_i(12'd7, 5'd0, 3'b000, 5'd4, 7'b0010011);
      dut.instruction_memory[4097] = 32'h0000006f;
      dut.ddr3_model.memory[1024] = make_pte(44'd2, 8'h0b);
      dut.ddr3_model.memory[1025] = make_pte(44'd4, 8'h4b);
    end
    @(posedge clk);
    #1;
    reset = 1'b0;
    for (cycle_count = 0; cycle_count < 3000 && dut.core.register_file.registers[4] !== 64'd7;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end

    if (dut.core.register_file.registers[4] !== 64'd7 || failures != 0 ||
        !overlap_seen ||
        (DATA_TEST && dut.core.register_file.registers[5] !== 64'd3) ||
        dut.ddr3_model.memory[DATA_TEST ? 1026 : 1024][6] !== 1'b1)
      $fatal(1, "SIM FAIL: A-bit write overlap DATA_TEST=%0d pc=%h cause=%h overlap=%b",
             DATA_TEST, dut.core.program_counter, dut.core.csr_file.mcause, overlap_seen);
    $display("PTE write overlap case completed DATA_TEST=%0d", DATA_TEST);
    done = 1'b1;
  end
  always @(posedge clk) begin
    if (!reset && dut.pte_master_active && dut.pte_master_write_latched && dut.pte_master_ready) begin
      if (DATA_TEST ? dut.data_pte_request : dut.instruction_pte_request)
        overlap_seen = 1'b1;
      $display("PTE_WRITE_ACK instruction_walk=%b instruction_ready=%b data_walk=%b data_ready=%b", dut.instruction_pte_request, dut.instruction_pte_ready, dut.data_pte_request, dut.data_pte_ready);
    end
    if (!reset && dut.commit_valid && dut.commit_trap_valid) begin
      failures = failures + 1;
      $display("TRAP pc=%h cause=%h", dut.commit_pc, dut.commit_trap_cause);
    end
  end
endmodule

module tb_rv64_bram_soc_pte_write;
  logic fetch_done, data_done;
  rv64_pte_write_case #(.DATA_TEST(0)) fetch_case(fetch_done);
  rv64_pte_write_case #(.DATA_TEST(1)) data_case(data_done);
  initial begin
    wait (fetch_done && data_done);
    $display("SIM PASS: page-table write acknowledgements cannot complete instruction or data walks");
    $finish;
  end
endmodule
