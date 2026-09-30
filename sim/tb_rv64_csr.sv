`timescale 1ns / 1ps

module tb_rv64_csr;
  logic clk;
  logic reset;
  logic [11:0] read_address;
  logic [63:0] read_data;
  logic write_enable;
  logic [11:0] write_address;
  logic [63:0] write_data;
  logic trap_to_machine;
  logic [63:0] trap_pc;
  logic [63:0] trap_cause;
  logic [63:0] trap_value;
  logic [1:0] current_privilege;
  logic return_from_machine;
  logic return_from_supervisor;
  logic software_interrupt;
  logic timer_interrupt;
  logic external_interrupt;
  logic machine_interrupt_enable;
  logic [63:0] machine_interrupt_enable_bits;
  logic [63:0] machine_interrupt_pending_bits;
  logic [63:0] interrupt_delegation_bits;
  logic supervisor_interrupt_enable;
  logic [63:0] supervisor_interrupt_enable_bits;
  logic [63:0] supervisor_interrupt_pending_bits;
  logic [63:0] machine_trap_vector;
  logic [63:0] machine_exception_pc;
  logic [1:0] privilege_mode;
  logic [1:0] data_privilege;
  logic [63:0] satp_value;
  logic sum_enable;
  logic mxr_enable;
  logic [63:0] trap_vector;
  logic [63:0] trap_exception_pc;
  logic trap_delegated;
  logic [63:0] counter_value;
  integer failures;

  rv64_csr dut (.*);
  always #5 clk = ~clk;

  task automatic expect_read(input logic [511:0] name, input logic [11:0] address, input logic [63:0] expected);
    begin
      read_address = address;
      #1;
      if (read_data !== expected) begin
        $display("FAIL %0s: address=%h got=%h expected=%h", name, address, read_data, expected);
        failures = failures + 1;
      end
    end
  endtask

  task automatic write_csr(input logic [11:0] address, input logic [63:0] value);
    begin
      write_address = address;
      write_data = value;
      write_enable = 1'b1;
      @(posedge clk);
      #1;
      write_enable = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    read_address = '0;
    write_enable = 1'b0;
    write_address = '0;
    write_data = '0;
    trap_to_machine = 1'b0;
    trap_pc = '0;
    trap_cause = '0;
    trap_value = '0;
    current_privilege = 2'b01;
    return_from_machine = 1'b0;
    return_from_supervisor = 1'b0;
    software_interrupt = 1'b0;
    timer_interrupt = 1'b0;
    external_interrupt = 1'b0;
    failures = 0;

    @(posedge clk);
    #1;
    reset = 1'b0;
    expect_read("reset mtvec", 12'h305, 64'd0);
    expect_read("machine vendor id", 12'hF11, 64'd0);
    expect_read("machine architecture id", 12'hF12, 64'h0000_0000_5256_3634);
    expect_read("machine implementation id", 12'hF13, 64'h0000_0000_0000_0001);
    expect_read("machine hart id", 12'hF14, 64'd0);
    expect_read("misa advertises RV64IMASU", 12'h301, 64'h8000_0000_0014_1101);
    read_address = 12'hC00;
    #1;
    counter_value = read_data;
    expect_read("cycle aliases time", 12'hC01, counter_value);
    timer_interrupt = 1'b1;
    expect_read("undelegated timer hidden from sip", 12'h144, 64'd0);
    write_csr(12'h303, 64'h0000_0000_0000_0020);
    expect_read("physical mtip is not exposed as stip", 12'h144, 64'd0);
    write_csr(12'h344, 64'h0000_0000_0000_0020);
    expect_read("software-pending stip appears in sip", 12'h144, 64'h0000_0000_0000_0020);
    write_csr(12'h104, 64'h0000_0000_0000_0020);
    expect_read("sie is delegated mie view", 12'h104, 64'h0000_0000_0000_0020);
    // OpenSBI sets STIP with csrs while the physical MTIP line is high.  The
    // read-modify-write must not latch MTIP into the software-writable mip.
    write_csr(12'h344, 64'h0000_0000_0000_08a8);
    timer_interrupt = 1'b0;
    expect_read("mip MTIP/MSIP/MEIP are not software writable", 12'h344,
                64'h0000_0000_0000_0020);
    write_csr(12'h303, 64'h0000_0000_0000_0022);
    write_csr(12'h144, 64'h0000_0000_0000_0002);
    expect_read("sip writes only SSIP", 12'h344, 64'h0000_0000_0000_0022);
    write_csr(12'h144, 64'h0000_0000_0000_0000);
    expect_read("sip clear preserves STIP", 12'h344, 64'h0000_0000_0000_0020);
    write_csr(12'h344, 64'd0);
    write_csr(12'h303, 64'd0);

    write_csr(12'h305, 64'h0000_0000_0000_1001);
    expect_read("mtvec write", 12'h305, 64'h1001);
    write_csr(12'h301, 64'hffff_ffff_ffff_ffff);
    expect_read("misa is read only", 12'h301, 64'h8000_0000_0014_1101);
    write_csr(12'h180, 64'h8123_4567_89ab_cdef);
    expect_read("satp accepts Sv39", 12'h180, 64'h8123_4567_89ab_cdef);
    write_csr(12'h180, 64'hafed_cba9_8765_4321);
    expect_read("satp ignores unsupported Sv57 write", 12'h180,
                64'h8123_4567_89ab_cdef);
    write_csr(12'h180, 64'h0000_0000_0000_0000);
    expect_read("satp accepts Bare", 12'h180, 64'h0000_0000_0000_0000);
    write_csr(12'h100, 64'hffff_ffff_ffff_ffff);
    expect_read("sstatus write is masked", 12'h100, 64'h8000_0003_000d_e162);
    write_csr(12'h300, 64'd0);
    write_csr(12'h300, 64'h0000_0000_0008_0000);
    if (mxr_enable !== 1'b1) begin
      $display("FAIL mstatus.MXR output is not asserted");
      failures = failures + 1;
    end
    write_csr(12'h300, 64'd0);
    write_csr(12'h300, 64'h0000_0000_0002_0800);
    if (data_privilege !== 2'b01 || privilege_mode !== 2'b11) begin
      $display("FAIL MPRV MPP=S data privilege: current=%b data=%b", privilege_mode, data_privilege);
      failures = failures + 1;
    end
    write_csr(12'h300, 64'h0000_0000_0002_0000);
    if (data_privilege !== 2'b00 || privilege_mode !== 2'b11) begin
      $display("FAIL MPRV MPP=U data privilege: current=%b data=%b", privilege_mode, data_privilege);
      failures = failures + 1;
    end
    write_csr(12'h300, 64'd0);
    if (data_privilege !== 2'b11) begin
      $display("FAIL cleared MPRV did not restore M data privilege: data=%b", data_privilege);
      failures = failures + 1;
    end
    write_csr(12'h300, 64'h0000_0000_0002_0800);
    trap_pc = 64'h0000_0000_0000_0100;
    trap_cause = 64'd2;
    trap_value = 64'd0;
    trap_to_machine = 1'b1;
    @(posedge clk);
    #1;
    trap_to_machine = 1'b0;
    return_from_machine = 1'b1;
    @(posedge clk);
    #1;
    return_from_machine = 1'b0;
    if (dut.mstatus[17] !== 1'b0 || privilege_mode !== 2'b01) begin
      $display("FAIL MRET did not clear MPRV: mstatus.MPRV=%b privilege=%b", dut.mstatus[17], privilege_mode);
      failures = failures + 1;
    end
    write_csr(12'h300, 64'd0);

    trap_pc = 64'h0000_0000_8000_0040;
    trap_cause = 64'h0000_0000_0000_000b;
    trap_value = 64'h0000_0000_dead_beef;
    trap_to_machine = 1'b1;
    @(posedge clk);
    #1;
    trap_to_machine = 1'b0;
    expect_read("trap saves mepc", 12'h341, trap_pc);
    expect_read("trap saves mcause", 12'h342, trap_cause);
    expect_read("trap saves mtval", 12'h343, trap_value);
    expect_read("trap clears mie and records privilege", 12'h300, 64'h0000_0000_0000_0800);

    return_from_machine = 1'b1;
    @(posedge clk);
    #1;
    return_from_machine = 1'b0;
    expect_read("mret restores mstatus state", 12'h300, 64'h0000_0000_0000_0080);

    write_csr(12'h302, 64'h0000_0000_0000_0200);
    write_csr(12'h105, 64'h0000_0000_0000_2001);
    trap_pc = 64'h0000_0000_8000_0080;
    trap_cause = 64'd9;
    trap_value = 64'h0000_0000_cafe_babe;
    trap_to_machine = 1'b1;
    @(posedge clk);
    #1;
    trap_to_machine = 1'b0;
    expect_read("delegated trap saves sepc", 12'h141, trap_pc);
    expect_read("delegated trap saves scause", 12'h142, trap_cause);
    if (!trap_delegated || trap_vector !== 64'h0000_0000_0000_2001 ||
        privilege_mode !== 2'b01) begin
      $display("FAIL delegated S trap: delegated=%b vector=%h privilege=%b",
               trap_delegated, trap_vector, privilege_mode);
      failures = failures + 1;
    end

    return_from_supervisor = 1'b1;
    @(posedge clk);
    #1;
    return_from_supervisor = 1'b0;
    if (privilege_mode !== 2'b01) begin
      $display("FAIL SRET did not return to S mode: privilege=%b", privilege_mode);
      failures = failures + 1;
    end

    current_privilege = 2'b00;
    trap_pc = 64'h0000_0000_8000_00c0;
    trap_cause = 64'd9;
    trap_value = 64'h0000_0000_1234_5678;
    trap_to_machine = 1'b1;
    @(posedge clk);
    #1;
    trap_to_machine = 1'b0;
    if (privilege_mode !== 2'b01 || dut.mstatus[8] !== 1'b0) begin
      $display("FAIL delegated U trap state: privilege=%b spp=%b", privilege_mode, dut.mstatus[8]);
      failures = failures + 1;
    end
    return_from_supervisor = 1'b1;
    @(posedge clk);
    #1;
    return_from_supervisor = 1'b0;
    if (privilege_mode !== 2'b00) begin
      $display("FAIL SRET did not return to U mode: privilege=%b", privilege_mode);
      failures = failures + 1;
    end

    if (failures != 0) begin
      $display("SIM FAIL: %0d CSR checks failed", failures);
      $fatal(1);
    end
    $display("SIM PASS: rv64_csr trap and access regression");
    $finish;
  end
endmodule
