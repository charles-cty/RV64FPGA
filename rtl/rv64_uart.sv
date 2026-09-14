module rv64_uart #(
  parameter integer BIT_CYCLES = 434
) (
  input  logic        clk,
  input  logic        reset,
  input  logic        request,
  input  logic        write,
  input  logic [11:0] address,
  input  logic [63:0] write_data,
  output logic [63:0] read_data,
  output logic        ready,
  output logic        tx
);
  logic [9:0] shift_register;
  logic [3:0] bit_index;
  logic [31:0] baud_counter;
  logic busy;

  assign ready = !busy || !write;

  always_comb begin
    read_data = '0;
    unique case (address)
      12'h000: read_data = {56'b0, shift_register[8:1]};
      12'h005: read_data = {63'b0, !busy};
      default: read_data = '0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      shift_register <= 10'b11_1111_1111;
      bit_index <= '0;
      baud_counter <= '0;
      busy <= 1'b0;
      tx <= 1'b1;
    end else begin
      if (request && write && (address == 12'h000) && !busy) begin
        shift_register <= {1'b1, write_data[7:0], 1'b0};
        bit_index <= '0;
        baud_counter <= '0;
        busy <= 1'b1;
        tx <= 1'b0;
      end else if (busy) begin
        if (baud_counter == BIT_CYCLES - 1) begin
          baud_counter <= '0;
          if (bit_index == 4'd9) begin
            busy <= 1'b0;
            tx <= 1'b1;
          end else begin
            bit_index <= bit_index + 4'd1;
            shift_register <= {1'b0, shift_register[9:1]};
            tx <= shift_register[1];
          end
        end else begin
          baud_counter <= baud_counter + 32'd1;
        end
      end
    end
  end
endmodule
