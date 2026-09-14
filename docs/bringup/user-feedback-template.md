# 用户硬件反馈记录模板

每次下载或上电测试后，由用户填写并与对应 Git commit 绑定。

```text
日期/时间:
Git commit:
Bitstream:
板卡序列号:

JTAG 可识别:        yes / no
配置完成:           yes / no
LED 状态/频率:
UART 端口/波特率:
UART 原始日志:

VIO probe 值:
JTAG-AXI BRAM 写值:
JTAG-AXI BRAM 读值:
DDR3 初始化:        pass / fail / unknown
DDR3 压力测试:      pass / fail / not-run
PCIe warm reboot 枚举: pass / fail / not-run

异常现象:
复现步骤:
附件路径:
用户结论:            pass / fail / needs-investigation
```
