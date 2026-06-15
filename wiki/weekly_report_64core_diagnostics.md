# 移植与多核扩展技术周报：64核系统扩展与硬件调试阶段性进展 (6月9日 - 6月15日)

本报告汇总了从 **6月9日（上周二）至 6月15日（本周一）** 期间，在 **HuaPro P3 (Versal VP1902)** 评估板上移植 **OpenPiton + Ariane (CVA6)** 平台的单周调试进展。本周我们的核心任务是向 **64核（8x8 Mesh）超大系统** 发起攻坚，主要工作涵盖了 Build 67 双核收尾验证、64核系统实现与低级诊断（Build 68-69）、编译源文件闭合（Build 70-71），以及在硬件调试阶段对 JTAG-XVC 链路高延迟下载瓶颈的突破。

---

## 一、 本周核心调试里程碑

本周我们围绕 64核系统的物理实现、总线与外设诊断，以及调试流程优化，完成了以下关键工作：

```mermaid
gantt
    title P3 64核扩展与调试进度 (6月9日 - 6月15日)
    dateFormat  YYYY-MM-DD
    section 双核收尾与64核启动
    Build 67: 2x1多核Linux交接与DTB中断树验证 :active, 2026-06-09, 2026-06-11
    Build 68: 首个64核(8x8)OpenSBI/Linux大系统综合与布线 :crit, 2026-06-12, 2026-06-12
    section 64核诊断与源闭合
    Build 69: 64核低级诊断映像上板,ILA定位DDR正常但SD读错 :active, 2026-06-13, 2026-06-13
    Build 70: 64核UART优先诊断映像,因未跟踪源文件导致综合失败 :crit, 2026-06-13, 2026-06-13
    Build 71: SPI-SD源闭合与大PDI烧录,DONE成功拉高并实现引导 :active, 2026-06-13, 2026-06-14
    section 物理烧录与软件诊断
    烧录看门狗配置与XVC链路调试: 确立90min烧录期并完成Bootrom阶段验证 :crit, 2026-06-14, 2026-06-15
```

---

## 二、 Build 迭代历程及问题解决详述

### 1. Build 67 (2x1 多核 Linux 交接与 DTB 中断树验证)
* **遇到问题**：
  * 系统上电引导后，控制台串口打印在 BBL 设备树（DTB）输出后停滞，伴随高位乱码。且由于初期使用了单核 SD 镜像，内核无法识别 CPU1。
  * 写入正确的 2x1 镜像后，多核启动仍发生挂起或极其缓慢，串口日志卡在 SunRPC 注册或 Linux 引导初始化阶段。
* **排查与解决过程**：
  * **诊断工具设计**：生成了软件级诊断映像对交接边界进行探测：
    1. **屏蔽 CPU1 验证 (`nosmp` 映像)**：在 DTB 中将 `cpu@1` 标为 `status = "masked"` 并传入 `maxcpus=1 nosmp`。启动依然卡死在 BBL `mret` 交接处，说明并非单纯的 Linux 唤醒 secondary hart 冲突。
    2. **跳转节点打桩 (`bbl_markers` 映像)**：在 BBL 中插入关键执行点标记（如 BBL `mret` 前后寄存器状态），确认 BBL 成功选择 hart0、准备好 DTB，并执行了进入 Linux 的 `mret` 指令。
    3. **消除串口二次配置 (`keep_divisor` 映像)**：移除 earlycon 的显式波特率重写。控制台乱码被清除，得以完整输出 `smp: Brought up 1 node, 2 CPUs`。
    4. **中断与定时器诊断 (`sbi_trace` / `keep_bootcon` / `mtip_state` 映像)**：保留 bootcon 控制台和 initcall 详细调试信息。分析发现 Linux 在 hart0 上正常拉起进程，但 CPU1（hart1）在运行期间产生大量 RCU 前向进度停滞警告，表明 CLINT 产生的中断未被 CPU1 正确处理或清除。
  * **最终结论**：Build 67 证实了 2x1 多核大体设计（DDR、外设总线、UART）通路在硬件上的可行性，将后续多核软件死锁、中断机制问题界定为软件调试范畴，具备向 64 核（8x8 Mesh）进一步扩展的基础。

### 2. Build 68 (首个 64核/8x8 OpenSBI 与 Linux 6.6 综合工程)
* **遇到问题**：
  * **环境缺项**：远程离线 Ubuntu 编译主机上缺失 `riscv64-unknown-elf-gcc` 工具链及 C 标准库头文件（picolibc），且缺少 OOC 综合阶段 debug IP 许可证，导致编译启动即告中止。
  * **源码包缺失**：`riscv_peripherals.sv` 必须同时例化 `bootrom` 与 `bootrom_linux`（通过 `ariane_boot_sel_i` 选择），但远程打包仅生成了 OpenSBI 模式的 `bootrom_linux.sv`，使得 baremetal `bootrom` 丢失。
  * **下载挂起**：虽然通过布线并生成了 238MB 的大容量 PDI，但在板端进行 JTAG-XVC 烧录时，下载进度在 30 分钟内未见推进，`DONE` 信号未置高。
* **排查与解决过程**：
  * **环境与依赖闭合**：在离线编译主机上安装了 Ubuntu 官方 Jammy 工具包，并通过 `P3_BOOTROM_EXTRA_CFLAGS` 引入 picolibc 头文件目录，同时导入了 Xilinx Vivado OOC 编译许可证。
  * **脚本修正**：重构了 `p3_rebuild_build68_8x8_opensbi_linux.sh`，生成一个临时最小化 DTS 以自动编译生成 baremetal `bootrom.sv` 以满足例化要求。
  * **调试路线微调**：由于 238MB 大文件烧录极易卡在下载层，我们需要一个体积相同但具备诊断阶段汇报功能的 Bootrom，因此快速迭代了 Build 69（低级诊断映像）。

### 3. Build 69 (64核低级汇编/C级引导诊断)
* **遇到问题**：
  * 映像烧录成功，DONE 信号正常拉高，但在 UART 控制台上未输出任何预期的低级汇编字符（如 `B69 ASM` 标记或 DDR 初始化信息）。
* **排查与解决过程**：
  * **ILA 总线捕获**：连接 Windows Vivado 客户端，读取 debug hub 并捕获 4 组 ILA：
    1. 捕获显示 `sys_rst_n` 与处理器解复位信号均已正常置高，证明核心已出复位并正常取指。
    2. DDR4 地址段的总线事务握手成功，返回 `OKAY`，证明大系统中的 DDR4 折叠与访问控制器正常运作。
    3. Wishbone 总线探测到 SPI-SD 控制器读数据失败，事务寄存器返回读卡错误标志 `p3_dbg_uart_seen16=0x5bd3`，说明 SD 接口存在交互异常。
    4. AXI16550 UART 控制器的写操作未反映在 TX 引脚的翻转上。
    5. CDC 时序分析中发现有 4 个 debug 专属跨时钟域 Hold 违规（由 raw `sd_clk_out` 引入 ILA 所致）。
  * **最终结论**：硬件总线与 DDR4 控制器无物理损坏，但暴露了 SD 读卡异常以及 UART 写信号未到引脚的故障。下一步需要精简 ILA 信号，针对 UART 写数据寄存器及 SPI-SD 交互标志做直接捕获。

### 4. Build 70 (UART优先及 SD ILA 时序诊断)
* **遇到问题**：
  * 针对 Build 69 的跨时钟域问题，修正了 SD 调试标志采样（使用同步采样段加上 `ASYNC_REG` 约束并对第一级输入假路径），以期消除 Hold 违规。但在 Vivado 综合时，工程报主 elaborated 阶段缺失错误：`Synth 8-439: module 'piton_spi_sd_top' not found`。
* **排查与解决过程**：
  * **snapshot 机制失效定位**：由于使用了源码自包含模式（`P3_SELF_CONTAINED_SOURCES=1`），在工程创建前 Vivado 脚本会基于 `git archive` 提取 tracked 文件至 `source_snapshot` 目录。然而，新增的 [piton_spi_sd_top.v](file:///L:/home/illya/openpiton/piton/design/chipset/noc_sd_bridge/rtl/piton_spi_sd_top.v) 和 [init_sd_p3.v](file:///L:/home/illya/openpiton/piton/design/chipset/axi_sd_bridge/rtl/init_sd_p3.v) 在本地属于 untracked（未跟踪）状态，导致在打包时被排除，远程主机最终编译缺失。
  * **最终结论**：必须强制所有关键源文件被 git 跟踪，同时在创建工程脚本中加入前置预检逻辑。

### 5. Build 71 (源码自包含闭合与 XVC 传输机制突破)
* **遇到问题**：
  * 成功将缺失源码提交并执行了预检，Build 71 顺利完成了全部综合、布线和 timing 闭合（0 timing errors, `WNS=5.094 ns`, `WHS=0.010 ns`）。
  * 但在上板下载时，Windows 完整 Vivado 烧录进度卡在 `program_hw_devices` 长达 30 分钟。随后，进行手动取消下载，导致硬件管理器内部的 PMC/DPC 寄存器进入不完整配置的悬空状态，此后再执行 enumeration 会持续报错 `No devices detected`。
* **排查与解决过程**：
  * **物理层恢复**：对 P3 Pro 评估板进行完整的断电物理冷启动，清空 PMC/DPC 芯片的状态锁死。
  * **烧录超时机制配置**：我们修改了自动化监控脚本的看门狗阈值（延长至 90 分钟）并设置 persistent monitor。重新通过 JTAG-XVC 运行烧录，在经历 ~35 分钟的漫长数据传送后，**DONE 信号成功拉高，Device Programmed 成功**！
  * **高延迟本质定位**：通过对 Tailscale 网络上的 XVC 链路抓包以及 `open_hw_target` 握手测试，发现高延迟的根本原因是 Tailscale 转发下 XVC 的单次 transaction（事务）延迟极高（单次 target 打开动作耗时 40~44s）。在 238MB 这种 Versal 级大型 PDI 的大颗粒度传输中，高频次的 JTAG 握手包累计产生的正常传输时间便需要 30 分钟以上，因此之前的“卡死”实为“高延迟慢速下载”，并非硬件连接挂起。
  * **板端运行诊断**：DONE 拉高后，UART 成功输出端到端日志：`B69 ASM` → `B69 OpenSBI bundle diag bootrom` → `B69 DDR OK` → `B69 SD init OK` → `B69 SD read GPT header` -> `B69 read bundle header`。之后读取 bundle 头魔数时打印了 `0x3401117332C0006F`，触发了 **`B69 ERROR bad header`** 错误并停机。
  * **根因定位**：魔数不匹配的原因是 SD 卡的第一个扇区（LBA 0x800 起始处）目前装载的是旧的 BBL 标志映像，未写入符合 OpenSBI 结构的 `P3OS` 和 `BI64` 引导魔数组合。
  * **解决办法**：硬件链路、DDR4 寻址、SPI-SD 通道、GPT 分区解析已全部打通，问题收敛为软件级的 SD 卡 Image 烧录镜像内容差异。

---

## 三、 64核硬件调试与流程固化的开发规则

为了规范后续 64核大规模硬件调试流程，减少因环境/链路因素带来的误判，我们在开发规则中明确了以下约束：

1. **源码 snapshot 与 Git 跟踪预检**：
   * 所有新增/修改 of RTL 级源文件或桥接模块，**必须**在运行远程 Vivado 编译脚本前进行 git commit 或 staged 跟踪，严禁处于 untracked 状态。
   * 必须在 `scripts/p3_remote_vivado_64core.sh` 中调用前置检测脚本，凡检测到有 dirty 状态或未跟踪源码的模块直接拒绝打包。
2. **大容量 PDI 烧录看门狗策略**：
   * Versal 级别的 238MB PDI 下载文件庞大，而 Tailscale 连接的 XVC 存在单次 transaction 约 40ms 的固有网络往返高延时。
   * 烧录看门狗（Watchdog）必须设置为 90 分钟以上，并采用 persistent 模式的监视进程以防被自动判定为“死锁挂起”而提前中止。
   * 若发生烧录意外中止，必须对 board 执行完全物理断电重启以恢复 PMC/DPC 寄存器的配置链，禁止直接带状态重烧。
3. **并行编译核数配置**：
   * 离线 Ubuntu 编译服务器（384 线程，1.5TB 内存）的作业并行度统一默认配置为 `JOBS=32`，主进程并发度为 32。
   * 为了避开部分 IP 生成的时序/布线依赖性 Vivado Bug，顶层 synthesis 完成后的 child-IP 编译步骤应继续强制执行单核串行化，保持编译稳定性。

---

## 四、 下阶段工作与验证计划

随著 Build 71 在硬件上完成对 DDR4、SPI-SD 及 GPT 分区寻址逻辑的闭合，下阶段的工作将重点转移至软件及镜像烧写：

1. **SD 卡物理移动与写入**：
   * 解决板卡 Linux 系统下读写 reader 0 字节的问题，将 SD 卡移动到物理 USB 读卡器中。
   * 使用 `dd` 写入本地生成的 `build/huaprop3/opensbi64/p3_opensbi_linux_64hart.img`，确保带有正确的 `P3OSBI64` 魔数（`magic0=0x534f3350` "P3OS", `magic1=0x34364942` "BI64"）。
2. **多核 OpenSBI & Linux 引导阶段观察**：
   * 重设 JTAG-XVC 烧录后，启动串口 `/dev/ttyUSB0` 长期捕获。
   * 观察 Bootrom 是否能通过 Magic 校验，正确从 SD 卡将 OpenSBI (`fw_jump.bin`)、Linux (`Image`)、DTB 及 initramfs 拷贝至 DDR4 的对应预设地址。
   * 验证 CPU0（hart0）完成拷贝后释放其余 63 个 hart 并共同进入 OpenSBI。
3. **Linux 多核启动验证**：
   * 确认 Linux 控制台打印 `SMP: Total of 64 processors activated` 及 `/bin/sh` 成功拉起。
   * 运行 `/proc/cpuinfo` / `nproc` 确认 64 个 CPU 均在线。
