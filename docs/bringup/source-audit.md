# LC480T 原始资料审计

## Word 文档检查

在 `C:\My\Projects\FPGA\docs\LC480T` 中共找到一个 Word 文件：

```text
vivado 板卡文件\新建 DOCX 文档 (2).docx
```

检查日期：2026-09-14。文档创建于 2024-12-21，作者元数据为 `dhj2`，最后修改者为 `DHJ`。

该 DOCX 没有可提取的正文文字、表格、页眉或页脚，内容由三张 PNG 截图组成。已逐张检查全部图片，得到以下信息：

1. 把 `ypcb003381p1` board file 安装到 Vivado 的 `data/boards/board_files` 后，可选择 `YPCB-00338-1P1 Accelerator Card`。
2. 截图中的 part 为 `xc7k480tffg1156-2`，board revision 为 1.0。
3. Board 面板列出 50 MHz 单端系统时钟、两组 200 MHz 差分系统时钟、DDR3、用户 LED、I2C 和 PCI Express。
4. DDR3 board component 的描述为 `4GB DDR3 memory components`。
5. 文档提醒 PCIe 接收端口可能出现约束失败，需要手工补充约束；实际工程必须结合 `PCIE.xdc` 和实现报告验证，不能只依赖截图。
6. JTAG 调试口为 14 针 JTAG-HS3 布局：奇数脚接地，偶数脚依次包含 VREF、TMS、TCK、TDO、TDI 和 SRST。
7. 固化截图选择 Micron BPI x16 配置 flash `mt28gu512aax1e-bpi-x16`。

## 证据等级

- pin、时钟和接口名称优先采用 board XML、MIG `.prj`、UCF/XDC 等机器可读文件。
- Word 截图用于补充操作流程和容量描述，不作为信号完整性、实际装片或硬件通过的证明。
- 4 GB DDR3、LED active-high、flash 型号和 PCIe lane 均须在实际硬件上验证。

## 未发现的信息

- 没有 UART 专用管脚、连接器或电气标准。
- 没有 Linux console 接线说明。
- 没有能证明 DDR3 已通过当前 Vivado 版本初始化和压力测试的日志。
