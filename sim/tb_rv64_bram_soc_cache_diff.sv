`timescale 1ns / 1ps

module tb_rv64_bram_soc_cache_diff;
  logic clk;
  logic reset;
  logic [2:0] led;
  logic uart_tx;
  integer failures;
  integer index;
  integer trace_file;
  integer commit_count;
  integer cycle_count;

  rv64_bram_soc dut (.*);
  always #5 clk = ~clk;

  task automatic write_trace;
    begin
      if (dut.core.commit_rd_write) begin
        $fdisplay(trace_file,
                  "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":\"0x%016h\"}",
                  dut.core.commit_pc, dut.core.commit_instruction, dut.core.commit_next_pc,
                  dut.core.commit_rd, dut.core.commit_rd_value);
      end else begin
        $fdisplay(trace_file,
                  "{\"pc\":\"0x%016h\",\"instruction\":\"0x%08h\",\"next_pc\":\"0x%016h\",\"rd\":%0d,\"rd_value\":null}",
                  dut.core.commit_pc, dut.core.commit_instruction, dut.core.commit_next_pc,
                  dut.core.commit_rd);
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

    dut.instruction_memory[0] = 32'h0050_0093; // addi x1, x0, 5
    dut.instruction_memory[1] = 32'h0010_3023; // sd x1, 0(x0)
    dut.instruction_memory[2] = 32'h0000_3103; // ld x2, 0(x0), cache miss
    dut.instruction_memory[3] = 32'h0000_3183; // ld x3, 0(x0), cache hit
    dut.instruction_memory[4] = 32'h0070_8093; // addi x1, x1, 7
    dut.instruction_memory[5] = 32'h0010_3423; // sd x1, 8(x0)
    dut.instruction_memory[6] = 32'h0080_3203; // ld x4, 8(x0), cache miss
    dut.instruction_memory[7] = 32'h0041_02b3; // add x5, x2, x4
    dut.instruction_memory[8] = 32'h0050_3823; // sd x5, 16(x0)
    dut.instruction_memory[9] = 32'h0100_3303; // ld x6, 16(x0)
    dut.instruction_memory[10] = 32'h0062_8463; // beq x5, x6, +8
    dut.instruction_memory[11] = 32'h0630_0393; // addi x7, x0, 99 (skipped)
    dut.instruction_memory[12] = 32'h02a0_0393; // addi x7, x0, 42
    dut.instruction_memory[13] = 32'h0000_006f; // jal x0, 0

    @(posedge clk);
    #1;
    reset = 1'b0;

    for (cycle_count = 0; cycle_count < 240 && commit_count < 12;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
      if (dut.core.commit_valid) begin
        write_trace();
        commit_count = commit_count + 1;
      end
    end

    if (commit_count != 12) begin
      $display("FAIL expected 12 commits, got %0d", commit_count);
      failures = failures + 1;
    end
    if (dut.core.register_file.registers[2] !== 64'd5 ||
        dut.core.register_file.registers[3] !== 64'd5 ||
        dut.core.register_file.registers[4] !== 64'd12 ||
        dut.core.register_file.registers[5] !== 64'd17 ||
        dut.core.register_file.registers[6] !== 64'd17 ||
        dut.core.register_file.registers[7] !== 64'd42) begin
      $display("FAIL cache program registers x2=%h x3=%h x4=%h x5=%h x6=%h x7=%h",
               dut.core.register_file.registers[2], dut.core.register_file.registers[3],
               dut.core.register_file.registers[4], dut.core.register_file.registers[5],
               dut.core.register_file.registers[6], dut.core.register_file.registers[7]);
      failures = failures + 1;
    end
    if (dut.data_memory[0] !== 64'd5 || dut.data_memory[1] !== 64'd12 ||
        dut.data_memory[2] !== 64'd17) begin
      $display("FAIL cache program memory m0=%h m1=%h m2=%h",
               dut.data_memory[0], dut.data_memory[1], dut.data_memory[2]);
      failures = failures + 1;
    end
    if (!dut.data_cache.line_valid[0] || !dut.data_cache.line_valid[1] ||
        !dut.data_cache.line_valid[2]) begin
      $display("FAIL expected cache lines were not filled: valid=%b", dut.data_cache.line_valid);
      failures = failures + 1;
    end

    $fclose(trace_file);
    if (failures != 0) begin
      $display("SIM FAIL: %0d SoC cache differential checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_bram_soc cache differential regression");
    $finish;
  end
endmodule
