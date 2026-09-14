module rv64_async_memory_bridge (
  input  logic        cpu_clk,
  input  logic        cpu_reset,
  input  logic        cpu_request_valid,
  input  logic        cpu_request_write,
  input  logic [63:0] cpu_request_address,
  input  logic [63:0] cpu_request_write_data,
  input  logic [7:0]  cpu_request_write_strobe,
  output logic        cpu_request_ready,
  output logic [63:0] cpu_response_read_data,
  output logic        cpu_response_error,
  input  logic        ui_clk,
  input  logic        ui_reset,
  output logic        ui_request_valid,
  output logic        ui_request_write,
  output logic [63:0] ui_request_address,
  output logic [63:0] ui_request_write_data,
  output logic [7:0]  ui_request_write_strobe,
  input  logic        ui_request_ready,
  input  logic [63:0] ui_response_read_data,
  input  logic        ui_response_error
);
  typedef enum logic [1:0] {CPU_IDLE, CPU_WAIT_RESPONSE, CPU_RESPONSE} cpu_state_t;
  typedef enum logic {UI_IDLE, UI_REQUEST} ui_state_t;

  cpu_state_t cpu_state;
  ui_state_t ui_state;
  logic cpu_request_toggle;
  logic ui_request_toggle_sync1;
  logic ui_request_toggle_sync2;
  logic ui_request_toggle_seen;
  logic ui_response_toggle;
  logic cpu_response_toggle_sync1;
  logic cpu_response_toggle_sync2;
  logic cpu_response_toggle_seen;

  logic cpu_request_write_latched;
  logic [63:0] cpu_request_address_latched;
  logic [63:0] cpu_request_write_data_latched;
  logic [7:0] cpu_request_write_strobe_latched;
  logic [63:0] ui_response_read_data_latched;
  logic ui_response_error_latched;
  logic [63:0] cpu_response_read_data_latched;
  logic cpu_response_error_latched;

  always_comb begin
    cpu_request_ready = cpu_state == CPU_RESPONSE;
    cpu_response_read_data = cpu_response_read_data_latched;
    cpu_response_error = cpu_request_ready && cpu_response_error_latched;
    ui_request_valid = ui_state == UI_REQUEST;
  end

  always_ff @(posedge cpu_clk or posedge cpu_reset) begin
    if (cpu_reset) begin
      cpu_state <= CPU_IDLE;
      cpu_request_toggle <= 1'b0;
      cpu_response_toggle_sync1 <= 1'b0;
      cpu_response_toggle_sync2 <= 1'b0;
      cpu_response_toggle_seen <= 1'b0;
      cpu_request_write_latched <= 1'b0;
      cpu_request_address_latched <= '0;
      cpu_request_write_data_latched <= '0;
      cpu_request_write_strobe_latched <= '0;
      cpu_response_read_data_latched <= '0;
      cpu_response_error_latched <= 1'b0;
    end else begin
      cpu_response_toggle_sync1 <= ui_response_toggle;
      cpu_response_toggle_sync2 <= cpu_response_toggle_sync1;
      case (cpu_state)
        CPU_IDLE: begin
          if (cpu_request_valid) begin
            cpu_request_write_latched <= cpu_request_write;
            cpu_request_address_latched <= cpu_request_address;
            cpu_request_write_data_latched <= cpu_request_write_data;
            cpu_request_write_strobe_latched <= cpu_request_write_strobe;
            cpu_request_toggle <= ~cpu_request_toggle;
            cpu_state <= CPU_WAIT_RESPONSE;
          end
        end
        CPU_WAIT_RESPONSE: begin
          if (cpu_response_toggle_sync2 != cpu_response_toggle_seen) begin
            cpu_response_toggle_seen <= cpu_response_toggle_sync2;
            cpu_response_read_data_latched <= ui_response_read_data_latched;
            cpu_response_error_latched <= ui_response_error_latched;
            cpu_state <= CPU_RESPONSE;
          end
        end
        CPU_RESPONSE: begin
          if (cpu_request_valid) begin
            cpu_state <= CPU_IDLE;
          end
        end
        default: cpu_state <= CPU_IDLE;
      endcase
    end
  end

  always_ff @(posedge ui_clk or posedge ui_reset) begin
    if (ui_reset) begin
      ui_state <= UI_IDLE;
      ui_request_toggle_sync1 <= 1'b0;
      ui_request_toggle_sync2 <= 1'b0;
      ui_request_toggle_seen <= 1'b0;
      ui_response_toggle <= 1'b0;
      ui_request_write <= 1'b0;
      ui_request_address <= '0;
      ui_request_write_data <= '0;
      ui_request_write_strobe <= '0;
      ui_response_read_data_latched <= '0;
      ui_response_error_latched <= 1'b0;
    end else begin
      ui_request_toggle_sync1 <= cpu_request_toggle;
      ui_request_toggle_sync2 <= ui_request_toggle_sync1;
      case (ui_state)
        UI_IDLE: begin
          if (ui_request_toggle_sync2 != ui_request_toggle_seen) begin
            ui_request_toggle_seen <= ui_request_toggle_sync2;
            ui_request_write <= cpu_request_write_latched;
            ui_request_address <= cpu_request_address_latched;
            ui_request_write_data <= cpu_request_write_data_latched;
            ui_request_write_strobe <= cpu_request_write_strobe_latched;
            ui_state <= UI_REQUEST;
          end
        end
        UI_REQUEST: begin
          if (ui_request_ready) begin
            ui_response_read_data_latched <= ui_response_read_data;
            ui_response_error_latched <= ui_response_error;
            ui_response_toggle <= ~ui_response_toggle;
            ui_state <= UI_IDLE;
          end
        end
        default: ui_state <= UI_IDLE;
      endcase
    end
  end
endmodule
