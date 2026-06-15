# 移植与多核扩展技术周报：64核系统扩展与硬件调试工具链突破 (6月9日 - 6月15日)

本报告汇总了从 **6月9日（上周二）至 6月15日（本周一）** 期间，在 **HuaPro P3 (Versal VP1902)** 评估板上移植 **OpenPiton + Ariane (CVA6)** 平台的单周调试进展。本周我们的核心任务是向 **64核（8x8 Mesh）超大系统** 发起攻坚，主要工作涵盖了 64核诊断映像的建立与上板分析（Build 68-69）、编译源文件闭合（Build 70-71），以及在硬件调试阶段对 Versal XVC JTAG 工具链重大兼容性 Bug 的定位与解决。

---

## 一、 本周核心调试里程碑

本周我们围绕 64核系统的物理实现、总线与外设诊断，以及调试工具链的优化，完成了以下关键工作：

```mermaid
gantt
    title P3 64核扩展与工具链调试进度 (6月9日 - 6月15日)
    dateFormat  YYYY-MM-DD
    section 双核收尾与64核启动
    Build 67: 2x1多核Linux交接与DTB中断树验证 :active, 2026-06-09, 2026-06-11
    Build 68: 首个64核(8x8)OpenSBI/Linux大系统综合与布线 :crit, 2026-06-12, 2026-06-12
    section 64核诊断与源闭合
    Build 69: 64核低级诊断映像上板,ILA定位DDR正常但SD读错 :active, 2026-06-13, 2026-06-13
    Build 70: 64核UART优先诊断映像,因未跟踪源文件导致综合失败 :crit, 2026-06-13, 2026-06-13
    Build 71: SPI-SD源文件完全闭合,64核诊断映像顺利通过布线 :active, 2026-06-13, 2026-06-14
    section 工具链Bug攻克
    工具链交叉测试: 规避Vivado Lab兼容性错误,打通P3稳定枚举 :crit, 2026-06-14, 2026-06-15
```

---

## 二、 本周技术突破与根本原因剖析

### 1. Build 69 ILA 诊断分析：确证核心/DDR 状态，暴露 SD/UART 瓶颈
* **调试背景**：Build 68（64核 OpenSBI/Linux 目标）在烧录时因 JTAG 链路问题未获取 `DONE` 信号，UART 保持沉默。我们在 Build 69 降级为低级汇编诊断映像（`BOOTROM_MODE=opensbi_bundle_diag`）以定位极早期停点。
* **ILA 捕获结论**：
  1. **核心已解除复位**：系统上板 Done 信号正常，NOC/Core 历史总线活跃，CPU 正在执行正常的取指与数据请求。
  2. **DDR4 访问完全正常**：ILA 捕获到 DDR 写与读（AR/R）握手全部通过并返回 `OKAY` 响应，证明 64核大系统的 DDR 地址折叠机制与 MIG 初始化没有物理故障。
  3. **SD 与 UART 异常**：SPI-SD 控制器发起了读卡请求，但 Wishbone 事务管理器上报了**读错误标志**（`p3_dbg_uart_seen16=0x5bd3`），且卡座无任何数据返回；UART 写入流在 AXI16550 处未触发 TX 翻转。
* **结论**：系统逻辑已顺利越过复位与 DDR 初始化，但停留在 SD 引导 Payload 拷贝和早期 UART 写操作阶段。

### 2. Build 70 综合失败原因定位：未跟踪源文件导致 snapshot 编译缺失
* **故障表现**：Build 70 试图增强 UART 写通道和 SPI-SD 状态的监控，但在 RTL 综合阶段直接报错：`Synth 8-439: module 'piton_spi_sd_top' not found`。
* **原因剖析**：由于项目实行严格的自包含源码快照重构（`P3_SELF_CONTAINED_SOURCES=1`），在创建 Vivado 工程前会将所有源文件复制到 `p3b70/source_snapshot` 中。但新设计的 [piton_spi_sd_top.v](file:///L:/home/illya/openpiton/piton/design/chipset/noc_sd_bridge/rtl/piton_spi_sd_top.v) 和 [init_sd_p3.v](file:///L:/home/illya/openpiton/piton/design/chipset/axi_sd_bridge/rtl/init_sd_p3.v) 在本地为未跟踪文件（`untracked`）。在调用 `git archive` 打包源码并传输到离线 Ubuntu 编译服务器时，这些文件被过滤掉，导致远程编译工程缺失关键模块。
* **解决办法**：在 Build 71 脚本中增加前置 Preflight 校验，确保所有新增源文件及其在 [rtl_setup.tcl](file:///L:/home/illya/openpiton/piton/tools/src/proto/common/rtl_setup.tcl) 中的注册全部被 git 跟踪并闭合。Build 71 顺利通过综合、布局与布线。

### 3. 重大工具链突破：规避 Vivado Lab 兼容性 Bug，推断“必须断电”为假阴性
* **故障表现**：Build 71 映像生成后，在板端 Ubuntu 上运行 Vivado Lab 2024.2 进行烧录时，连接 `hw_server` 和 XVC 均正常，也能读取物理 IDCODE，但在目标注册阶段直接报错：`No devices detected` / `No core debug access`。此前认为只能通过断电或 EPIC 控制器重启来恢复。
* **交叉验证结论**：
  * 我们排查了进程占用，并在单 `hw_server` 监听下重试，Lab 仍报错。
  * 随后改用 **Windows 完整版 Vivado v2024.2.2** 连接相同的远程 `hw_server` 和 XVC 节点，**立刻成功枚举**出 `arm_dap_0` 和 `xcvp1902_1`。
* **原因剖析**：板端 Vivado Lab Edition 2024.2 的 Versal DPC/PMC 调试器件识别逻辑，在此 VP1902 XVC 链路下存在严重的兼容性缺陷，导致无法将其注册为硬件调试目标；而 Windows 完整的 Vivado 客户端规避或修复了此问题。
* **结论**：**“Lab 识别不到需要板卡断电”的结论被推翻**。板卡、XVC 及 `hw_server` 均为正常状态，问题纯属客户端软件形态差异。

---

## 三、 64核硬件调试固化的开发规则

为了避免后续工具链误判，我们在 [CLAUDE.md](file:///L:/home/illya/openpiton/CLAUDE.md) 和 [AGENTS.md](file:///L:/home/illya/openpiton/AGENTS.md) 中正式提交并固化了硬件操作规则（提交哈希：`ca5f83f`）：

1. **板端 Ubuntu 宿主机 (`illya@100.93.77.36`)**：
   * 仅用于运行后台 `hw_server`（监听 3121 端口）和 `/dev/ttyUSB0` 串口捕获；
   * **严禁**使用其 Vivado Lab 客户端的硬件管理器作为最终器件存取状态的依据。
2. **本地 Windows 主机**：
   * 运行 **完整版 Vivado v2024.2.2** 客户端；
   * 通过 TCP 远程添加 XVC `202.197.4.99:2540`，并在该客户端上执行设备枚举、PDI 下载和 ILA 窗口监视。

---

## 四、 下阶段工作与验证计划

Build 71 已经在离线编译主机上完成了全部布线和哈希校验，PDI/LTX 映像已完整传输到本地。我们将启动实际的 64核 UART/SD 联合物理层诊断：

1. **开启一小时以上 UART 串口备份捕获**：
   在板端 Ubuntu 上针对 `/dev/ttyUSB0` 启动长效捕获任务，以防漏掉 Bootrom 极早期的汇编级字符打印。
2. **使用 Windows Vivado 2024.2.2 进行烧录**：
   在已打开且连接正常的 JTAG 会话中，向 `xcvp1902_1` 写入 [p3_top_build71_8x8_uart_sd_source_closure.pdi](file:///L:/home/illya/openpiton/huaprop3_build71_8x8_uart_sd_source_closure/debug_build/p3_top_build71_8x8_uart_sd_source_closure.pdi)。
3. **定位死锁点**：
   * 若串口打印出 `B69 ASM` 宏或 DDR 初始化信息，说明总线桥和核心成功越过早期阶段，将根据 SD 诊断状态判断是否是 SDHC 卡座供电/协议死锁。
   * 若依然完全无输出，则通过 `P3_BD_UART_SD_DIAG_ILA` 的 4 个 ILA 捕获 AXI-Lite 读写周期，判断 CPU 指令向 UART IP 发送的写数据在桥接层是否发生了握手死锁。
