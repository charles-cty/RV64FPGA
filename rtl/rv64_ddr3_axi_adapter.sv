module rv64_ddr3_axi_adapter #(
  parameter logic [63:0] DDR_BASE_ADDRESS = 64'h0000_0000_8000_0000,
  parameter logic [63:0] DDR_SIZE_BYTES = 64'h0000_0000_8000_0000,
  parameter integer AXI_ADDRESS_WIDTH = 31,
  parameter integer AXI_ID_WIDTH = 4
) (
  input  logic                         clk,
  input  logic                         reset,
  input  logic                         calibrated,
  input  logic                         request_valid,
  input  logic                         request_write,
  input  logic [63:0]                  request_address,
  input  logic [63:0]                  request_write_data,
  input  logic [7:0]                   request_write_strobe,
  output logic                         request_ready,
  output logic [63:0]                  response_read_data,
  output logic                         response_error,
  output logic [AXI_ID_WIDTH-1:0]      axi_awid,
  output logic [AXI_ADDRESS_WIDTH-1:0] axi_awaddr,
  output logic [7:0]                   axi_awlen,
  output logic [2:0]                   axi_awsize,
  output logic [1:0]                   axi_awburst,
  output logic                         axi_awvalid,
  input  logic                         axi_awready,
  output logic [511:0]                 axi_wdata,
  output logic [63:0]                  axi_wstrb,
  output logic                         axi_wlast,
  output logic                         axi_wvalid,
  input  logic                         axi_wready,
  input  logic [AXI_ID_WIDTH-1:0]      axi_bid,
  input  logic [1:0]                   axi_bresp,
  input  logic                         axi_bvalid,
  output logic                         axi_bready,
  output logic [AXI_ID_WIDTH-1:0]      axi_arid,
  output logic [AXI_ADDRESS_WIDTH-1:0] axi_araddr,
  output logic [7:0]                   axi_arlen,
  output logic [2:0]                   axi_arsize,
  output logic [1:0]                   axi_arburst,
  output logic                         axi_arvalid,
  input  logic                         axi_arready,
  input  logic [AXI_ID_WIDTH-1:0]      axi_rid,
  input  logic [511:0]                 axi_rdata,
  input  logic [1:0]                   axi_rresp,
  input  logic                         axi_rlast,
  input  logic                         axi_rvalid,
  output logic                         axi_rready
);
  typedef enum logic [2:0] {
    IDLE,
    WRITE_ADDRESS,
    WRITE_DATA,
    WRITE_RESPONSE,
    READ_ADDRESS,
    READ_RESPONSE,
    RESPONSE
  } state_t;

  state_t state;
  logic [63:0] request_address_latched;
  logic [63:0] request_write_data_latched;
  logic [7:0] request_write_strobe_latched;
  logic [63:0] response_read_data_latched;
  logic response_error_latched;
  logic request_address_valid;
  logic [63:0] axi_address;

  always_comb begin
    request_address_valid = request_address >= DDR_BASE_ADDRESS &&
                            request_address < DDR_BASE_ADDRESS + DDR_SIZE_BYTES &&
                            request_address[2:0] == 3'b000;
    axi_address = (request_address_latched - DDR_BASE_ADDRESS) & ~64'h3f;

    request_ready = state == RESPONSE;
    response_read_data = response_read_data_latched;
    response_error = request_ready && response_error_latched;

    axi_awid = '0;
    axi_awaddr = axi_address[AXI_ADDRESS_WIDTH-1:0];
    axi_awlen = 8'd0;
    axi_awsize = 3'd6;
    axi_awburst = 2'b01;
    axi_awvalid = state == WRITE_ADDRESS;

    axi_wdata = {448'b0, request_write_data_latched} <<
                (request_address_latched[5:3] * 64);
    axi_wstrb = {56'b0, request_write_strobe_latched} <<
                (request_address_latched[5:3] * 8);
    axi_wlast = 1'b1;
    axi_wvalid = state == WRITE_DATA;
    axi_bready = state == WRITE_RESPONSE;

    axi_arid = '0;
    axi_araddr = axi_address[AXI_ADDRESS_WIDTH-1:0];
    axi_arlen = 8'd0;
    axi_arsize = 3'd6;
    axi_arburst = 2'b01;
    axi_arvalid = state == READ_ADDRESS;
    axi_rready = state == READ_RESPONSE;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      state <= IDLE;
      request_address_latched <= '0;
      request_write_data_latched <= '0;
      request_write_strobe_latched <= '0;
      response_read_data_latched <= '0;
      response_error_latched <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          if (request_valid) begin
            request_address_latched <= request_address;
            request_write_data_latched <= request_write_data;
            request_write_strobe_latched <= request_write_strobe;
            response_read_data_latched <= '0;
            response_error_latched <= !calibrated || !request_address_valid;
            if (!calibrated || !request_address_valid) begin
              state <= RESPONSE;
            end else if (request_write) begin
              state <= WRITE_ADDRESS;
            end else begin
              state <= READ_ADDRESS;
            end
          end
        end
        WRITE_ADDRESS: begin
          if (axi_awready) begin
            state <= WRITE_DATA;
          end
        end
        WRITE_DATA: begin
          if (axi_wready) begin
            state <= WRITE_RESPONSE;
          end
        end
        WRITE_RESPONSE: begin
          if (axi_bvalid) begin
            response_error_latched <= axi_bid != '0 || axi_bresp != 2'b00;
            state <= RESPONSE;
          end
        end
        READ_ADDRESS: begin
          if (axi_arready) begin
            state <= READ_RESPONSE;
          end
        end
        READ_RESPONSE: begin
          if (axi_rvalid) begin
            response_read_data_latched <= axi_rdata >> (request_address_latched[5:3] * 64);
            response_error_latched <= axi_rid != '0 || axi_rresp != 2'b00 || !axi_rlast;
            state <= RESPONSE;
          end
        end
        RESPONSE: begin
          if (request_valid) begin
            state <= IDLE;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
