`timescale 1ns / 1ps

module tb_rv64_core_supervisor_irq;
  logic clk;
  logic reset;
  logic software_interrupt;
  logic timer_interrupt;
  logic external_interrupt;
  logic [63:0] instruction_address;
  logic [31:0] instruction_data;
  logic instruction_ready;
  logic instruction_fault;
  logic data_valid;
  logic data_write;
  logic [63:0] data_address;
  logic [63:0] data_write_data;
  logic [7:0] data_write_strobe;
  logic [63:0] data_read_data;
  logic data_ready;
  logic data_fault;
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
  logic [1:0] data_privilege;
  logic [63:0] satp_value;
  logic sum_enable;
  logic mxr_enable;
  logic sfence_valid;
  logic [63:0] sfence_virtual_address;
  logic sfence_all;
  logic fence_i_valid;
  logic atomic_access;
  logic [31:0] instruction_memory [0:63];
  integer failures;
  integer index;
  integer cycle_count;
  logic machine_timer_seen;
  logic supervisor_timer_seen;

  rv64_core dut (.*);
  always #5 clk = ~clk;
  assign instruction_data = instruction_memory[instruction_address[7:2]];
  assign data_read_data = '0;
  assign data_ready = 1'b1;
  assign data_fault = 1'b0;

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    software_interrupt = 1'b0;
    timer_interrupt = 1'b0;
    external_interrupt = 1'b0;
    instruction_ready = 1'b1;
    instruction_fault = 1'b0;
    failures = 0;
    machine_timer_seen = 1'b0;
    supervisor_timer_seen = 1'b0;
    for (index = 0; index < 64; index = index + 1) begin
      instruction_memory[index] = 32'h0000_0013;
    end

    // Configure an OpenSBI-style timer handoff.  Enter S-mode with MIE=0,
    // SIE=1, MTIE=1, STIE=1, and only STIP delegated.
    instruction_memory[0] = 32'h0800_0093; // li x1, 0x80
    instruction_memory[1] = 32'h3050_9073; // csrw mtvec, x1
    instruction_memory[2] = 32'h0c00_0093; // li x1, 0xc0
    instruction_memory[3] = 32'h1050_9073; // csrw stvec, x1
    instruction_memory[4] = 32'h0200_0093; // li x1, 0x20
    instruction_memory[5] = 32'h3030_9073; // csrw mideleg, x1
    instruction_memory[6] = 32'h1040_9073; // csrw sie, x1 (STIE)
    instruction_memory[7] = 32'h0800_0093; // li x1, 0x80
    instruction_memory[8] = 32'h3040_a073; // csrs mie, x1 (MTIE)
    instruction_memory[9] = 32'h0400_0093; // li x1, 0x40
    instruction_memory[10] = 32'h3410_9073; // csrw mepc, x1
    instruction_memory[11] = 32'h0000_10b7; // lui x1, 1
    instruction_memory[12] = 32'h8020_8093; // addi x1, x1, -2046 = 0x802
    instruction_memory[13] = 32'h3000_9073; // csrw mstatus, x1 (MPP=S, SIE=1, MIE=0)
    instruction_memory[14] = 32'h3020_0073; // mret
    instruction_memory[16] = 32'h0000_0013; // interrupted S-mode nop
    instruction_memory[17] = 32'h0000_006f; // S-mode loop

    // Machine timer handler: disable MTIE, inject STIP, return to S-mode.
    instruction_memory[32] = 32'h0800_0093; // li x1, 0x80
    instruction_memory[33] = 32'h3040_b073; // csrc mie, x1
    instruction_memory[34] = 32'h0200_0093; // li x1, 0x20
    instruction_memory[35] = 32'h3440_a073; // csrs mip, x1
    instruction_memory[36] = 32'h3020_0073; // mret

    instruction_memory[48] = 32'h0090_0193; // S handler: li x3, 9
    instruction_memory[49] = 32'h0000_006f; // loop

    @(posedge clk);
    #1;
    reset = 1'b0;

    for (cycle_count = 0; cycle_count < 80 && privilege_mode !== 2'b01;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
    end
    if (privilege_mode !== 2'b01) begin
      $display("FAIL did not enter S-mode: privilege=%b", privilege_mode);
      failures = failures + 1;
    end
    if (dut.csr_file.mstatus[3] !== 1'b0 ||
        dut.supervisor_interrupt_pending_bits[5] !== 1'b0) begin
      $display("FAIL precondition MIE=%b STIP=%b",
               dut.csr_file.mstatus[3], dut.supervisor_interrupt_pending_bits[5]);
      failures = failures + 1;
    end

    timer_interrupt = 1'b1;
    for (cycle_count = 0; cycle_count < 80 && !supervisor_timer_seen;
         cycle_count = cycle_count + 1) begin
      @(posedge clk);
      #1;
      if (commit_trap_valid && commit_trap_cause == 64'h8000_0000_0000_0007) begin
        if (supervisor_timer_seen || privilege_mode !== 2'b11) begin
          $display("FAIL machine timer ordering/target privilege=%b", privilege_mode);
          failures = failures + 1;
        end
        machine_timer_seen = 1'b1;
      end
      if (commit_trap_valid && commit_trap_cause == 64'h8000_0000_0000_0005) begin
        if (!machine_timer_seen || privilege_mode !== 2'b01) begin
          $display("FAIL supervisor timer arrived before M handoff or wrong privilege=%b", privilege_mode);
          failures = failures + 1;
        end
        supervisor_timer_seen = 1'b1;
      end
    end
    timer_interrupt = 1'b0;
    @(posedge clk);
    #1;
    // The M handler's csrs mip ran while MTIP was high; the read-modify-write
    // must not have latched the hardware MTIP bit into software state.
    if (dut.machine_interrupt_pending_bits[7] !== 1'b0 ||
        dut.csr_file.mip[5] !== 1'b1) begin
      $display("FAIL mip after handoff: MTIP=%b STIP=%b",
               dut.machine_interrupt_pending_bits[7], dut.csr_file.mip[5]);
      failures = failures + 1;
    end

    if (!machine_timer_seen || !supervisor_timer_seen ||
        dut.csr_file.mcause !== 64'h8000_0000_0000_0007 ||
        dut.csr_file.scause !== 64'h8000_0000_0000_0005) begin
      $display("FAIL OpenSBI timer handoff Mseen=%b Sseen=%b mcause=%h scause=%h",
               machine_timer_seen, supervisor_timer_seen,
               dut.csr_file.mcause, dut.csr_file.scause);
      failures = failures + 1;
    end

    if (failures != 0) $fatal(1, "SIM FAIL: %0d supervisor interrupt checks failed", failures);
    $display("SIM PASS: rv64_core OpenSBI MTIP-to-STIP timer handoff");
    $finish;
  end
endmodule
