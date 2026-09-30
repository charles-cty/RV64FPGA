module rv64_jtag_axi_loader #(
  parameter logic [31:0] CONTROL_ADDRESS = 32'h7fff_ff00,
  parameter logic [31:0] DDR_BASE_ADDRESS = 32'h8000_0000
) (
  input  logic        clk,
  input  logic        reset,
  input  logic        axi_awvalid,
  output logic        axi_awready,
  input  logic [31:0] axi_awaddr,
  input  logic [7:0]  axi_awlen,
  input  logic [2:0]  axi_awsize,
  input  logic [1:0]  axi_awburst,
  input  logic        axi_wvalid,
  output logic        axi_wready,
  input  logic [31:0] axi_wdata,
  input  logic [3:0]  axi_wstrb,
  input  logic        axi_wlast,
  output logic        axi_bvalid,
  input  logic        axi_bready,
  output logic [1:0]  axi_bresp,
  input  logic        axi_arvalid,
  output logic        axi_arready,
  input  logic [31:0] axi_araddr,
  input  logic [7:0]  axi_arlen,
  input  logic [2:0]  axi_arsize,
  input  logic [1:0]  axi_arburst,
  output logic        axi_rvalid,
  input  logic        axi_rready,
  output logic [31:0] axi_rdata,
  output logic [1:0]  axi_rresp,
  output logic        axi_rlast,
  output logic        cpu_hold_reset,
  input  logic        memory_available,
  output logic        memory_request_valid,
  output logic        memory_request_write,
  output logic [63:0] memory_request_address,
  output logic [63:0] memory_request_write_data,
  output logic [7:0]  memory_request_write_strobe,
  input  logic        memory_request_ready,
  input  logic [63:0] memory_response_read_data,
  input  logic        memory_response_error
);
  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
  localparam logic [1:0] AXI_BURST_INCR = 2'b01;

  typedef enum logic [2:0] {IDLE, WRITE_DATA, MEMORY_WAIT, WRITE_RESPONSE, READ_RESPONSE} state_t;
  state_t state;
  logic [31:0] address_latched;
  logic [7:0] burst_length_latched;
  logic [7:0] beat_index;
  logic write_latched;
  logic loader_released;
  logic transaction_is_control;
  logic transaction_error;
  logic [31:0] write_data_latched;
  logic [3:0] write_strobe_latched;
  logic [31:0] read_data_latched;
  logic [1:0] response_latched;

  function automatic logic valid_memory_burst(
    input logic [31:0] address,
    input logic [7:0] length,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    logic [32:0] final_address;
    begin
      final_address = {1'b0, address} + ({25'b0, length} << 2);
      valid_memory_burst = address[1:0] == 2'b00 &&
                           size == 3'd2 &&
                           burst == AXI_BURST_INCR &&
                           address >= DDR_BASE_ADDRESS &&
                           !final_address[32];
    end
  endfunction

  function automatic logic valid_control_access(
    input logic [31:0] address,
    input logic [7:0] length,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    begin
      valid_control_access = address == CONTROL_ADDRESS &&
                             length == 8'd0 &&
                             size == 3'd2 &&
                             burst == AXI_BURST_INCR;
    end
  endfunction

  always_comb begin
    axi_awready = state == IDLE && !axi_arvalid;
    axi_wready = state == WRITE_DATA;
    axi_arready = state == IDLE && !axi_awvalid;
    axi_bvalid = state == WRITE_RESPONSE;
    axi_bresp = response_latched;
    axi_rvalid = state == READ_RESPONSE;
    axi_rdata = read_data_latched;
    axi_rresp = response_latched;
    axi_rlast = state == READ_RESPONSE && beat_index == burst_length_latched;
    memory_request_valid = state == MEMORY_WAIT && !transaction_is_control && !transaction_error;
    memory_request_write = write_latched;
    memory_request_address = {32'b0, address_latched[31:3], 3'b000};
    memory_request_write_data = address_latched[2] ? {write_data_latched, 32'b0} : {32'b0, write_data_latched};
    memory_request_write_strobe = address_latched[2] ? {write_strobe_latched, 4'b0} : {4'b0, write_strobe_latched};
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      state <= IDLE;
      address_latched <= '0;
      burst_length_latched <= '0;
      beat_index <= '0;
      write_latched <= 1'b0;
      loader_released <= 1'b0;
      transaction_is_control <= 1'b0;
      transaction_error <= 1'b0;
      write_data_latched <= '0;
      write_strobe_latched <= '0;
      read_data_latched <= '0;
      response_latched <= AXI_RESP_OKAY;
      cpu_hold_reset <= 1'b1;
    end else begin
      case (state)
        IDLE: begin
          response_latched <= AXI_RESP_OKAY;
          if (axi_awvalid && axi_awready) begin
            address_latched <= axi_awaddr;
            burst_length_latched <= axi_awlen;
            beat_index <= '0;
            write_latched <= 1'b1;
            transaction_is_control <= axi_awaddr == CONTROL_ADDRESS;
            transaction_error <= !(valid_control_access(axi_awaddr, axi_awlen, axi_awsize, axi_awburst) ||
                                   (valid_memory_burst(axi_awaddr, axi_awlen, axi_awsize, axi_awburst) &&
                                    cpu_hold_reset && memory_available));
            state <= WRITE_DATA;
          end else if (axi_arvalid && axi_arready) begin
            address_latched <= axi_araddr;
            burst_length_latched <= axi_arlen;
            beat_index <= '0;
            write_latched <= 1'b0;
            transaction_is_control <= axi_araddr == CONTROL_ADDRESS;
            if (valid_control_access(axi_araddr, axi_arlen, axi_arsize, axi_arburst)) begin
              read_data_latched <= {29'b0, loader_released, memory_available, cpu_hold_reset};
              transaction_error <= 1'b0;
              state <= READ_RESPONSE;
            end else if (valid_memory_burst(axi_araddr, axi_arlen, axi_arsize, axi_arburst) &&
                         cpu_hold_reset && memory_available) begin
              transaction_error <= 1'b0;
              state <= MEMORY_WAIT;
            end else begin
              burst_length_latched <= '0;
              transaction_error <= 1'b1;
              response_latched <= AXI_RESP_SLVERR;
              state <= READ_RESPONSE;
            end
          end
        end
        WRITE_DATA: if (axi_wvalid && axi_wready) begin
          write_data_latched <= axi_wdata;
          write_strobe_latched <= axi_wstrb;
          if (transaction_error) begin
            response_latched <= AXI_RESP_SLVERR;
            state <= WRITE_RESPONSE;
          end else if (transaction_is_control) begin
            // A control write with bit 0 set is an explicit re-arm.  This is
            // useful after a failed Linux boot: it makes the loader recoverable
            // without requiring a board power cycle or a full FPGA reset.  A
            // zero write remains the handoff to the CPU and is still one-way
            // until the next re-arm write.
            if (!axi_wlast) begin
              response_latched <= AXI_RESP_SLVERR;
            end else if (axi_wstrb[0]) begin
              cpu_hold_reset <= axi_wdata[0];
              loader_released <= !axi_wdata[0];
            end
            state <= WRITE_RESPONSE;
          end else if (axi_wlast != (beat_index == burst_length_latched)) begin
            response_latched <= AXI_RESP_SLVERR;
            state <= WRITE_RESPONSE;
          end else begin
            state <= MEMORY_WAIT;
          end
        end
        MEMORY_WAIT: if (memory_request_ready) begin
          response_latched <= memory_response_error ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
          read_data_latched <= address_latched[2] ? memory_response_read_data[63:32] : memory_response_read_data[31:0];
          if (write_latched) begin
            if (memory_response_error || beat_index == burst_length_latched) begin
              state <= WRITE_RESPONSE;
            end else begin
              address_latched <= address_latched + 32'd4;
              beat_index <= beat_index + 8'd1;
              state <= WRITE_DATA;
            end
          end else begin
            state <= READ_RESPONSE;
          end
        end
        WRITE_RESPONSE: if (axi_bready) state <= IDLE;
        READ_RESPONSE: if (axi_rready) begin
          if (beat_index == burst_length_latched) begin
            state <= IDLE;
          end else begin
            address_latched <= address_latched + 32'd4;
            beat_index <= beat_index + 8'd1;
            state <= MEMORY_WAIT;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
