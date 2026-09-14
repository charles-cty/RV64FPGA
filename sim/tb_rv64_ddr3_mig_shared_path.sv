`timescale 1ns / 1ps

module tb_rv64_ddr3_mig_shared_path;
  logic cpu_clk, cpu_reset, i_valid, i_write, i_ready, i_error;
  logic [63:0] i_address, i_write_data, i_read_data;
  logic [7:0] i_write_strobe;
  logic d_valid, d_write, d_ready, d_error;
  logic [63:0] d_address, d_write_data, d_read_data;
  logic [7:0] d_write_strobe;
  logic ui_clk, ui_reset, init_calib_complete;
  logic [3:0] axi_awid, axi_bid, axi_arid, axi_rid;
  logic [30:0] axi_awaddr, axi_araddr;
  logic [7:0] axi_awlen, axi_arlen;
  logic [2:0] axi_awsize, axi_arsize;
  logic [1:0] axi_awburst, axi_bresp, axi_arburst, axi_rresp;
  logic axi_awvalid, axi_awready, axi_wlast, axi_wvalid, axi_wready, axi_bvalid, axi_bready;
  logic axi_arvalid, axi_arready, axi_rlast, axi_rvalid, axi_rready;
  logic [511:0] axi_wdata, axi_rdata;
  logic [63:0] axi_wstrb;
  integer failures;

  rv64_ddr3_mig_shared_path dut (.*,
    .instruction_request_valid(i_valid), .instruction_request_write(i_write),
    .instruction_request_address(i_address), .instruction_request_write_data(i_write_data),
    .instruction_request_write_strobe(i_write_strobe), .instruction_request_ready(i_ready),
    .instruction_response_read_data(i_read_data), .instruction_response_error(i_error),
    .data_request_valid(d_valid), .data_request_write(d_write),
    .data_request_address(d_address), .data_request_write_data(d_write_data),
    .data_request_write_strobe(d_write_strobe), .data_request_ready(d_ready),
    .data_response_read_data(d_read_data), .data_response_error(d_error));
  always #5 cpu_clk = ~cpu_clk;
  always #3.5 ui_clk = ~ui_clk;

  task automatic check(input logic condition, input [511:0] message);
    begin if (!condition) begin $display("FAIL %0s", message); failures = failures + 1; end end
  endtask

  task automatic clear_instruction;
    begin @(posedge cpu_clk); #1; i_valid = 1'b0; end
  endtask

  initial begin
    cpu_clk = 1'b0; ui_clk = 1'b0; cpu_reset = 1'b1; ui_reset = 1'b1;
    init_calib_complete = 1'b1; failures = 0;
    i_valid = 1'b0; i_write = 1'b0; i_address = '0; i_write_data = '0; i_write_strobe = '0;
    d_valid = 1'b0; d_write = 1'b0; d_address = '0; d_write_data = '0; d_write_strobe = '0;
    axi_awready = 1'b0; axi_wready = 1'b0; axi_bid = '0; axi_bresp = '0; axi_bvalid = 1'b0;
    axi_arready = 1'b0; axi_rid = '0; axi_rdata = '0; axi_rresp = '0; axi_rlast = 1'b0; axi_rvalid = 1'b0;
    @(posedge cpu_clk); #1; cpu_reset = 1'b0;
    @(posedge ui_clk); #1; ui_reset = 1'b0;

    i_valid = 1'b1; i_address = 64'h8000_0020;
    while (!axi_arvalid) begin @(posedge ui_clk); #1; end
    check(axi_araddr == 31'd0 && axi_arsize == 3'd6, "shared path instruction AXI read");
    axi_arready = 1'b1; @(posedge ui_clk); #1; axi_arready = 1'b0;
    while (!axi_rready) begin @(posedge ui_clk); #1; end
    axi_rdata = {192'b0, 64'h0123_4567_89ab_cdef, 256'b0}; axi_rid = '0; axi_rresp = 0; axi_rlast = 1'b1; axi_rvalid = 1'b1;
    @(posedge ui_clk); #1; axi_rvalid = 1'b0;
    while (!i_ready) begin @(posedge cpu_clk); #1; end
    check(!i_error && i_read_data === 64'h0123_4567_89ab_cdef, "shared path instruction response");
    clear_instruction();

    d_valid = 1'b1; d_write = 1'b1; d_address = 64'h8000_0038;
    d_write_data = 64'hfeed_face_cafe_babe; d_write_strobe = 8'h81;
    while (!axi_awvalid) begin @(posedge ui_clk); #1; end
    axi_awready = 1'b1; @(posedge ui_clk); #1; axi_awready = 1'b0;
    while (!axi_wvalid) begin @(posedge ui_clk); #1; end
    check(axi_wstrb == (64'h81 << 56), "shared path data write lane");
    axi_wready = 1'b1; @(posedge ui_clk); #1; axi_wready = 1'b0;
    while (!axi_bready) begin @(posedge ui_clk); #1; end
    axi_bresp = 0; axi_bid = 0; axi_bvalid = 1'b1; @(posedge ui_clk); #1; axi_bvalid = 1'b0;
    while (!d_ready) begin @(posedge cpu_clk); #1; end
    check(!d_error, "shared path data response");
    @(posedge cpu_clk); #1; d_valid = 1'b0;

    init_calib_complete = 1'b0; d_valid = 1'b1; d_write = 1'b0; d_address = 64'h8000_0000;
    while (!d_ready) begin @(posedge cpu_clk); #1; end
    check(d_error && !axi_awvalid && !axi_arvalid, "shared path calibration error without AXI");
    @(posedge cpu_clk); #1; d_valid = 1'b0;
    if (failures != 0) $fatal(1, "SIM FAIL: %0d shared MIG path checks failed", failures);
    $display("SIM PASS: rv64_ddr3_mig_shared_path integration regression");
    $finish;
  end
endmodule
