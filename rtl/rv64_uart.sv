module rv64_uart #(
  parameter bit JTAG_CONSOLE = 1'b0,
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
  output logic        tx,
  input  logic        rx,
  input logic console_rx_valid,
  input logic [7:0] console_rx_data,
  output logic console_rx_ready,
  output logic console_tx_valid,
  output logic [7:0] console_tx_data,
  input logic console_tx_ready,
  output logic        interrupt
);
  logic [9:0] shift_register;
  logic [3:0] bit_index;
  logic [31:0] baud_counter;
  logic busy;
  logic [7:0] interrupt_enable;
  logic [7:0] fifo_control;
  logic [7:0] line_control;
  logic [7:0] divisor_low;
  logic [7:0] divisor_high;
  logic rx_sync_meta;
  logic rx_sync;
  logic rx_busy;
  logic [3:0] rx_bit_index;
  logic [31:0] rx_baud_counter;
  logic [7:0] rx_shift_register;
  logic [7:0] rx_data_register;
  logic rx_data_valid;
  logic rx_overrun;
  logic rx_framing_error;
  logic [7:0] interrupt_identification;
  localparam integer RX_START_DELAY = (BIT_CYCLES < 2) ? 1 : (BIT_CYCLES / 2);

  logic receive_valid, transmit_ready;
  assign receive_valid = JTAG_CONSOLE ? console_rx_valid : rx_data_valid;
  assign transmit_ready = !busy && (!JTAG_CONSOLE || console_tx_ready);
  assign ready = (!busy || !write) &&
                 !(JTAG_CONSOLE && write && address == 0 && !line_control[7] && !console_tx_ready);
  assign console_rx_ready = JTAG_CONSOLE && !reset && request && !write && address == 0 && !line_control[7];
  assign console_tx_valid = JTAG_CONSOLE && !reset && request && write && ready && address == 0 && !line_control[7];
  assign console_tx_data = write_data[7:0];
  assign interrupt = (interrupt_enable[0] && receive_valid) ||
                     (interrupt_enable[1] && transmit_ready);

  always_comb begin
    read_data = '0;
    interrupt_identification = 8'h01;
    if (interrupt_enable[0] && receive_valid) begin
      interrupt_identification = 8'h04;
    end else if (interrupt_enable[1] && transmit_ready) begin
      interrupt_identification = 8'h02;
    end
    unique case (address)
      12'h000: read_data = line_control[7] ? {56'b0, divisor_low} :
                           {56'b0, (JTAG_CONSOLE ? console_rx_data : rx_data_register)};
      12'h001: read_data = line_control[7] ? {56'b0, divisor_high} :
                           {56'b0, interrupt_enable};
      12'h002: read_data = {56'b0, interrupt_identification};
      12'h003: read_data = {56'b0, line_control};
      12'h005: read_data = {56'b0,
                            1'b0,
                            transmit_ready,
                            transmit_ready,
                            1'b0,
                            rx_framing_error,
                            1'b0,
                            rx_overrun,
                            receive_valid};
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
      interrupt_enable <= '0;
      fifo_control <= '0;
      line_control <= 8'h03;
      divisor_low <= 8'd1;
      divisor_high <= '0;
      rx_sync_meta <= 1'b1;
      rx_sync <= 1'b1;
      rx_busy <= 1'b0;
      rx_bit_index <= '0;
      rx_baud_counter <= '0;
      rx_shift_register <= '0;
      rx_data_register <= '0;
      rx_data_valid <= 1'b0;
      rx_overrun <= 1'b0;
      rx_framing_error <= 1'b0;
    end else begin
      rx_sync_meta <= rx;
      rx_sync <= rx_sync_meta;

      if (request && write && address == 12'h001) begin
        if (line_control[7]) begin
          divisor_high <= write_data[7:0];
        end else begin
          interrupt_enable <= write_data[7:0];
        end
      end else if (request && write && address == 12'h002) begin
        fifo_control <= write_data[7:0];
      end else if (request && write && address == 12'h003) begin
        line_control <= write_data[7:0];
      end else if (request && write && (address == 12'h000) && line_control[7]) begin
        divisor_low <= write_data[7:0];
      end else if (request && write && (address == 12'h000) && transmit_ready) begin
        shift_register <= {1'b1, write_data[7:0], 1'b0};
        bit_index <= '0;
        baud_counter <= '0;
        busy <= 1'b1;
        tx <= 1'b0;
      end else if (request && !write && address == 12'h000 && !line_control[7]) begin
        rx_data_valid <= 1'b0;
        rx_overrun <= 1'b0;
        rx_framing_error <= 1'b0;
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

      if (!rx_busy) begin
        if (rx_sync == 1'b0) begin
          rx_busy <= 1'b1;
          rx_bit_index <= 4'd0;
          rx_baud_counter <= RX_START_DELAY - 1;
        end
      end else if (rx_baud_counter != 0) begin
        rx_baud_counter <= rx_baud_counter - 1;
      end else if (rx_bit_index == 4'd0) begin
        if (rx_sync == 1'b0) begin
          rx_bit_index <= 4'd1;
          rx_baud_counter <= (BIT_CYCLES < 1) ? 0 : BIT_CYCLES - 1;
        end else begin
          rx_busy <= 1'b0;
        end
      end else if (rx_bit_index <= 4'd8) begin
        rx_shift_register[rx_bit_index - 1'b1] <= rx_sync;
        rx_bit_index <= rx_bit_index + 1'b1;
        rx_baud_counter <= (BIT_CYCLES < 1) ? 0 : BIT_CYCLES - 1;
      end else begin
        rx_busy <= 1'b0;
        if (rx_sync == 1'b1) begin
          if (rx_data_valid) begin
            rx_overrun <= 1'b1;
          end else begin
            rx_data_register <= rx_shift_register;
            rx_data_valid <= 1'b1;
          end
        end else begin
          rx_framing_error <= 1'b1;
        end
      end
    end
  end
endmodule
