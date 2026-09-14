module rv64_ddr3_mig_shared_path #(
  parameter logic [63:0] DDR_BASE_ADDRESS = 64'h0000_0000_8000_0000,
  parameter logic [63:0] DDR_SIZE_BYTES = 64'h0000_0000_8000_0000,
  parameter integer AXI_ADDRESS_WIDTH = 31,
  parameter integer AXI_ID_WIDTH = 4
) (
  input logic cpu_clk,
  input logic cpu_reset,
  input logic instruction_request_valid,
  input logic instruction_request_write,
  input logic [63:0] instruction_request_address,
  input logic [63:0] instruction_request_write_data,
  input logic [7:0] instruction_request_write_strobe,
  output logic instruction_request_ready,
  output logic [63:0] instruction_response_read_data,
  output logic instruction_response_error,
  input logic data_request_valid,
  input logic data_request_write,
  input logic [63:0] data_request_address,
  input logic [63:0] data_request_write_data,
  input logic [7:0] data_request_write_strobe,
  output logic data_request_ready,
  output logic [63:0] data_response_read_data,
  output logic data_response_error,
  input logic ui_clk,
  input logic ui_reset,
  input logic init_calib_complete,
  output logic [AXI_ID_WIDTH-1:0] axi_awid,
  output logic [AXI_ADDRESS_WIDTH-1:0] axi_awaddr,
  output logic [7:0] axi_awlen,
  output logic [2:0] axi_awsize,
  output logic [1:0] axi_awburst,
  output logic axi_awvalid,
  input logic axi_awready,
  output logic [511:0] axi_wdata,
  output logic [63:0] axi_wstrb,
  output logic axi_wlast,
  output logic axi_wvalid,
  input logic axi_wready,
  input logic [AXI_ID_WIDTH-1:0] axi_bid,
  input logic [1:0] axi_bresp,
  input logic axi_bvalid,
  output logic axi_bready,
  output logic [AXI_ID_WIDTH-1:0] axi_arid,
  output logic [AXI_ADDRESS_WIDTH-1:0] axi_araddr,
  output logic [7:0] axi_arlen,
  output logic [2:0] axi_arsize,
  output logic [1:0] axi_arburst,
  output logic axi_arvalid,
  input logic axi_arready,
  input logic [AXI_ID_WIDTH-1:0] axi_rid,
  input logic [511:0] axi_rdata,
  input logic [1:0] axi_rresp,
  input logic axi_rlast,
  input logic axi_rvalid,
  output logic axi_rready
);
  logic cpu_memory_request_valid;
  logic cpu_memory_request_write;
  logic [63:0] cpu_memory_request_address;
  logic [63:0] cpu_memory_request_write_data;
  logic [7:0] cpu_memory_request_write_strobe;
  logic cpu_memory_request_ready;
  logic [63:0] cpu_memory_response_read_data;
  logic cpu_memory_response_error;
  logic ui_request_valid;
  logic ui_request_write;
  logic [63:0] ui_request_address;
  logic [63:0] ui_request_write_data;
  logic [7:0] ui_request_write_strobe;
  logic ui_request_ready;
  logic [63:0] ui_response_read_data;
  logic ui_response_error;

  rv64_ddr3_arbiter arbiter (
    .clk(cpu_clk), .reset(cpu_reset),
    .instruction_request_valid(instruction_request_valid),
    .instruction_request_write(instruction_request_write),
    .instruction_request_address(instruction_request_address),
    .instruction_request_write_data(instruction_request_write_data),
    .instruction_request_write_strobe(instruction_request_write_strobe),
    .instruction_request_ready(instruction_request_ready),
    .instruction_response_read_data(instruction_response_read_data),
    .instruction_response_error(instruction_response_error),
    .data_request_valid(data_request_valid),
    .data_request_write(data_request_write),
    .data_request_address(data_request_address),
    .data_request_write_data(data_request_write_data),
    .data_request_write_strobe(data_request_write_strobe),
    .data_request_ready(data_request_ready),
    .data_response_read_data(data_response_read_data),
    .data_response_error(data_response_error),
    .memory_request_valid(cpu_memory_request_valid),
    .memory_request_write(cpu_memory_request_write),
    .memory_request_address(cpu_memory_request_address),
    .memory_request_write_data(cpu_memory_request_write_data),
    .memory_request_write_strobe(cpu_memory_request_write_strobe),
    .memory_request_ready(cpu_memory_request_ready),
    .memory_response_read_data(cpu_memory_response_read_data),
    .memory_response_error(cpu_memory_response_error)
  );

  rv64_async_memory_bridge bridge (
    .cpu_clk(cpu_clk), .cpu_reset(cpu_reset),
    .cpu_request_valid(cpu_memory_request_valid),
    .cpu_request_write(cpu_memory_request_write),
    .cpu_request_address(cpu_memory_request_address),
    .cpu_request_write_data(cpu_memory_request_write_data),
    .cpu_request_write_strobe(cpu_memory_request_write_strobe),
    .cpu_request_ready(cpu_memory_request_ready),
    .cpu_response_read_data(cpu_memory_response_read_data),
    .cpu_response_error(cpu_memory_response_error),
    .ui_clk(ui_clk), .ui_reset(ui_reset),
    .ui_request_valid(ui_request_valid),
    .ui_request_write(ui_request_write),
    .ui_request_address(ui_request_address),
    .ui_request_write_data(ui_request_write_data),
    .ui_request_write_strobe(ui_request_write_strobe),
    .ui_request_ready(ui_request_ready),
    .ui_response_read_data(ui_response_read_data),
    .ui_response_error(ui_response_error)
  );

  rv64_ddr3_axi_adapter #(
    .DDR_BASE_ADDRESS(DDR_BASE_ADDRESS), .DDR_SIZE_BYTES(DDR_SIZE_BYTES),
    .AXI_ADDRESS_WIDTH(AXI_ADDRESS_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH)
  ) adapter (
    .clk(ui_clk), .reset(ui_reset), .calibrated(init_calib_complete),
    .request_valid(ui_request_valid), .request_write(ui_request_write),
    .request_address(ui_request_address), .request_write_data(ui_request_write_data),
    .request_write_strobe(ui_request_write_strobe), .request_ready(ui_request_ready),
    .response_read_data(ui_response_read_data), .response_error(ui_response_error),
    .axi_awid(axi_awid), .axi_awaddr(axi_awaddr), .axi_awlen(axi_awlen),
    .axi_awsize(axi_awsize), .axi_awburst(axi_awburst), .axi_awvalid(axi_awvalid),
    .axi_awready(axi_awready), .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb),
    .axi_wlast(axi_wlast), .axi_wvalid(axi_wvalid), .axi_wready(axi_wready),
    .axi_bid(axi_bid), .axi_bresp(axi_bresp), .axi_bvalid(axi_bvalid),
    .axi_bready(axi_bready), .axi_arid(axi_arid), .axi_araddr(axi_araddr),
    .axi_arlen(axi_arlen), .axi_arsize(axi_arsize), .axi_arburst(axi_arburst),
    .axi_arvalid(axi_arvalid), .axi_arready(axi_arready), .axi_rid(axi_rid),
    .axi_rdata(axi_rdata), .axi_rresp(axi_rresp), .axi_rlast(axi_rlast),
    .axi_rvalid(axi_rvalid), .axi_rready(axi_rready)
  );
endmodule
