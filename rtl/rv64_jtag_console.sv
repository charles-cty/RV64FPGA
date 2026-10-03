// Accepted host register beats and UART byte handshakes share clk.
module rv64_jtag_console #(
  parameter integer RX_DEPTH = 256,
  parameter integer TX_DEPTH = 4096,
  parameter integer LEASE_CYCLES = 250000000
) (
  input logic clk, reset,
  input logic host_read, host_write,
  input logic [4:0] host_address,
  input logic [31:0] host_write_data,
  output logic [31:0] host_read_data,
  output logic host_error,
  output logic rx_valid,
  output logic [7:0] rx_data,
  input logic rx_ready,
  input logic tx_valid,
  input logic [7:0] tx_data,
  output logic tx_ready
);
  localparam integer RW = $clog2(RX_DEPTH);
  localparam integer TW = $clog2(TX_DEPTH);
  logic [7:0] rx_mem [0:RX_DEPTH-1];
  logic [7:0] tx_mem [0:TX_DEPTH-1];
  logic [RW-1:0] rx_head, rx_tail;
  logic [TW-1:0] tx_head, tx_tail;
  logic [RW:0] rx_count;
  logic [TW:0] tx_count;
  logic [31:0] dropped, lease;
  logic attached;
  logic rx_push, rx_pop, tx_push, tx_pop;
  assign rx_valid = !reset && rx_count != 0;
  assign rx_data = rx_count != 0 ? rx_mem[rx_head] : 8'b0;
  assign tx_ready = !reset && (!attached || tx_count < TX_DEPTH);
  assign rx_pop = rx_valid && rx_ready;
  assign rx_push = host_write && !host_error && host_address == 5'h0c;
  assign tx_pop = host_read && !reset && host_address == 5'h0c && tx_count != 0;
  assign tx_push = !reset && tx_valid && tx_ready && (tx_count < TX_DEPTH || tx_pop);

  always_comb begin
    host_read_data = 0;
    host_error = 0;
    case (host_address)
      5'h00: host_read_data = 32'h4a544331; // JTC1
      5'h04: host_read_data = reset ? 0 : RX_DEPTH - rx_count;
      5'h08: host_read_data = reset ? 0 : tx_count;
      5'h0c: host_read_data = (!reset && tx_count != 0) ? {1'b1,23'b0,tx_mem[tx_head]} : 0;
      5'h10: host_read_data = dropped;
      5'h14: host_read_data = {31'b0,attached};
      default: host_error = 1;
    endcase
    if (host_write) begin
      if (reset) host_error = 1;
      else if (host_address == 5'h0c) host_error = rx_count == RX_DEPTH;
      else if (host_address == 5'h14) host_error = host_write_data > 1;
      else host_error = 1;
    end
  end
  always_ff @(posedge clk) begin
    if (reset) begin
      rx_head <= 0; rx_tail <= 0; rx_count <= 0;
      tx_head <= 0; tx_tail <= 0; tx_count <= 0;
      dropped <= 0; attached <= 0; lease <= 0;
    end else begin
      // A vanished host cannot leave Linux blocked indefinitely.
      if (host_read || host_write) lease <= 0;
      else if (attached) begin
        if (lease == LEASE_CYCLES-1) begin attached <= 0; lease <= 0; end
        else lease <= lease + 1;
      end
      if (host_write && !host_error && host_address == 5'h14) attached <= host_write_data[0];
      if (rx_push) begin rx_mem[rx_tail] <= host_write_data[7:0]; rx_tail <= rx_tail + 1'b1; end
      if (rx_pop) rx_head <= rx_head + 1'b1;
      case ({rx_push,rx_pop})
        2'b10: rx_count <= rx_count + 1'b1;
        2'b01: rx_count <= rx_count - 1'b1;
        default: ;
      endcase
      if (tx_push) begin tx_mem[tx_tail] <= tx_data; tx_tail <= tx_tail + 1'b1; end
      if (tx_pop) tx_head <= tx_head + 1'b1;
      case ({tx_push,tx_pop})
        2'b10: tx_count <= tx_count + 1'b1;
        2'b01: tx_count <= tx_count - 1'b1;
        default: ;
      endcase
      // Offline boot never blocks. Count any discarded output explicitly.
      if (tx_valid && tx_ready && !tx_push && dropped != 32'hffffffff) dropped <= dropped + 1'b1;
    end
  end
endmodule
