`timescale 1ns / 1ps

module tb_rv64_bram_soc_mmu_sum_diff;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;
  integer trace_file;
  integer commit_count;
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

  task automatic write_trace;
    begin
      if (dut.core.commit_trap_valid) begin
        $fdisplay(trace_file,
                  "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":null,\"trap_cause\":\"0x%016h\",\"trap_value\":\"0x%016h\",\"privilege\":%0d}",
                  dut.core.commit_pc, dut.core.commit_instruction, dut.core.commit_next_pc,
                  dut.core.commit_rd, dut.core.commit_trap_cause, dut.core.csr_file.mtval,
                  dut.core.privilege_mode);
      end else if (dut.core.commit_rd_write) begin
        $fdisplay(trace_file,
                  "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":\"0x%016h\",\"trap_cause\":null,\"trap_value\":null,\"privilege\":%0d}",
                  dut.core.commit_pc, dut.core.commit_instruction, dut.core.commit_next_pc,
                  dut.core.commit_rd, dut.core.commit_rd_value, dut.core.privilege_mode);
      end else begin
        $fdisplay(trace_file,
                  "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":null,\"trap_cause\":null,\"trap_value\":null,\"privilege\":%0d}",
                  dut.core.commit_pc, dut.core.commit_instruction, dut.core.commit_next_pc,
                  dut.core.commit_rd, dut.core.privilege_mode);
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    failures = 0;
    commit_count = 0;
    trace_file = $fopen("rtl_trace.jsonl", "w");
    if (trace_file == 0) begin
      $display("SIM FAIL: could not open rtl_trace.jsonl");
      $fatal(1);
    end

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
    dut.data_memory[1536] = make_pte(44'd0, 8'h4b);
    dut.data_memory[1538] = make_pte(44'd4, 8'hd7);
    dut.data_memory[2048] = 64'h1122_3344_5566_7788;

    @(posedge clk);
    #1;
    reset = 1'b0;

    for (cycle_count = 0; cycle_count < 240 && commit_count < 14;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
      if (dut.core.commit_valid) begin
        write_trace();
        commit_count = commit_count + 1;
      end
    end

    if (commit_count != 14 || dut.core.privilege_mode !== 2'b11 ||
        dut.core.csr_file.mcause !== 64'd13 || dut.core.csr_file.mtval !== 64'h2000 ||
        dut.core.csr_file.mepc !== 64'h104 || dut.core.register_file.registers[4] !== 64'b0) begin
      $display("FAIL SUM=0 fault commits=%0d privilege=%b mcause=%h mtval=%h mepc=%h x4=%h",
               commit_count, dut.core.privilege_mode, dut.core.csr_file.mcause,
               dut.core.csr_file.mtval, dut.core.csr_file.mepc, dut.core.register_file.registers[4]);
      failures = failures + 1;
    end

    @(negedge clk);
    reset = 1'b1;
    dut.instruction_memory[6] = encode_u(20'h00041, 5'd1);
    dut.instruction_memory[7] = encode_i(12'h800, 5'd1, 3'b000, 5'd1, 7'b0010011);
    @(posedge clk);
    #1;
    reset = 1'b0;

    for (cycle_count = 0; cycle_count < 240 && commit_count < 28;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
      if (dut.core.commit_valid) begin
        write_trace();
        commit_count = commit_count + 1;
      end
    end

    if (commit_count != 28 || dut.core.privilege_mode !== 2'b01 ||
        dut.core.register_file.registers[4] !== 64'h1122_3344_5566_7788 ||
        dut.core.commit_trap_valid !== 1'b0) begin
      $display("FAIL SUM=1 result commits=%0d privilege=%b x4=%h trap=%b",
               commit_count, dut.core.privilege_mode, dut.core.register_file.registers[4],
               dut.core.commit_trap_valid);
      failures = failures + 1;
    end

    $fclose(trace_file);
    if (failures != 0) begin
      $display("SIM FAIL: %0d SoC Sv39 SUM differential checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_bram_soc Sv39 SUM differential regression");
    $finish;
  end
endmodule
