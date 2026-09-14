`timescale 1ns / 1ps

module tb_rv64_ddr3_axi_adapter;
  localparam logic [63:0] DDR_BASE_ADDRESS = 64'h0000_0000_8000_0000;

  logic clk;
  logic reset;
  logic calibrated;
  logic request_valid;
  logic request_write;
  logic [63:0] request_address;
  logic [63:0] request_write_data;
  logic [7:0] request_write_strobe;
  logic request_ready;
  logic [63:0] response_read_data;
  logic response_error;
  logic [3:0] axi_awid;
  logic [30:0] axi_awaddr;
  logic [7:0] axi_awlen;
  logic [2:0] axi_awsize;
  logic [1:0] axi_awburst;
  logic axi_awvalid;
  logic axi_awready;
  logic [511:0] axi_wdata;
  logic [63:0] axi_wstrb;
  logic axi_wlast;
  logic axi_wvalid;
  logic axi_wready;
  logic [3:0] axi_bid;
  logic [1:0] axi_bresp;
  logic axi_bvalid;
  logic axi_bready;
  logic [3:0] axi_arid;
  logic [30:0] axi_araddr;
  logic [7:0] axi_arlen;
  logic [2:0] axi_arsize;
  logic [1:0] axi_arburst;
  logic axi_arvalid;
  logic axi_arready;
  logic [3:0] axi_rid;
  logic [511:0] axi_rdata;
  logic [1:0] axi_rresp;
  logic axi_rlast;
  logic axi_rvalid;
  logic axi_rready;
  integer failures;

  rv64_ddr3_axi_adapter dut (.*);
  always #5 clk = ~clk;

  task automatic check_condition(input logic condition, input [511:0] message);
    begin
      if (!condition) begin
        $display("FAIL %0s", message);
        failures = failures + 1;
      end
    end
  endtask

  task automatic begin_request(
    input logic write,
    input logic [63:0] address,
    input logic [63:0] write_data,
    input logic [7:0] write_strobe
  );
    begin
      request_valid = 1'b1;
      request_write = write;
      request_address = address;
      request_write_data = write_data;
      request_write_strobe = write_strobe;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic finish_request(input logic expected_error, input logic [63:0] expected_data);
    begin
      while (!request_ready) begin
        @(posedge clk);
        #1;
      end
      check_condition(response_error === expected_error, "response error");
      if (!expected_error && !request_write) begin
        check_condition(response_read_data === expected_data, "response read data");
      end
      @(posedge clk);
      #1;
      request_valid = 1'b0;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic send_read_response(
    input logic [511:0] data,
    input logic [1:0] response,
    input logic [3:0] identifier,
    input logic last
  );
    begin
      while (!axi_rready) begin
        @(posedge clk);
        #1;
      end
      axi_rdata = data;
      axi_rresp = response;
      axi_rid = identifier;
      axi_rlast = last;
      axi_rvalid = 1'b1;
      @(posedge clk);
      #1;
      axi_rvalid = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b1;
    calibrated = 1'b1;
    request_valid = 1'b0;
    request_write = 1'b0;
    request_address = '0;
    request_write_data = '0;
    request_write_strobe = '0;
    axi_awready = 1'b0;
    axi_wready = 1'b0;
    axi_bid = '0;
    axi_bresp = '0;
    axi_bvalid = 1'b0;
    axi_arready = 1'b0;
    axi_rid = '0;
    axi_rdata = '0;
    axi_rresp = '0;
    axi_rlast = 1'b0;
    axi_rvalid = 1'b0;
    failures = 0;

    @(posedge clk);
    #1;
    reset = 1'b0;

    calibrated = 1'b0;
    begin_request(1'b0, DDR_BASE_ADDRESS, '0, '0);
    check_condition(!axi_awvalid && !axi_arvalid, "uncalibrated request has no AXI transaction");
    finish_request(1'b1, '0);
    calibrated = 1'b1;

    begin_request(1'b0, DDR_BASE_ADDRESS + 64'h28, '0, '0);
    while (!axi_arvalid) begin
      @(posedge clk);
      #1;
    end
    check_condition(axi_araddr == 31'd0 && axi_arid == '0 && axi_arlen == 8'd0 &&
                    axi_arsize == 3'd6 && axi_arburst == 2'b01,
                    "read request maps to one aligned 64-byte AXI beat");
    @(posedge clk);
    #1;
    axi_arready = 1'b1;
    @(posedge clk);
    #1;
    axi_arready = 1'b0;
    send_read_response({64'h7788_99aa_bbcc_ddee, 64'h0011_2233_4455_6677,
                        64'h0123_4567_89ab_cdef, 64'hfeed_face_cafe_babe,
                        64'h1020_3040_5060_7080, 64'h8899_aabb_ccdd_eeff,
                        64'h1357_9bdf_2468_ace0, 64'h0bad_f00d_dead_beef},
                       2'b00, '0, 1'b1);
    finish_request(1'b0, 64'h0123_4567_89ab_cdef);

    begin_request(1'b1, DDR_BASE_ADDRESS + 64'h28, 64'h0123_4567_89ab_cdef, 8'ha5);
    while (!axi_awvalid) begin
      @(posedge clk);
      #1;
    end
    check_condition(axi_awaddr == 31'd0 && axi_awid == '0 && axi_awlen == 8'd0 &&
                    axi_awsize == 3'd6 && axi_awburst == 2'b01,
                    "write address maps to one aligned 64-byte AXI beat");
    axi_awready = 1'b1;
    @(posedge clk);
    #1;
    axi_awready = 1'b0;
    while (!axi_wvalid) begin
      @(posedge clk);
      #1;
    end
    check_condition(axi_wdata[5*64 +: 64] == 64'h0123_4567_89ab_cdef &&
                    axi_wdata == ({{448{1'b0}}, 64'h0123_4567_89ab_cdef} << (5*64)) &&
                    axi_wstrb == (64'ha5 << (5*8)) && axi_wlast,
                    "write payload occupies its addressed 8-byte lane");
    axi_wready = 1'b1;
    @(posedge clk);
    #1;
    axi_wready = 1'b0;
    while (!axi_bready) begin
      @(posedge clk);
      #1;
    end
    axi_bid = '0;
    axi_bresp = 2'b00;
    axi_bvalid = 1'b1;
    @(posedge clk);
    #1;
    axi_bvalid = 1'b0;
    finish_request(1'b0, '0);

    begin_request(1'b0, DDR_BASE_ADDRESS + 64'h8000_0000, '0, '0);
    check_condition(!axi_awvalid && !axi_arvalid, "out of range request has no AXI transaction");
    finish_request(1'b1, '0);

    begin_request(1'b0, DDR_BASE_ADDRESS + 64'h08, '0, '0);
    while (!axi_arvalid) begin
      @(posedge clk);
      #1;
    end
    axi_arready = 1'b1;
    @(posedge clk);
    #1;
    axi_arready = 1'b0;
    send_read_response('0, 2'b10, '0, 1'b1);
    finish_request(1'b1, '0);

    begin_request(1'b1, DDR_BASE_ADDRESS + 64'h10, 64'hffff_ffff_ffff_ffff, 8'hff);
    while (!axi_awvalid) begin
      @(posedge clk);
      #1;
    end
    reset = 1'b1;
    @(posedge clk);
    #1;
    check_condition(!axi_awvalid && !axi_wvalid && !axi_arvalid && !axi_bready && !axi_rready &&
                    !request_ready, "reset drops a pending transaction without a response");
    reset = 1'b0;
    request_valid = 1'b0;

    if (failures != 0) $fatal(1, "SIM FAIL: %0d AXI adapter checks failed", failures);
    $display("SIM PASS: rv64_ddr3_axi_adapter protocol regression");
    $finish;
  end
endmodule
