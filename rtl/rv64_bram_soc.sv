module rv64_bram_soc #(
  parameter integer UART_BIT_CYCLES = 434,
  parameter logic USE_DDR3_MODEL = 1'b0,
  parameter integer DDR3_MODEL_RESPONSE_DELAY = 2,
  parameter logic DDR3_MODEL_CALIBRATED = 1'b1
) (
  input  logic        clk,
  input  logic        reset,
  output logic [2:0]  led,
  output logic        uart_tx
);
  import riscv_pkg::*;

  localparam logic [63:0] LED_ADDRESS = 64'h0000_0000_1000_1000;
  localparam logic [63:0] UART_ADDRESS = 64'h0000_0000_1000_0000;
  localparam logic [63:0] CLINT_ADDRESS = 64'h0000_0000_0200_0000;
  localparam logic [63:0] PLIC_ADDRESS = 64'h0000_0000_0c00_0000;
  localparam logic [63:0] DDR3_BASE_ADDRESS = 64'h0000_0000_8000_0000;
  localparam logic [63:0] DDR3_END_ADDRESS = 64'h0000_0001_0000_0000;

  logic [31:0] instruction_memory [0:16383];
  logic [63:0] data_memory [0:8191];
  logic [63:0] instruction_address;
  logic [63:0] instruction_physical_address;
  logic [63:0] instruction_mmu_physical_address;
  logic [31:0] instruction_data;
  logic instruction_ready;
  logic instruction_fault;
  logic instruction_translation_ready;
  logic instruction_ddr3_access;
  logic instruction_cache_request;
  logic instruction_cache_response_valid;
  logic [63:0] instruction_cache_response_data;
  logic instruction_cache_memory_valid;
  logic instruction_cache_memory_write;
  logic [63:0] instruction_cache_memory_address;
  logic [63:0] instruction_cache_memory_write_data;
  logic [7:0] instruction_cache_memory_write_strobe;
  logic instruction_cache_memory_ddr3;
  logic instruction_ddr3_model_ready;
  logic [63:0] instruction_ddr3_model_read_data;
  logic instruction_ddr3_model_error;
  logic        data_valid;
  logic        data_write;
  logic [63:0] data_address;
  logic [63:0] data_write_data;
  logic [7:0]  data_write_strobe;
  logic [63:0] data_read_data;
  logic        data_ready;
  logic        data_fault;
  logic [63:0] data_physical_address;
  logic [63:0] data_mmu_physical_address;
  logic        commit_valid;
  logic [63:0] commit_pc;
  logic [31:0] commit_instruction;
  logic [63:0] commit_next_pc;
  logic        commit_rd_write;
  logic [4:0]  commit_rd;
  logic [63:0] commit_rd_value;
  logic        commit_csr_write;
  logic [11:0] commit_csr_address;
  logic [63:0] commit_csr_value;
  logic        commit_trap_valid;
  logic [63:0] commit_trap_cause;
  logic        illegal_instruction;
  logic [1:0] privilege_mode;
  logic [63:0] satp_value;
  logic sum_enable;
  logic sfence_valid;
  logic [63:0] sfence_virtual_address;
  logic sfence_all;
  logic        software_interrupt;
  logic        timer_interrupt;
  logic        external_interrupt;
  logic        clint_request;
  logic        clint_ready;
  logic [63:0] clint_read_data;
  logic        clint_software_interrupt;
  logic        clint_timer_interrupt;
  logic        plic_request;
  logic        plic_ready;
  logic [63:0] plic_read_data;
  logic [31:0] plic_sources;
  logic        plic_external_interrupt;
  logic instruction_translation_done;
  logic instruction_translation_fault;
  logic instruction_translation_complete;
  logic instruction_translation_fault_latched;
  logic [63:0] instruction_translation_virtual_address;
  logic [63:0] instruction_translation_satp;
  logic [1:0] instruction_translation_privilege;
  logic instruction_translation_sum;
  logic [63:0] instruction_physical_address_latched;
  logic instruction_pte_request;
  logic [63:0] instruction_pte_address;
  logic [63:0] instruction_pte_read_data;
  logic data_translation_done;
  logic data_translation_fault;
  logic data_translation_complete;
  logic data_translation_fault_latched;
  logic [63:0] data_translation_virtual_address;
  logic [63:0] data_translation_satp;
  logic [1:0] data_translation_privilege;
  logic data_translation_sum;
  logic [63:0] data_physical_address_latched;
  logic data_translation_ready;
  logic data_bram_request;
  logic data_ddr3_access;
  logic data_ddr3_request;
  logic data_cache_request;
  logic data_cache_request_ready;
  logic data_cache_response_valid;
  logic [63:0] data_cache_response_data;
  logic data_cache_memory_valid;
  logic data_cache_memory_write;
  logic [63:0] data_cache_memory_address;
  logic [63:0] data_cache_memory_write_data;
  logic [7:0] data_cache_memory_write_strobe;
  logic data_cache_memory_ddr3;
  logic ddr3_model_ready;
  logic [63:0] ddr3_model_read_data;
  logic ddr3_model_error;
  logic data_pte_request;
  logic [63:0] data_pte_address;
  logic [63:0] data_pte_read_data;
  logic mmu_enabled;
  logic        uart_request;
  logic        uart_ready;
  logic [63:0] uart_read_data;
  integer index;
  integer byte_index;

  rv64_core core (.*);

  assign mmu_enabled = (privilege_mode != 2'b11) && (satp_value[63:60] == 4'h8);
  assign instruction_physical_address = mmu_enabled ?
                                        ((instruction_translation_complete &&
                                          instruction_address == instruction_translation_virtual_address &&
                                          satp_value == instruction_translation_satp &&
                                          privilege_mode == instruction_translation_privilege &&
                                          sum_enable == instruction_translation_sum &&
                                          !instruction_translation_fault_latched) ?
                                         instruction_physical_address_latched : 64'b0) : instruction_address;
  assign instruction_translation_ready = !mmu_enabled ||
                                         (instruction_translation_complete &&
                                          instruction_address == instruction_translation_virtual_address &&
                                          satp_value == instruction_translation_satp &&
                                          privilege_mode == instruction_translation_privilege &&
                                          sum_enable == instruction_translation_sum);
  assign instruction_ddr3_access = instruction_translation_ready &&
                                   !instruction_translation_fault_latched &&
                                   instruction_physical_address >= DDR3_BASE_ADDRESS &&
                                   instruction_physical_address < DDR3_END_ADDRESS;
  assign instruction_cache_request = instruction_ddr3_access && USE_DDR3_MODEL;
  assign instruction_data = instruction_cache_request ?
                            (instruction_physical_address[2] ? instruction_cache_response_data[63:32] :
                             instruction_cache_response_data[31:0]) :
                            instruction_memory[instruction_physical_address[15:2]];
  assign instruction_ready = instruction_translation_ready &&
                             (instruction_cache_request ?
                              (instruction_cache_response_valid || instruction_ddr3_model_error) : 1'b1);
  assign instruction_fault = (mmu_enabled && instruction_translation_ready &&
                              instruction_translation_fault_latched) ||
                             (instruction_ddr3_access && !USE_DDR3_MODEL) ||
                             (instruction_cache_memory_valid && instruction_cache_memory_ddr3 &&
                              instruction_ddr3_model_error);
  assign data_physical_address = mmu_enabled ?
                                 ((data_translation_complete &&
                                   data_address == data_translation_virtual_address &&
                                   satp_value == data_translation_satp &&
                                   privilege_mode == data_translation_privilege &&
                                   sum_enable == data_translation_sum &&
                                   !data_translation_fault_latched) ?
                                  data_physical_address_latched : 64'b0) : data_address;
  assign data_translation_ready = !mmu_enabled ||
                                  (data_translation_complete &&
                                   data_address == data_translation_virtual_address &&
                                   satp_value == data_translation_satp &&
                                   privilege_mode == data_translation_privilege &&
                                   sum_enable == data_translation_sum &&
                                   !data_translation_fault_latched);
  assign uart_request = data_valid && data_translation_ready &&
                        (data_physical_address[63:12] == UART_ADDRESS[63:12]);
  assign clint_request = data_valid && data_translation_ready &&
                         (data_physical_address[63:16] == CLINT_ADDRESS[63:16]);
  assign plic_request = data_valid && data_translation_ready &&
                        (data_physical_address[63:22] == PLIC_ADDRESS[63:22]);
  assign data_bram_request = data_valid && data_translation_ready &&
                             data_physical_address[63:16] == 48'b0;
  assign data_ddr3_access = data_translation_ready &&
                             data_physical_address >= DDR3_BASE_ADDRESS &&
                             data_physical_address < DDR3_END_ADDRESS;
  assign data_ddr3_request = data_valid && data_ddr3_access;
  assign data_cache_request = data_bram_request || data_ddr3_request;
  assign data_ready = data_translation_ready &&
                      (data_cache_request ? data_cache_response_valid :
                       uart_request ? uart_ready :
                       clint_request ? clint_ready :
                       plic_request ? plic_ready : 1'b1);
  assign data_fault = (mmu_enabled && data_translation_complete &&
                       data_address == data_translation_virtual_address &&
                       satp_value == data_translation_satp &&
                       privilege_mode == data_translation_privilege &&
                       sum_enable == data_translation_sum &&
                       data_translation_fault_latched) ||
                      (data_ddr3_access && !USE_DDR3_MODEL) ||
                      (data_cache_memory_valid && data_cache_memory_ddr3 &&
                       ddr3_model_error);
  assign software_interrupt = clint_software_interrupt;
  assign timer_interrupt = clint_timer_interrupt;
  assign external_interrupt = plic_external_interrupt;
  assign plic_sources = '0;

  rv64_mmu instruction_mmu (
    .clk(clk),
    .reset(reset),
    .translate_valid(mmu_enabled && !instruction_translation_complete &&
                     !instruction_translation_done),
    .virtual_address(instruction_address),
    .access(MMU_FETCH),
    .privilege(privilege_mode),
    .sum_enable(sum_enable),
    .satp(satp_value),
    .pte_request(instruction_pte_request),
    .pte_address(instruction_pte_address),
    .pte_read_data(instruction_pte_read_data),
    .pte_ready(instruction_pte_request),
    .sfence_valid(sfence_valid),
    .sfence_all(sfence_all),
    .sfence_virtual_address(sfence_virtual_address),
    .translation_done(instruction_translation_done),
    .translation_fault(instruction_translation_fault),
    .physical_address(instruction_mmu_physical_address),
    .busy()
  );

  rv64_mmu data_mmu (
    .clk(clk),
    .reset(reset),
    .translate_valid(mmu_enabled && data_valid && !data_translation_complete &&
                     !data_translation_done),
    .virtual_address(data_address),
    .access(data_write ? MMU_STORE : MMU_LOAD),
    .privilege(privilege_mode),
    .sum_enable(sum_enable),
    .satp(satp_value),
    .pte_request(data_pte_request),
    .pte_address(data_pte_address),
    .pte_read_data(data_pte_read_data),
    .pte_ready(data_pte_request),
    .sfence_valid(sfence_valid),
    .sfence_all(sfence_all),
    .sfence_virtual_address(sfence_virtual_address),
    .translation_done(data_translation_done),
    .translation_fault(data_translation_fault),
    .physical_address(data_mmu_physical_address),
    .busy()
  );

  rv64_ddr3_model #(.RESPONSE_DELAY(DDR3_MODEL_RESPONSE_DELAY)) ddr3_model (
    .clk(clk),
    .reset(reset),
    .calibrated(DDR3_MODEL_CALIBRATED),
    .request_valid(USE_DDR3_MODEL && data_cache_memory_valid && data_cache_memory_ddr3),
    .request_write(data_cache_memory_write),
    .request_address(data_cache_memory_address - DDR3_BASE_ADDRESS),
    .request_write_data(data_cache_memory_write_data),
    .request_write_strobe(data_cache_memory_write_strobe),
    .request_ready(ddr3_model_ready),
    .response_read_data(ddr3_model_read_data),
    .response_error(ddr3_model_error)
  );

  rv64_ddr3_model #(.RESPONSE_DELAY(DDR3_MODEL_RESPONSE_DELAY)) instruction_ddr3_model (
    .clk(clk),
    .reset(reset),
    .calibrated(DDR3_MODEL_CALIBRATED),
    .request_valid(USE_DDR3_MODEL && instruction_cache_memory_valid && instruction_cache_memory_ddr3),
    .request_write(instruction_cache_memory_write),
    .request_address(instruction_cache_memory_address - DDR3_BASE_ADDRESS),
    .request_write_data(instruction_cache_memory_write_data),
    .request_write_strobe(instruction_cache_memory_write_strobe),
    .request_ready(instruction_ddr3_model_ready),
    .response_read_data(instruction_ddr3_model_read_data),
    .response_error(instruction_ddr3_model_error)
  );

  rv64_cache #(.LINE_COUNT(4)) instruction_cache (
    .clk(clk),
    .reset(reset),
    .request_valid(instruction_cache_request),
    .request_ready(),
    .request_write(1'b0),
    .request_address(instruction_physical_address),
    .request_write_data('0),
    .request_write_strobe('0),
    .response_valid(instruction_cache_response_valid),
    .response_read_data(instruction_cache_response_data),
    .memory_valid(instruction_cache_memory_valid),
    .memory_ready(instruction_cache_memory_ddr3 ? instruction_ddr3_model_ready : 1'b1),
    .memory_write(instruction_cache_memory_write),
    .memory_address(instruction_cache_memory_address),
    .memory_write_data(instruction_cache_memory_write_data),
    .memory_write_strobe(instruction_cache_memory_write_strobe),
    .memory_read_data(instruction_cache_memory_ddr3 ? instruction_ddr3_model_read_data :
                      instruction_memory[instruction_cache_memory_address[15:2]])
  );

  assign instruction_cache_memory_ddr3 = instruction_cache_memory_address >= DDR3_BASE_ADDRESS &&
                                         instruction_cache_memory_address < DDR3_END_ADDRESS;

  rv64_cache #(.LINE_COUNT(4)) data_cache (
    .clk(clk),
    .reset(reset),
    .request_valid(data_cache_request),
    .request_ready(data_cache_request_ready),
    .request_write(data_write),
    .request_address(data_physical_address),
    .request_write_data(data_write_data),
    .request_write_strobe(data_write_strobe),
    .response_valid(data_cache_response_valid),
    .response_read_data(data_cache_response_data),
    .memory_valid(data_cache_memory_valid),
    .memory_ready(data_cache_memory_ddr3 ? (USE_DDR3_MODEL ? ddr3_model_ready : 1'b1) : 1'b1),
    .memory_write(data_cache_memory_write),
    .memory_address(data_cache_memory_address),
    .memory_write_data(data_cache_memory_write_data),
    .memory_write_strobe(data_cache_memory_write_strobe),
    .memory_read_data(data_cache_memory_ddr3 && USE_DDR3_MODEL ? ddr3_model_read_data :
                      data_memory[data_cache_memory_address[15:3]])
  );

  assign data_cache_memory_ddr3 = data_cache_memory_address >= DDR3_BASE_ADDRESS &&
                                  data_cache_memory_address < DDR3_END_ADDRESS;

  always_comb begin
    instruction_pte_read_data = '0;
    data_pte_read_data = '0;
    if (instruction_pte_address[63:16] == 48'b0) begin
      instruction_pte_read_data = data_memory[instruction_pte_address[15:3]];
    end
    if (data_pte_address[63:16] == 48'b0) begin
      data_pte_read_data = data_memory[data_pte_address[15:3]];
    end
  end

  rv64_uart #(.BIT_CYCLES(UART_BIT_CYCLES)) uart (
    .clk(clk),
    .reset(reset),
    .request(uart_request),
    .write(data_write),
    .address(data_physical_address[11:0]),
    .write_data(data_write_data),
    .read_data(uart_read_data),
    .ready(uart_ready),
    .tx(uart_tx)
  );

  rv64_clint clint (
    .clk(clk),
    .reset(reset),
    .request(clint_request),
    .write(data_write),
    .address(data_physical_address[15:0]),
    .write_data(data_write_data),
    .write_strobe(data_write_strobe),
    .read_data(clint_read_data),
    .ready(clint_ready),
    .timer_interrupt(clint_timer_interrupt),
    .software_interrupt(clint_software_interrupt)
  );

  rv64_plic plic (
    .clk(clk),
    .reset(reset),
    .interrupt_sources(plic_sources),
    .request(plic_request),
    .write(data_write),
    .address(data_physical_address[21:0]),
    .write_data(data_write_data),
    .read_data(plic_read_data),
    .ready(plic_ready),
    .external_interrupt(plic_external_interrupt)
  );

  always_comb begin
    if (data_cache_request) begin
      data_read_data = data_cache_response_data;
    end else if (uart_request) begin
      data_read_data = uart_read_data;
    end else if (clint_request) begin
      data_read_data = clint_read_data;
    end else if (plic_request) begin
      data_read_data = plic_read_data;
    end else if (data_physical_address == LED_ADDRESS) begin
      data_read_data = {61'b0, led};
    end else begin
      data_read_data = data_memory[data_physical_address[15:3]];
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      led <= 3'b0;
      instruction_translation_complete <= 1'b0;
      instruction_translation_fault_latched <= 1'b0;
      instruction_translation_virtual_address <= '0;
      instruction_translation_satp <= '0;
      instruction_translation_privilege <= '0;
      instruction_translation_sum <= 1'b0;
      instruction_physical_address_latched <= '0;
      data_translation_complete <= 1'b0;
      data_translation_fault_latched <= 1'b0;
      data_translation_virtual_address <= '0;
      data_translation_satp <= '0;
      data_translation_privilege <= '0;
      data_translation_sum <= 1'b0;
      data_physical_address_latched <= '0;
    end else begin
      if (!mmu_enabled) begin
        instruction_translation_complete <= 1'b0;
        data_translation_complete <= 1'b0;
      end else begin
        if (instruction_translation_complete &&
            (instruction_address != instruction_translation_virtual_address ||
             satp_value != instruction_translation_satp ||
             privilege_mode != instruction_translation_privilege ||
             sum_enable != instruction_translation_sum)) begin
          instruction_translation_complete <= 1'b0;
        end
        if (instruction_translation_done && !instruction_translation_complete) begin
          instruction_translation_complete <= 1'b1;
          instruction_translation_fault_latched <= instruction_translation_fault;
          instruction_translation_virtual_address <= instruction_address;
          instruction_translation_satp <= satp_value;
          instruction_translation_privilege <= privilege_mode;
          instruction_translation_sum <= sum_enable;
          instruction_physical_address_latched <= instruction_mmu_physical_address;
        end
        if (!data_valid) begin
          data_translation_complete <= 1'b0;
        end else if (data_translation_complete &&
                     (data_address != data_translation_virtual_address ||
                      satp_value != data_translation_satp ||
                      privilege_mode != data_translation_privilege ||
                      sum_enable != data_translation_sum)) begin
          data_translation_complete <= 1'b0;
        end
        if (data_translation_done && !data_translation_complete) begin
          data_translation_complete <= 1'b1;
          data_translation_fault_latched <= data_translation_fault;
          data_translation_virtual_address <= data_address;
          data_translation_satp <= satp_value;
          data_translation_privilege <= privilege_mode;
          data_translation_sum <= sum_enable;
          data_physical_address_latched <= data_mmu_physical_address;
        end
      end

      if (data_cache_memory_valid && data_cache_memory_write &&
          data_cache_memory_address[63:16] == 48'b0) begin
        for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
          if (data_cache_memory_write_strobe[byte_index]) begin
            data_memory[data_cache_memory_address[15:3]][byte_index*8 +: 8] <=
              data_cache_memory_write_data[byte_index*8 +: 8];
          end
        end
      end

      if (data_valid && data_write && data_ready) begin
        if (data_physical_address == LED_ADDRESS) begin
          if (data_write_strobe[0]) begin
            led <= data_write_data[2:0];
          end
        end else if (!data_bram_request && !data_ddr3_request &&
                     !uart_request && !clint_request && !plic_request) begin
          for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
            if (data_write_strobe[byte_index]) begin
              data_memory[data_physical_address[15:3]][byte_index*8 +: 8] <= data_write_data[byte_index*8 +: 8];
            end
          end
        end
      end
    end
  end

  initial begin
    for (index = 0; index < 16384; index = index + 1) begin
      instruction_memory[index] = 32'h0000_0013;
    end
    for (index = 0; index < 8192; index = index + 1) begin
      data_memory[index] = 64'b0;
    end
  end
endmodule
