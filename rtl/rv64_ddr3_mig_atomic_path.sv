module rv64_ddr3_mig_atomic_path #(
  parameter logic [63:0] DDR_BASE_ADDRESS = 64'h0000_0000_8000_0000,
  parameter logic [63:0] DDR_SIZE_BYTES = 64'h0000_0000_8000_0000,
  parameter integer AXI_ADDRESS_WIDTH = 31,
  parameter integer AXI_ID_WIDTH = 4
) (
  input  logic                         cpu_clk,
  input  logic                         cpu_reset,
  input  logic                         request_valid,
  input  riscv_pkg::atomic_op_t       request_operation,
  input  logic                         request_word_operation,
  input  logic [63:0]                  request_address,
  input  logic [63:0]                  request_source_data,
  output logic                         request_ready,
  output logic [63:0]                  response_read_data,
  output logic                         response_error,
  input  logic                         ui_clk,
  input  logic                         ui_reset,
  input  logic                         init_calib_complete,
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
  import riscv_pkg::*;

  typedef enum logic [2:0] {IDLE, READ_OLD, WRITE_NEW, RESPONSE} state_t;
  state_t state;
  logic [63:0] address_latched;
  logic [63:0] source_data_latched;
  logic [63:0] old_data_latched;
  atomic_op_t operation_latched;
  logic word_operation_latched;
  logic reservation_valid;
  logic [63:0] reservation_address;
  logic [63:0] operation_result;
  logic operation_error;
  logic [63:0] operation_write_data;
  logic memory_valid;
  logic memory_ready;
  logic memory_write;
  logic [63:0] memory_address;
  logic [63:0] memory_write_data;
  logic [7:0] memory_write_strobe;
  logic [63:0] memory_read_data;
  logic memory_error;
  logic memory_wait_seen;

  function automatic logic [63:0] calculate_amo(
    input atomic_op_t operation,
    input logic [63:0] old_value,
    input logic [63:0] source_value,
    input logic word_operation
  );
    logic [31:0] old_word;
    logic [31:0] source_word;
    logic [31:0] result_word;
    begin
      old_word = old_value[31:0];
      source_word = source_value[31:0];
      result_word = old_word;
      if (word_operation) begin
        unique case (operation)
          ATOMIC_SWAP: result_word = source_word;
          ATOMIC_ADD:  result_word = old_word + source_word;
          ATOMIC_XOR:  result_word = old_word ^ source_word;
          ATOMIC_AND:  result_word = old_word & source_word;
          ATOMIC_OR:   result_word = old_word | source_word;
          ATOMIC_MIN:  result_word = ($signed(old_word) < $signed(source_word)) ? old_word : source_word;
          ATOMIC_MAX:  result_word = ($signed(old_word) > $signed(source_word)) ? old_word : source_word;
          ATOMIC_MINU: result_word = (old_word < source_word) ? old_word : source_word;
          ATOMIC_MAXU: result_word = (old_word > source_word) ? old_word : source_word;
          default:     result_word = old_word;
        endcase
        calculate_amo = {{32{result_word[31]}}, result_word};
      end else begin
        unique case (operation)
          ATOMIC_SWAP: calculate_amo = source_value;
          ATOMIC_ADD:  calculate_amo = old_value + source_value;
          ATOMIC_XOR:  calculate_amo = old_value ^ source_value;
          ATOMIC_AND:  calculate_amo = old_value & source_value;
          ATOMIC_OR:   calculate_amo = old_value | source_value;
          ATOMIC_MIN:  calculate_amo = ($signed(old_value) < $signed(source_value)) ? old_value : source_value;
          ATOMIC_MAX:  calculate_amo = ($signed(old_value) > $signed(source_value)) ? old_value : source_value;
          ATOMIC_MINU: calculate_amo = (old_value < source_value) ? old_value : source_value;
          ATOMIC_MAXU: calculate_amo = (old_value > source_value) ? old_value : source_value;
          default:     calculate_amo = old_value;
        endcase
      end
    end
  endfunction

  rv64_ddr3_mig_path #(
    .DDR_BASE_ADDRESS(DDR_BASE_ADDRESS),
    .DDR_SIZE_BYTES(DDR_SIZE_BYTES),
    .AXI_ADDRESS_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH)
  ) memory_path (
    .cpu_clk(cpu_clk), .cpu_reset(cpu_reset),
    .cpu_request_valid(memory_valid), .cpu_request_write(memory_write),
    .cpu_request_address(memory_address), .cpu_request_write_data(memory_write_data),
    .cpu_request_write_strobe(memory_write_strobe), .cpu_request_ready(memory_ready),
    .cpu_response_read_data(memory_read_data), .cpu_response_error(memory_error),
    .ui_clk(ui_clk), .ui_reset(ui_reset), .init_calib_complete(init_calib_complete),
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

  always_comb begin
    request_ready = state == RESPONSE;
    response_read_data = operation_result;
    response_error = request_ready && operation_error;
    operation_write_data = calculate_amo(operation_latched, old_data_latched,
                                         source_data_latched, word_operation_latched);
    memory_valid = state == READ_OLD || state == WRITE_NEW;
    memory_write = state == WRITE_NEW;
    memory_address = address_latched;
    memory_write_data = operation_latched == ATOMIC_SC ? source_data_latched : operation_write_data;
    memory_write_strobe = word_operation_latched ? 8'h0f : 8'hff;
  end

  always_ff @(posedge cpu_clk) begin
    if (cpu_reset) begin
      state <= IDLE;
      address_latched <= '0;
      source_data_latched <= '0;
      old_data_latched <= '0;
      operation_latched <= ATOMIC_LR;
      word_operation_latched <= 1'b0;
      reservation_valid <= 1'b0;
      reservation_address <= '0;
      operation_result <= '0;
      operation_error <= 1'b0;
      memory_wait_seen <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          if (request_valid) begin
            address_latched <= request_address;
            source_data_latched <= request_source_data;
            operation_latched <= request_operation;
            word_operation_latched <= request_word_operation;
            operation_result <= '0;
            operation_error <= 1'b0;
            if (request_operation == ATOMIC_SC &&
                !(reservation_valid && reservation_address == request_address)) begin
              operation_result <= 64'd1;
              reservation_valid <= 1'b0;
              state <= RESPONSE;
            end else begin
              memory_wait_seen <= 1'b0;
              state <= READ_OLD;
            end
          end
        end
        READ_OLD: begin
          if (!memory_ready) begin
            memory_wait_seen <= 1'b1;
          end else if (memory_wait_seen) begin
            operation_error <= memory_error;
            if (memory_error) begin
              reservation_valid <= 1'b0;
              state <= RESPONSE;
            end else begin
              old_data_latched <= memory_read_data;
              if (operation_latched == ATOMIC_LR) begin
                operation_result <= word_operation_latched ? {{32{memory_read_data[31]}}, memory_read_data[31:0]} : memory_read_data;
                reservation_valid <= 1'b1;
                reservation_address <= address_latched;
                state <= RESPONSE;
              end else begin
                memory_wait_seen <= 1'b0;
                state <= WRITE_NEW;
              end
            end
          end
        end
        WRITE_NEW: begin
          if (!memory_ready) begin
            memory_wait_seen <= 1'b1;
          end else if (memory_wait_seen) begin
            operation_error <= memory_error;
            operation_result <= operation_latched == ATOMIC_SC ? 64'd0 :
                                (word_operation_latched ? {{32{old_data_latched[31]}}, old_data_latched[31:0]} : old_data_latched);
            reservation_valid <= 1'b0;
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
