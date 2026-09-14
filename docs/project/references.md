# 规范与参考资料

实现时以发布版本的规范原文为准，不能仅凭博客或二手摘要实现指令语义。

- RISC-V Unprivileged ISA：<https://riscv.org/technical/specifications/>
- RISC-V Privileged ISA：<https://riscv.org/technical/specifications/>
- RISC-V Memory Model：<https://riscv.org/technical/specifications/>
- RISC-V ELF psABI：<https://github.com/riscv-non-isa/riscv-elf-psabi-doc>
- Linux RISC-V 文档：<https://www.kernel.org/doc/html/latest/riscv/index.html>
- Xilinx 7 Series FPGA 文档入口：<https://docs.amd.com/>

进入实现前应把采用的 RISC-V ISA/Privileged 规范版本、Linux 内核版本、Vivado 版本写入构建元数据。当前板级工具目标为 Vivado 2026.1。
