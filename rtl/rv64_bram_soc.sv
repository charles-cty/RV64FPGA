module rv64_bram_soc #(
  parameter bit JTAG_CONSOLE = 1'b0,
  parameter integer UART_BIT_CYCLES = 434,
  parameter logic USE_DDR3_MODEL = 1'b0,
  parameter logic USE_DDR3_EXTERNAL = 1'b0,
  parameter integer DDR3_MODEL_WORD_COUNT = 1024,
  parameter integer DDR3_MODEL_RESPONSE_DELAY = 2,
  parameter logic DDR3_MODEL_CALIBRATED = 1'b1,
  parameter string BOOT_ROM_INIT_FILE = "",
  parameter string DDR3_MODEL_INIT_FILE = ""
) (
  input  logic        clk,
  input  logic        reset,
  output logic [2:0]  led,
  output logic        uart_tx,
  input  logic        uart_rx,
  input logic console_rx_valid,
  input logic [7:0] console_rx_data,
  output logic console_rx_ready,
  output logic console_tx_valid,
  output logic [7:0] console_tx_data,
  input logic console_tx_ready,
  output logic        debug_commit_valid,
  output logic [63:0] debug_commit_pc,
  output logic [31:0] debug_commit_instruction,
  output logic        debug_commit_trap_valid,
  output logic [63:0] debug_commit_trap_cause,
  output logic        debug_illegal_instruction,
  output logic [1:0]  debug_privilege_mode,
  output logic [63:0] debug_satp_value,
  output logic [63:0] debug_instruction_address,
  output logic        debug_instruction_ready,
  output logic        debug_data_valid,
  output logic [63:0] debug_data_address,
  output logic        external_ddr3_request_valid,
  output logic        external_ddr3_request_write,
  output logic [63:0] external_ddr3_request_address,
  output logic [63:0] external_ddr3_request_write_data,
  output logic [7:0]  external_ddr3_request_write_strobe,
  input  logic        external_ddr3_request_ready,
  input  logic [63:0] external_ddr3_response_read_data,
  input  logic        external_ddr3_response_error
);
  import riscv_pkg::*;

  localparam logic [63:0] LED_ADDRESS = 64'h0000_0000_1000_1000;
  localparam logic [63:0] UART_ADDRESS = 64'h0000_0000_1000_0000;
  localparam logic [63:0] CLINT_ADDRESS = 64'h0000_0000_0200_0000;
  localparam logic [63:0] PLIC_ADDRESS = 64'h0000_0000_0c00_0000;
  localparam logic [63:0] DDR3_BASE_ADDRESS = 64'h0000_0000_8000_0000;
  localparam logic [63:0] DDR3_END_ADDRESS = 64'h0000_0001_0000_0000;

  localparam integer INTERNAL_DATA_MEMORY_WORD_COUNT = USE_DDR3_EXTERNAL ? 1 : 8192;

  (* ram_style = "block" *) logic [31:0] instruction_memory [0:16383];
  logic [63:0] data_memory [0:INTERNAL_DATA_MEMORY_WORD_COUNT-1];
  logic [63:0] instruction_address;
  logic [63:0] instruction_physical_address;
  logic [63:0] instruction_mmu_physical_address;
  logic [31:0] instruction_data;
  logic [31:0] instruction_bram_read_data;
  logic [13:0] instruction_bram_read_address;
  logic instruction_bram_read_valid;
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
  logic        data_instruction_active;
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
  logic [1:0] data_privilege;
  logic [63:0] satp_value;
  logic sum_enable;
  logic mxr_enable;
  logic [1:0] core_privilege_mode;
  logic [1:0] core_data_privilege;
  logic [63:0] core_satp_value;
  logic core_sum_enable;
  logic core_mxr_enable;
  logic sfence_valid;
  logic [63:0] sfence_virtual_address;
  logic sfence_all;
  logic fence_i_valid;
  logic atomic_access;
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
  logic instruction_translation_mxr;
  logic [63:0] instruction_physical_address_latched;
  logic instruction_pte_request;
  logic [63:0] instruction_pte_address;
  logic [63:0] instruction_pte_read_data;
  logic instruction_pte_update_valid;
  logic [63:0] instruction_pte_update_address;
  logic [63:0] instruction_pte_update_data;
  logic data_translation_done;
  logic data_translation_fault;
  logic data_translation_complete;
  logic data_translation_fault_latched;
  logic [63:0] data_translation_virtual_address;
  logic [63:0] data_translation_satp;
  logic [1:0] data_translation_privilege;
  logic data_translation_sum;
  logic data_translation_mxr;
  logic [63:0] data_physical_address_latched;
  logic data_translation_ready;
  logic data_bram_request;
  logic data_ddr3_access;
  logic data_ddr3_request;
  logic data_cache_request;
  logic atomic_bram_access;
  logic atomic_ddr3_access;
  logic atomic_ddr3_request_valid;
  logic atomic_ddr3_request_write;
  logic [63:0] atomic_ddr3_request_address;
  logic [63:0] atomic_ddr3_request_write_data;
  logic [7:0] atomic_ddr3_request_write_strobe;
  logic atomic_ddr3_request_ready;
  logic [63:0] atomic_ddr3_old_data;
  logic atomic_ddr3_error;
  logic atomic_ddr3_error_latched;
  typedef enum logic [1:0] {ATOMIC_DDR3_IDLE, ATOMIC_DDR3_READ,
                            ATOMIC_DDR3_WRITE, ATOMIC_DDR3_COMPLETE} atomic_ddr3_state_t;
  atomic_ddr3_state_t atomic_ddr3_state;
  logic data_cache_request_ready;
  logic data_cache_response_valid;
  logic [63:0] data_cache_response_data;
  logic instruction_cache_response_ready;
  logic data_cache_response_ready;
  logic data_cache_memory_valid;
  logic data_cache_memory_write;
  logic [63:0] data_cache_memory_address;
  logic [63:0] data_cache_memory_write_data;
  logic [7:0] data_cache_memory_write_strobe;
  logic data_cache_memory_ddr3;
  logic ddr3_model_ready;
  logic [63:0] ddr3_model_read_data;
  logic ddr3_model_error;
  logic ddr3_memory_request_valid;
  logic ddr3_memory_request_write;
  logic [63:0] ddr3_memory_request_address;
  logic [63:0] ddr3_memory_request_write_data;
  logic [7:0] ddr3_memory_request_write_strobe;
  logic ddr3_memory_request_ready;
  logic [63:0] ddr3_memory_response_read_data;
  logic ddr3_memory_response_error;
  logic ddr3_model_request_ready;
  logic [63:0] ddr3_model_response_read_data;
  logic ddr3_model_response_error;
  logic data_pte_request;
  logic [63:0] data_pte_address;
  logic [63:0] data_pte_read_data;
  logic data_pte_update_valid;
  logic [63:0] data_pte_update_address;
  logic [63:0] data_pte_update_data;
  logic instruction_pte_ddr3;
  logic data_pte_ddr3;
  logic instruction_pte_ready;
  logic data_pte_ready;
  logic instruction_pte_write_pending;
  logic data_pte_write_pending;
  logic [63:0] instruction_pte_write_address_pending;
  logic [63:0] instruction_pte_write_data_pending;
  logic [63:0] data_pte_write_address_pending;
  logic [63:0] data_pte_write_data_pending;
  logic pte_master_active;
  logic pte_master_owner;
  logic pte_master_valid;
  logic pte_master_write;
  logic [63:0] pte_master_address;
  logic [63:0] pte_master_write_data;
  logic [7:0] pte_master_write_strobe;
  logic pte_master_ready;
  logic [63:0] pte_master_response_read_data;
  logic pte_master_response_error;
  logic pte_master_write_latched;
  logic [63:0] pte_master_address_latched;
  logic [63:0] pte_master_write_data_latched;
  logic [7:0] pte_master_write_strobe_latched;
  logic instruction_mmu_enabled;
  logic data_mmu_enabled;
  logic        uart_request;
  logic        uart_ready;
  logic [63:0] uart_read_data;
  logic        uart_interrupt;
  integer index;
  integer byte_index;

  assign debug_commit_valid = commit_valid;
  assign debug_commit_pc = commit_pc;
  assign debug_commit_instruction = commit_instruction;
  assign debug_commit_trap_valid = commit_trap_valid;
  assign debug_commit_trap_cause = commit_trap_cause;
  assign debug_illegal_instruction = illegal_instruction;
  assign debug_privilege_mode = privilege_mode;
  assign debug_satp_value = satp_value;
  assign debug_instruction_address = instruction_address;
  assign debug_instruction_ready = instruction_ready;
  assign debug_data_valid = data_valid;
  assign debug_data_address = data_address;

  rv64_core core (
    .privilege_mode(core_privilege_mode),
    .data_privilege(core_data_privilege),
    .satp_value(core_satp_value),
    .sum_enable(core_sum_enable),
    .mxr_enable(core_mxr_enable),
    .*
  );

  // Address translation must observe CSR and privilege changes on the same
  // cycle as the core. Registering this context here leaves one fetch using
  // the previous mode after mret/sret or a satp write, which can route a
  // high-half virtual address into the boot ROM by its low address bits.
  assign privilege_mode = core_privilege_mode;
  assign data_privilege = core_data_privilege;
  assign satp_value = core_satp_value;
  assign sum_enable = core_sum_enable;
  assign mxr_enable = core_mxr_enable;

  always_ff @(posedge clk) begin
    if (reset) begin
      instruction_bram_read_data <= '0;
      instruction_bram_read_address <= '0;
      instruction_bram_read_valid <= 1'b0;
    end else if (!instruction_cache_request && instruction_translation_ready) begin
      instruction_bram_read_data <= instruction_memory[instruction_physical_address[15:2]];
      instruction_bram_read_address <= instruction_physical_address[15:2];
      instruction_bram_read_valid <= 1'b1;
    end else begin
      instruction_bram_read_valid <= 1'b0;
    end
  end

  assign instruction_mmu_enabled = (privilege_mode != 2'b11) && (satp_value[63:60] == 4'h8);
  assign data_mmu_enabled = (data_privilege != 2'b11) && (satp_value[63:60] == 4'h8);
  assign instruction_pte_ddr3 = (USE_DDR3_MODEL || USE_DDR3_EXTERNAL) &&
                                instruction_pte_address >= DDR3_BASE_ADDRESS &&
                                instruction_pte_address < DDR3_END_ADDRESS;
  assign data_pte_ddr3 = (USE_DDR3_MODEL || USE_DDR3_EXTERNAL) &&
                         data_pte_address >= DDR3_BASE_ADDRESS &&
                         data_pte_address < DDR3_END_ADDRESS;
  // A/D writeback can overlap the next walk from the same MMU. Its write
  // acknowledgement has no PTE data and must not advance that walk.
  assign instruction_pte_ready = instruction_pte_ddr3 ?
                                 (pte_master_active && !pte_master_owner &&
                                  !pte_master_write_latched && pte_master_ready) :
                                 instruction_pte_request;
  assign data_pte_ready = data_pte_ddr3 ?
                          (pte_master_active && pte_master_owner &&
                           !pte_master_write_latched && pte_master_ready) :
                          data_pte_request;
  assign instruction_physical_address = instruction_mmu_enabled ?
                                        ((instruction_translation_complete &&
                                          instruction_address == instruction_translation_virtual_address &&
                                          satp_value == instruction_translation_satp &&
                                          privilege_mode == instruction_translation_privilege &&
                                          sum_enable == instruction_translation_sum &&
                                          mxr_enable == instruction_translation_mxr &&
                                          !instruction_translation_fault_latched) ?
                                         instruction_physical_address_latched : 64'b0) : instruction_address;
  assign instruction_translation_ready = !instruction_mmu_enabled ||
                                         (instruction_translation_complete &&
                                          instruction_address == instruction_translation_virtual_address &&
                                          satp_value == instruction_translation_satp &&
                                          privilege_mode == instruction_translation_privilege &&
                                          sum_enable == instruction_translation_sum &&
                                          mxr_enable == instruction_translation_mxr);
  assign instruction_ddr3_access = instruction_translation_ready &&
                                   !instruction_translation_fault_latched &&
                                   instruction_physical_address >= DDR3_BASE_ADDRESS &&
                                   instruction_physical_address < DDR3_END_ADDRESS;
  assign instruction_cache_request = instruction_ddr3_access &&
                                    (USE_DDR3_MODEL || USE_DDR3_EXTERNAL);
  assign instruction_data = instruction_cache_request ?
                            (instruction_physical_address[2] ? instruction_cache_response_data[63:32] :
                             instruction_cache_response_data[31:0]) :
                            instruction_bram_read_data;
  assign instruction_ready = instruction_translation_ready &&
                             (instruction_cache_request ?
                             (instruction_cache_response_valid || instruction_ddr3_model_error) :
                             (instruction_bram_read_valid &&
                              instruction_bram_read_address == instruction_physical_address[15:2]));
  assign data_instruction_active = data_valid && instruction_ready;
  assign instruction_cache_response_ready = !data_valid || data_ready;
  assign data_cache_response_ready = data_instruction_active && data_ready;
  assign instruction_fault = (instruction_mmu_enabled && instruction_translation_ready &&
                              instruction_translation_fault_latched) ||
                             (instruction_ddr3_access && !(USE_DDR3_MODEL || USE_DDR3_EXTERNAL)) ||
                             (instruction_cache_memory_valid && instruction_cache_memory_ddr3 &&
                              instruction_ddr3_model_error);
  assign data_physical_address = data_mmu_enabled ?
                                 ((data_translation_complete &&
                                   data_address == data_translation_virtual_address &&
                                   satp_value == data_translation_satp &&
                                   data_privilege == data_translation_privilege &&
                                   sum_enable == data_translation_sum &&
                                   mxr_enable == data_translation_mxr &&
                                   !data_translation_fault_latched) ?
                                  data_physical_address_latched : 64'b0) : data_address;
  assign data_translation_ready = !data_mmu_enabled ||
                                  (data_translation_complete &&
                                   data_address == data_translation_virtual_address &&
                                   satp_value == data_translation_satp &&
                                   data_privilege == data_translation_privilege &&
                                   sum_enable == data_translation_sum &&
                                   mxr_enable == data_translation_mxr &&
                                   !data_translation_fault_latched);
  assign uart_request = data_instruction_active && data_translation_ready &&
                        (data_physical_address[63:12] == UART_ADDRESS[63:12]);
  assign clint_request = data_instruction_active && data_translation_ready &&
                         (data_physical_address[63:16] == CLINT_ADDRESS[63:16]);
  assign plic_request = data_instruction_active && data_translation_ready &&
                        (data_physical_address[63:22] == PLIC_ADDRESS[63:22]);
  assign data_bram_request = data_instruction_active && data_translation_ready &&
                             data_physical_address[63:16] == 48'b0;
  assign data_ddr3_access = data_translation_ready &&
                             data_physical_address >= DDR3_BASE_ADDRESS &&
                             data_physical_address < DDR3_END_ADDRESS;
  assign atomic_ddr3_access = (USE_DDR3_MODEL || USE_DDR3_EXTERNAL) && atomic_access &&
                              data_instruction_active && data_ddr3_access;
  assign data_ddr3_request = data_instruction_active && data_ddr3_access && !atomic_ddr3_access;
  assign atomic_bram_access = atomic_access && data_bram_request && !data_ddr3_access;
  assign data_cache_request = (data_bram_request || data_ddr3_request) && !atomic_bram_access &&
                              !atomic_ddr3_access;
  assign data_ready = data_translation_ready &&
                      (atomic_ddr3_access ? (atomic_ddr3_state == ATOMIC_DDR3_COMPLETE) :
                       data_cache_request ? data_cache_response_valid :
                       uart_request ? uart_ready :
                       clint_request ? clint_ready :
                       plic_request ? plic_ready : 1'b1);
  assign data_fault = (data_mmu_enabled && data_translation_complete &&
                       data_address == data_translation_virtual_address &&
                       satp_value == data_translation_satp &&
                       data_privilege == data_translation_privilege &&
                       sum_enable == data_translation_sum &&
                       mxr_enable == data_translation_mxr &&
                       data_translation_fault_latched) ||
                      (data_ddr3_access && !(USE_DDR3_MODEL || USE_DDR3_EXTERNAL)) ||
                      (data_cache_memory_valid && data_cache_memory_ddr3 &&
                       ddr3_model_error) ||
                      (atomic_ddr3_access && atomic_ddr3_state == ATOMIC_DDR3_COMPLETE &&
                       atomic_ddr3_error_latched);
  assign software_interrupt = clint_software_interrupt;
  assign timer_interrupt = clint_timer_interrupt;
  assign external_interrupt = plic_external_interrupt;
  assign plic_sources = {30'b0, uart_interrupt, 1'b0};
  assign atomic_ddr3_request_valid = atomic_ddr3_access &&
                                     (atomic_ddr3_state == ATOMIC_DDR3_READ ||
                                      atomic_ddr3_state == ATOMIC_DDR3_WRITE);
  assign atomic_ddr3_request_write = atomic_ddr3_state == ATOMIC_DDR3_WRITE;
  // The DDR port transfers aligned 64-bit words. AMO.W/LR.W/SC.W may
  // address either 32-bit lane; the core consumes and produces lane-local data.
  assign atomic_ddr3_request_address = {data_physical_address[63:3], 3'b000};
  assign atomic_ddr3_request_write_data = data_write_data << (data_physical_address[2:0] * 8);
  assign atomic_ddr3_request_write_strobe = data_write_strobe << data_physical_address[2:0];
  assign atomic_ddr3_request_ready = ddr3_model_ready;
  assign atomic_ddr3_error = ddr3_model_error;

  rv64_mmu instruction_mmu (
    .clk(clk),
    .reset(reset),
    .translate_valid(instruction_mmu_enabled && !instruction_translation_complete &&
                     !instruction_translation_done),
    .virtual_address(instruction_address),
    .access(MMU_FETCH),
    .privilege(privilege_mode),
    .sum_enable(sum_enable),
    .mxr_enable(mxr_enable),
    .satp(satp_value),
    .pte_request(instruction_pte_request),
    .pte_address(instruction_pte_address),
    .pte_read_data(instruction_pte_read_data),
    .pte_ready(instruction_pte_ready),
    .pte_update_valid(instruction_pte_update_valid),
    .pte_update_address(instruction_pte_update_address),
    .pte_update_data(instruction_pte_update_data),
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
    .translate_valid(data_mmu_enabled && data_instruction_active && !data_translation_complete &&
                     !data_translation_done),
    .virtual_address(data_address),
    .access(data_write ? MMU_STORE : MMU_LOAD),
    .privilege(data_privilege),
    .sum_enable(sum_enable),
    .mxr_enable(mxr_enable),
    .satp(satp_value),
    .pte_request(data_pte_request),
    .pte_address(data_pte_address),
    .pte_read_data(data_pte_read_data),
    .pte_ready(data_pte_ready),
    .pte_update_valid(data_pte_update_valid),
    .pte_update_address(data_pte_update_address),
    .pte_update_data(data_pte_update_data),
    .sfence_valid(sfence_valid),
    .sfence_all(sfence_all),
    .sfence_virtual_address(sfence_virtual_address),
    .translation_done(data_translation_done),
    .translation_fault(data_translation_fault),
    .physical_address(data_mmu_physical_address),
    .busy()
  );

  rv64_ddr3_arbiter ddr3_arbiter (
    .clk(clk),
    .reset(reset),
    .instruction_request_valid((USE_DDR3_MODEL || USE_DDR3_EXTERNAL) &&
                               instruction_cache_memory_valid && instruction_cache_memory_ddr3),
    .instruction_request_write(instruction_cache_memory_write),
    .instruction_request_address(instruction_cache_memory_address - DDR3_BASE_ADDRESS),
    .instruction_request_write_data(instruction_cache_memory_write_data),
    .instruction_request_write_strobe(instruction_cache_memory_write_strobe),
    .instruction_request_ready(instruction_ddr3_model_ready),
    .instruction_response_read_data(instruction_ddr3_model_read_data),
    .instruction_response_error(instruction_ddr3_model_error),
    .data_request_valid((USE_DDR3_MODEL || USE_DDR3_EXTERNAL) &&
                        ((data_cache_memory_valid && data_cache_memory_ddr3) ||
                         atomic_ddr3_request_valid)),
    .data_request_write(atomic_ddr3_request_valid ? atomic_ddr3_request_write : data_cache_memory_write),
    .data_request_address(atomic_ddr3_request_valid ? atomic_ddr3_request_address - DDR3_BASE_ADDRESS :
                          data_cache_memory_address - DDR3_BASE_ADDRESS),
    .data_request_write_data(atomic_ddr3_request_valid ? atomic_ddr3_request_write_data :
                             data_cache_memory_write_data),
    .data_request_write_strobe(atomic_ddr3_request_valid ? atomic_ddr3_request_write_strobe :
                               data_cache_memory_write_strobe),
    .data_request_ready(ddr3_model_ready),
    .data_response_read_data(ddr3_model_read_data),
    .data_response_error(ddr3_model_error),
    .pte_request_valid(pte_master_valid),
    .pte_request_write(pte_master_write),
    .pte_request_address(pte_master_address),
    .pte_request_write_data(pte_master_write_data),
    .pte_request_write_strobe(pte_master_write_strobe),
    .pte_request_ready(pte_master_ready),
    .pte_response_read_data(pte_master_response_read_data),
    .pte_response_error(pte_master_response_error),
    .memory_request_valid(ddr3_memory_request_valid),
    .memory_request_write(ddr3_memory_request_write),
    .memory_request_address(ddr3_memory_request_address),
    .memory_request_write_data(ddr3_memory_request_write_data),
    .memory_request_write_strobe(ddr3_memory_request_write_strobe),
    .memory_request_ready(ddr3_memory_request_ready),
    .memory_response_read_data(ddr3_memory_response_read_data),
    .memory_response_error(ddr3_memory_response_error)
  );

  assign ddr3_memory_request_ready = USE_DDR3_EXTERNAL ? external_ddr3_request_ready :
                                     ddr3_model_request_ready;
  assign ddr3_memory_response_read_data = USE_DDR3_EXTERNAL ? external_ddr3_response_read_data :
                                          ddr3_model_response_read_data;
  assign ddr3_memory_response_error = USE_DDR3_EXTERNAL ? external_ddr3_response_error :
                                      ddr3_model_response_error;
  assign external_ddr3_request_valid = USE_DDR3_EXTERNAL && ddr3_memory_request_valid;
  assign external_ddr3_request_write = ddr3_memory_request_write;
  // The arbiter and behavioral model use DDR-relative offsets. The external
  // endpoint is a system boundary and therefore receives physical addresses.
  assign external_ddr3_request_address = DDR3_BASE_ADDRESS + ddr3_memory_request_address;
  assign external_ddr3_request_write_data = ddr3_memory_request_write_data;
  assign external_ddr3_request_write_strobe = ddr3_memory_request_write_strobe;

  rv64_ddr3_model #(.WORD_COUNT(DDR3_MODEL_WORD_COUNT),
                    .RESPONSE_DELAY(DDR3_MODEL_RESPONSE_DELAY),
                    .INIT_FILE(DDR3_MODEL_INIT_FILE)) ddr3_model (
    .clk(clk),
    .reset(reset),
    .calibrated(DDR3_MODEL_CALIBRATED),
    .request_valid(ddr3_memory_request_valid && !USE_DDR3_EXTERNAL),
    .request_write(ddr3_memory_request_write),
    .request_address(ddr3_memory_request_address),
    .request_write_data(ddr3_memory_request_write_data),
    .request_write_strobe(ddr3_memory_request_write_strobe),
    .request_ready(ddr3_model_request_ready),
    .response_read_data(ddr3_model_response_read_data),
    .response_error(ddr3_model_response_error)
  );

  rv64_cache #(.LINE_COUNT(4)) instruction_cache (
    .clk(clk),
    .reset(reset),
    .request_valid(instruction_cache_request),
    .invalidate(fence_i_valid),
    .request_ready(),
    .request_write(1'b0),
    .request_address(instruction_physical_address),
    .request_write_data('0),
    .request_write_strobe('0),
    .response_valid(instruction_cache_response_valid),
    .response_read_data(instruction_cache_response_data),
    .response_ready(instruction_cache_response_ready),
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
    .invalidate(atomic_bram_access || atomic_ddr3_access),
    .request_ready(data_cache_request_ready),
    .request_write(data_write),
    .request_address(data_physical_address),
    .request_write_data(data_write_data << (data_physical_address[2:0] * 8)),
    .request_write_strobe(data_write_strobe << data_physical_address[2:0]),
    .response_valid(data_cache_response_valid),
    .response_read_data(data_cache_response_data),
    .response_ready(data_cache_response_ready),
    .memory_valid(data_cache_memory_valid),
    .memory_ready(data_cache_memory_ddr3 ? ddr3_model_ready : 1'b1),
    .memory_write(data_cache_memory_write),
    .memory_address(data_cache_memory_address),
    .memory_write_data(data_cache_memory_write_data),
    .memory_write_strobe(data_cache_memory_write_strobe),
    .memory_read_data(data_cache_memory_ddr3 && (USE_DDR3_MODEL || USE_DDR3_EXTERNAL) ?
                      ddr3_model_read_data :
                      data_memory[data_cache_memory_address[15:3]])
  );

  assign data_cache_memory_ddr3 = data_cache_memory_address >= DDR3_BASE_ADDRESS &&
                                  data_cache_memory_address < DDR3_END_ADDRESS;

  always_comb begin
    instruction_pte_read_data = '0;
    data_pte_read_data = '0;
    if (instruction_pte_ddr3) begin
      instruction_pte_read_data = pte_master_response_error ? 64'b0 :
                                   pte_master_response_read_data;
    end else if (instruction_pte_address[63:16] == 48'b0) begin
      instruction_pte_read_data = data_memory[instruction_pte_address[15:3]];
    end
    if (data_pte_ddr3) begin
      data_pte_read_data = pte_master_response_error ? 64'b0 :
                           pte_master_response_read_data;
    end else if (data_pte_address[63:16] == 48'b0) begin
      data_pte_read_data = data_memory[data_pte_address[15:3]];
    end
  end

  always_comb begin
    pte_master_valid = pte_master_active;
    pte_master_write = pte_master_write_latched;
    pte_master_address = pte_master_address_latched;
    pte_master_write_data = pte_master_write_data_latched;
    pte_master_write_strobe = pte_master_write_strobe_latched;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      instruction_pte_write_pending <= 1'b0;
      data_pte_write_pending <= 1'b0;
      instruction_pte_write_address_pending <= '0;
      instruction_pte_write_data_pending <= '0;
      data_pte_write_address_pending <= '0;
      data_pte_write_data_pending <= '0;
      pte_master_active <= 1'b0;
      pte_master_owner <= 1'b0;
      pte_master_write_latched <= 1'b0;
      pte_master_address_latched <= '0;
      pte_master_write_data_latched <= '0;
      pte_master_write_strobe_latched <= '0;
    end else begin
      if (instruction_pte_update_valid && instruction_pte_ddr3) begin
        instruction_pte_write_pending <= 1'b1;
        instruction_pte_write_address_pending <= instruction_pte_update_address;
        instruction_pte_write_data_pending <= instruction_pte_update_data;
      end
      if (data_pte_update_valid && data_pte_ddr3) begin
        data_pte_write_pending <= 1'b1;
        data_pte_write_address_pending <= data_pte_update_address;
        data_pte_write_data_pending <= data_pte_update_data;
      end

      if (pte_master_active) begin
        if (pte_master_ready) begin
          pte_master_active <= 1'b0;
          if (pte_master_write_latched) begin
            if (pte_master_owner) begin
              if (!(data_pte_update_valid && data_pte_ddr3)) begin
                data_pte_write_pending <= 1'b0;
              end
            end else begin
              if (!(instruction_pte_update_valid && instruction_pte_ddr3)) begin
                instruction_pte_write_pending <= 1'b0;
              end
            end
          end
        end
      end else if (instruction_pte_write_pending) begin
        pte_master_active <= 1'b1;
        pte_master_owner <= 1'b0;
        pte_master_write_latched <= 1'b1;
        pte_master_address_latched <= instruction_pte_write_address_pending - DDR3_BASE_ADDRESS;
        pte_master_write_data_latched <= instruction_pte_write_data_pending;
        pte_master_write_strobe_latched <= 8'hff;
      end else if (data_pte_write_pending) begin
        pte_master_active <= 1'b1;
        pte_master_owner <= 1'b1;
        pte_master_write_latched <= 1'b1;
        pte_master_address_latched <= data_pte_write_address_pending - DDR3_BASE_ADDRESS;
        pte_master_write_data_latched <= data_pte_write_data_pending;
        pte_master_write_strobe_latched <= 8'hff;
      end else if (instruction_pte_request && instruction_pte_ddr3) begin
        pte_master_active <= 1'b1;
        pte_master_owner <= 1'b0;
        pte_master_write_latched <= 1'b0;
        pte_master_address_latched <= instruction_pte_address - DDR3_BASE_ADDRESS;
        pte_master_write_data_latched <= '0;
        pte_master_write_strobe_latched <= '0;
      end else if (data_pte_request && data_pte_ddr3) begin
        pte_master_active <= 1'b1;
        pte_master_owner <= 1'b1;
        pte_master_write_latched <= 1'b0;
        pte_master_address_latched <= data_pte_address - DDR3_BASE_ADDRESS;
        pte_master_write_data_latched <= '0;
        pte_master_write_strobe_latched <= '0;
      end
    end
  end

  rv64_uart #(.BIT_CYCLES(UART_BIT_CYCLES), .JTAG_CONSOLE(JTAG_CONSOLE)) uart (
    .clk(clk),
    .reset(reset),
    .request(uart_request),
    .write(data_write),
    .address(data_physical_address[11:0]),
    .write_data(data_write_data),
    .read_data(uart_read_data),
    .ready(uart_ready),
    .tx(uart_tx),
    .rx(uart_rx),
    .console_rx_valid(console_rx_valid), .console_rx_data(console_rx_data),
    .console_rx_ready(console_rx_ready), .console_tx_valid(console_tx_valid),
    .console_tx_data(console_tx_data), .console_tx_ready(console_tx_ready),
    .interrupt(uart_interrupt)
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
    if (atomic_ddr3_access) begin
      data_read_data = atomic_ddr3_old_data >> (data_physical_address[2:0] * 8);
    end else if (data_cache_request) begin
      data_read_data = data_cache_response_data >> (data_physical_address[2:0] * 8);
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
      instruction_translation_mxr <= 1'b0;
      instruction_physical_address_latched <= '0;
      data_translation_complete <= 1'b0;
      data_translation_fault_latched <= 1'b0;
      data_translation_virtual_address <= '0;
      data_translation_satp <= '0;
      data_translation_privilege <= '0;
      data_translation_sum <= 1'b0;
      data_translation_mxr <= 1'b0;
      data_physical_address_latched <= '0;
      atomic_ddr3_state <= ATOMIC_DDR3_IDLE;
      atomic_ddr3_old_data <= '0;
      atomic_ddr3_error_latched <= 1'b0;
    end else begin
      case (atomic_ddr3_state)
        ATOMIC_DDR3_IDLE: begin
          if (atomic_ddr3_access) begin
            atomic_ddr3_error_latched <= 1'b0;
            atomic_ddr3_state <= ATOMIC_DDR3_READ;
          end
        end
        ATOMIC_DDR3_READ: begin
          if (atomic_ddr3_request_ready) begin
            atomic_ddr3_error_latched <= atomic_ddr3_error;
            if (!atomic_ddr3_error) begin
              atomic_ddr3_old_data <= ddr3_model_read_data;
              atomic_ddr3_state <= data_write ? ATOMIC_DDR3_WRITE : ATOMIC_DDR3_COMPLETE;
            end else begin
              atomic_ddr3_state <= ATOMIC_DDR3_COMPLETE;
            end
          end
        end
        ATOMIC_DDR3_WRITE: begin
          if (atomic_ddr3_request_ready) begin
            atomic_ddr3_error_latched <= atomic_ddr3_error;
            atomic_ddr3_state <= ATOMIC_DDR3_COMPLETE;
          end
        end
        ATOMIC_DDR3_COMPLETE: begin
          if (data_instruction_active) begin
            atomic_ddr3_state <= ATOMIC_DDR3_IDLE;
          end
        end
        default: atomic_ddr3_state <= ATOMIC_DDR3_IDLE;
      endcase

      if (!instruction_mmu_enabled) begin
        instruction_translation_complete <= 1'b0;
      end else begin
        if (instruction_translation_complete &&
            (instruction_address != instruction_translation_virtual_address ||
             satp_value != instruction_translation_satp ||
             privilege_mode != instruction_translation_privilege ||
             sum_enable != instruction_translation_sum ||
             mxr_enable != instruction_translation_mxr)) begin
          instruction_translation_complete <= 1'b0;
        end
        if (instruction_translation_done && !instruction_translation_complete) begin
          instruction_translation_complete <= 1'b1;
          instruction_translation_fault_latched <= instruction_translation_fault;
          instruction_translation_virtual_address <= instruction_address;
          instruction_translation_satp <= satp_value;
          instruction_translation_privilege <= privilege_mode;
          instruction_translation_sum <= sum_enable;
          instruction_translation_mxr <= mxr_enable;
          instruction_physical_address_latched <= instruction_mmu_physical_address;
        end
      end
      if (!data_mmu_enabled) begin
        data_translation_complete <= 1'b0;
      end else begin
        if (!data_instruction_active) begin
          data_translation_complete <= 1'b0;
        end else if (data_translation_complete &&
                     (data_address != data_translation_virtual_address ||
                      satp_value != data_translation_satp ||
                      data_privilege != data_translation_privilege ||
                      sum_enable != data_translation_sum ||
                      mxr_enable != data_translation_mxr)) begin
          data_translation_complete <= 1'b0;
        end
        if (data_translation_done && !data_translation_complete) begin
          data_translation_complete <= 1'b1;
          data_translation_fault_latched <= data_translation_fault;
          data_translation_virtual_address <= data_address;
          data_translation_satp <= satp_value;
          data_translation_privilege <= data_privilege;
          data_translation_sum <= sum_enable;
          data_translation_mxr <= mxr_enable;
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

      if (instruction_pte_update_valid && instruction_pte_update_address[63:16] == 48'b0) begin
        data_memory[instruction_pte_update_address[15:3]] <= instruction_pte_update_data;
      end
      if (data_pte_update_valid && data_pte_update_address[63:16] == 48'b0) begin
        data_memory[data_pte_update_address[15:3]] <= data_pte_update_data;
      end

      if (data_instruction_active && data_write && data_ready) begin
        if (data_physical_address == LED_ADDRESS) begin
          if (data_write_strobe[0]) begin
            led <= data_write_data[2:0];
          end
        end else if ((!data_bram_request && !data_ddr3_request &&
                      !uart_request && !clint_request && !plic_request) ||
                     atomic_bram_access) begin
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
    for (index = 0; index < INTERNAL_DATA_MEMORY_WORD_COUNT; index = index + 1) begin
      data_memory[index] = 64'b0;
    end
    if (BOOT_ROM_INIT_FILE != "") begin
      $readmemh(BOOT_ROM_INIT_FILE, instruction_memory);
    end
  end
endmodule
