# Vivado xsim 流程

`xvlog`、`xelab`、`xsim` 是 Vivado `bin` 目录下的独立程序，不能作为 `vivado -mode batch` Tcl 命令调用。

## Windows 本地 staging

WSL 脚本将 RTL、testbench、镜像复制到 Windows 本地临时目录。PowerShell 负责从 `VivadoBat` 参数通过 `Split-Path` 推导 `bin`，避免 WSL 反斜杠路径误解析。

## 标准步骤

```text
xvlog --nolog <rtl> <tb>
xelab --nolog --debug typical --snapshot tb_snap <tb_top>
xsim --nolog --runall --log sim.log tb_snap
```

仿真必须以 `$finish` 结束，并在日志中写出 `SIM PASS`。退出码为 0 不能单独证明 assertion 通过。

## 测试台规则

- 对同步 reset 在时钟边沿实际施加并释放。
- 初始化 128 位 bundle 时，slot 0 放在最低 32 位。
- 长消息 task 使用至少 512 位输入。
- 每个测试设置 timeout、seed、版本和期望结果。
