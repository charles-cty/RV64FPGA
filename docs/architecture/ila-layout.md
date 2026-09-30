# 已验收 ILA 布局（2026-09-30）

与主 `rtl/rv64_mig_soc_top.sv` 及成功位流对应。

- `debug_status[3]`：commit valid；`[4]`：trap valid。
- `debug_commit_trace[225:162]` satp；`[161:160]` live privilege；
  `[159:96]` cause；`[95:64]` instruction；`[63:0]` PC。
- cause 只在 commit 与 trap 同时有效时解释。特权转换时 live privilege 可能是目标模式。
- `debug_memory_trace` 为数据 MMU 观测，下列为精确位映射：

```text
129: soc.data_valid
128: soc.data_fault
127: soc.data_translation_fault
126: soc.data_translation_fault_latched
125: soc.data_pte_ready
124: soc.data_pte_request
123: soc.data_pte_update_valid
122: soc.data_pte_write_pending
121: soc.pte_master_write_latched
120: soc.pte_master_active
119: soc.pte_master_owner
118: soc.pte_master_ready
117: soc.pte_master_response_error
116: soc.ddr3_model_error
115: soc.data_mmu.tlb_match_valid
114: soc.data_mmu.tlb_match_permission
113: soc.data_mmu_enabled
112: soc.instruction_ready
111: soc.data_translation_complete
110: soc.data_write
109: soc.data_ready
108: soc.data_translation_done
107: soc.sum_enable
106: soc.mxr_enable
105:104: soc.data_privilege
103:102: soc.data_mmu.request_privilege
101:100: soc.data_mmu.request_access
99:98: soc.data_mmu.level
97: soc.data_translation_ready
96: soc.atomic_access
95:64: soc.data_pte_address[31:0]
63:0: soc.data_pte_read_data
```

`tools/analyze_ila_capture.py` 解析提交记录，必须使用匹配软件的 System.map。
不要用旧 CLINT memory trace 布局解释这个基线的 probe4。
