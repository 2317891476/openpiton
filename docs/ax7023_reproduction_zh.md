# AX7023/AX7203 Linux 启动复现说明

当前仓库实际使用的是 `a7203x` 原型验证目标和 AX7203 板级文件。如果实验记录里把板卡写作 AX7023，请先确认 FPGA 型号、DDR3 连线、SD 卡连线、UART 引脚以及 XDC 约束是否与仓库里的 `a7203x` 目标一致。

## 硬件准备

- FPGA 板卡：兼容 `a7203x` 目标的 ALINX AX7203 板卡。
- 串口终端：115200 波特率，8 位数据位，无校验，1 位停止位，关闭流控。
- 启动介质：包含 OpenPiton/Ariane Linux 镜像和测试程序的 SD 卡。
- JTAG：Vivado Hardware Manager 能够识别并烧录 FPGA。

SD 卡应包含 Linux 启动镜像，并且 Linux 启动后能看到第二个分区 `/dev/piton_sd2`。下面的示例假设 `/dev/piton_sd2` 中已经放好了 `hello` 和 `XSBench`。

## 构建 Bitstream

在仓库根目录执行：

```bash
export PITON_ROOT=/home/illya/openpiton
source $PITON_ROOT/piton/piton_settings.bash
export PITON_SKIP_ARIANE_FW_BUILD=1
cd $PITON_ROOT/build
protosyn -b a7203x -d system --core=ariane --uart-dmw ddr
```

生成的 bitstream 路径为：

```text
build/a7203x/system/a7203x_system.runs/impl_1/system.bit
```

实现结束后，检查 timing 是否通过，并确认 PLIC register map 没有端口宽度不匹配告警：

```bash
rg -n "All user specified timing constraints are met|WNS|WHS" \
  build/a7203x/system/a7203x_system.runs/impl_1/system_timing_summary_routed.rpt

rg -n "plic_regs|width .*port" \
  build/a7203x/system/a7203x_system.runs/synth_1/runme.log
```

对于 2-source PLIC register map，`plic_regs` 中 `req_i[wdata]` 高位未使用的告警是正常的。`prio_o`、`prio_we_o`、`ie_o` 或 `cc_o` 这类端口宽度不匹配告警不应出现。

## 烧录 FPGA

可以使用 Vivado Hardware Manager，也可以使用等价的 Tcl 脚本：

```tcl
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set_property PROGRAM.FILE {Z:/home/illya/openpiton/build/a7203x/system/a7203x_system.runs/impl_1/system.bit} [current_hw_device]
program_hw_devices [current_hw_device]
close_hw_manager
```

烧录成功时应看到：

```text
End of startup status: HIGH
```

## 启动 Linux

在烧录 FPGA 前或烧录完成后立刻打开串口终端。串口参数为：

```text
115200 8N1, no flow control
```

正常启动时应能看到以下关键输出：

```text
OpenPiton+Ariane Platform
sd initialized!
bbl loader
Linux version 5.1.0-rc7
plic: mapped 2 interrupts with 1 handlers for 2 contexts.
fff0c2c000.uart: ttyS0 at MMIO 0xfff0c2c000 (irq = 1, base_baud = 1875000) is a 16550
Starting logging: OK
Starting sshd: OK
Welcome to Buildroot
buildroot login:
```

除非 SD 镜像被改过账号配置，否则使用 `root` 登录。

## 运行 SD 卡测试程序

把 SD 卡插回 FPGA 板卡，启动 Linux，等串口终端出现 Buildroot 登录提示。登录后在串口终端执行：

```sh
mount /dev/piton_sd2 /mnt
/mnt/hello
/mnt/XSBench -s small -l 100
```

`XSBench` 使用 `-s small` 来减小问题规模。首次验证建议使用 `-l 100` 限制查找次数，因为当前是单核 50 MHz，运行速度会很慢。确认小规模能跑通后，再执行较长的测试：

```sh
/mnt/XSBench -s small -l 1000
```

如果 `/mnt/hello` 无法执行，先检查文件是否存在以及是否有执行权限：

```sh
ls -l /mnt
chmod +x /mnt/hello /mnt/XSBench
```

如果挂载失败，检查内核是否识别到 SD 控制器和分区：

```sh
dmesg | grep -i piton_sd
ls -l /dev/piton_sd*
```

## 已验证的正常启动点

当前已验证的流程能到达：

```text
Starting logging: OK
Starting sshd: OK
NFS preparation skipped, OK
Welcome to Buildroot
buildroot login:
```

已验证的 PLIC 配置是 2-source register map，文件路径为：

```text
piton/design/chip/tile/ariane/corev_apu/rv_plic/rtl/plic_regmap.sv
```

如果 Linux 能跑到 `/init`，但后续不再打印 `Starting logging: OK` 或 `Welcome to Buildroot`，需要重新检查综合时使用的 PLIC register map 是否与 OpenPiton/Ariane 实例中的 `NumSources=2` 匹配。

## 常见问题

- 没有任何串口输出：确认串口终端连接到板卡 USB-UART，参数为 115200 8N1，关闭流控，并确认没有其他程序占用 COM 口。
- 启动停在 user-space 的 random 或 ssh 相关信息附近：检查 Vivado 综合日志中是否存在 PLIC `plic_regs` 端口宽度不匹配告警。
- 旧 bitstream 能启动，但重新构建的 bitstream 不能启动：对比 `system.bit` 的 SHA256，并确认源码中使用的是 2-source `plic_regmap.sv`。
- `XSBench` 看起来像卡住：先用 `-s small -l 100` 做小规模验证；单核 50 MHz 构建在更大的 lookup 次数下会运行很久。
