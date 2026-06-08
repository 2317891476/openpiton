# 移植与多核扩展技术周报：单核 Linux 调通与 2x1 多核扩展验证 (6月2日 - 6月8日)

本报告汇总了从 **6月2日（周二）至 6月8日（本周一）** 期间，在 **HuaPro P3 (Versal VP1902)** 评估板上移植 **OpenPiton + Ariane (CVA6)** 平台的单周调试进展。本周我们完成了从“物理通路验证”到“单核 Linux 交互 shell 成功运行”，再到“双核（2x1）启动挂接”的阶段性目标。

---

## 一、 本周核心调试里程碑

本周调试流程全面转向 SPI-mode SD 协议，通过攻克 Versal 硬件三态限制，成功闭环了单核 Linux 系统，并完成了双核（2x1）系统的布线与上板测试：

```mermaid
gantt
    title P3 移植与多核扩展进度 (6月2日 - 6月8日)
    dateFormat  YYYY-MM-DD
    section SPI 物理层
    Build 57-61: 移植SPI-SD控制器,修正MOSI空闲电平,确认CMD0发出 :active, 2026-06-02, 2026-06-03
    section Full-shell 闭环
    Build 62-63: 攻克Versal AVAL-352 DRC限制,引入显式IOBUF :crit, 2026-06-03, 2026-06-03
    Build 64-65: 调通SPI-SD初始化与AXI Block-Read数据传输 :active, 2026-06-03, 2026-06-03
    Build 66: 单核正常引导BBL+Linux 5.1,交互式Shell与XSBench运行 :crit, 2026-06-04, 2026-06-05
    section 2x1 多核扩展
    Build 67: 2x1双核系统综合实现,双核BBL引导成功,进行Linux跳转调试 :active, 2026-06-05, 2026-06-08
```

---

## 二、 本周技术突破与根本原因剖析

### 1. Versal 顶层三态限制与显式 IOBUF 引入 (Build 62 - Build 63)
* **故障表现**：在 Full-shell 下整合 SPI-mode 时，Vivado Bitgen 报错中止，触发 DRC 校验 **AVAL-352** 违规。
* **原因剖析**：Versal 架构禁止对顶层的 `inout` 双向引脚（如 `sd_cmd` 和 `sd_dat`）进行隐式的三态推断（如直接赋值 `assign port = oe ? out : 1'bz`）。Vivado 自动推断出的 `OBUFT` 三态驱动器在 Versal 上是不合法的。
* **修复方法**：在 [piton_spi_sd_top.v](file:///L:/home/illya/openpiton/piton/design/chipset/noc_sd_bridge/rtl/piton_spi_sd_top.v) 中移除隐式三态，为双向端口**显式实例化 IOBUF 原语**：
  ```verilog
  IOBUF sd_cmd_iobuf (
      .O  (sd_cmd_i),
      .IO (sd_cmd),
      .I  (sd_cmd_o),
      .T  (~sd_cmd_oe)
  );
  ```
  显式例化后，Build 63 顺利通过 Bitgen 并验证了物理连接。

### 2. SPI-SD 协议栈初始化与 AXI 传输打通 (Build 64 - Build 65)
* **调试进展**：在引入显式 IOBUF 后，我们恢复了 OpenCores SPI 控制器通路并调通了数据传输：
  1. **初始化连通 (Build 64)**：SPI 模式下的 SDHC 初始化序列（`CMD0 -> CMD8 -> CMD55 -> ACMD41`）全部顺利通过，`init_sd_p3` 状态机拉高 `INIT_DONE`。
  2. **Block-Read 闭环 (Build 65)**：验证了 AXI 缓存缺失、Wishbone 事务启动、RX FIFO 拷贝及向 NoC 返回非零物理数据的完整闭环，证明 SD 卡物理读写在 SoC 层面完全可用。

### 3. 多核 (2x1) 扩展一致性与中断树设计 (Build 67)
* **调试进展**：本周我们正式向双核（2x1 Mesh）扩展发起攻关：
  1. **PyHP 一致性校验**：重构了多核参数生成逻辑，确保 `define.tmp.h`、`chip.tmp.v`、`flat_id_to_xy.tmp.v` 等 tile 相关文件在编译前自动对齐，规避了 Vivado  sizing 外部 CLINT/PLIC 向量时发生的宽度 mismatch Elaborate 报错。
  2. **中断树对齐**：在 BBL 设备树（DTB）中，完成了双核（`cpu@0` 和 `cpu@1`）的中断级联树和 CLINT/PLIC 映射。

---

## 三、 单核 Linux 启动基线建立 (Build 66)

本周我们基于自包含源码重构（`P3_SELF_CONTAINED_SOURCES=1`）成功建立了单核（1x1）的 Linux 启动基线工程：

* **基线状态**：板载运行时成功执行 Bootrom $\rightarrow$ SPI SD 自动拷贝 65,536 块 Payload 至 DDR4 $\rightarrow$ 校验通过 $\rightarrow$ 进入 BBL $\rightarrow$ 启动 Linux 5.1.0-rc7 内核。
* **控制台交互**：通过 picocom 以 `115200 8N1` 成功连接交互式 `/bin/sh` shell，响应了慢速串口输入（约 200 ms 延迟）。
* **挂载与跑分**：成功以只读模式挂载了 ext2 跑分分区（`/dev/piton_sd2`），成功启动了 `/mnt/XSBench -s small -p 1 -l 1` 并获取跑分输出。

---

## 四、 当前挂起点分析：BBL 到 Linux 固件交接流 (Firmware Handoff Flow)

目前 Build 67 双核系统在 BBL 打印设备树（DTB）后，串口仅输出少量高位乱码字节流并挂死。我们必须明确，BBL 跳转到 Linux 并非一步到位，中间有一段极为关键的固件交接与早期引导流程。基于当前的底层代码与编译路径，其实际调用链如下：

1. **BBL 初始化阶段**
   主核心调用 `init_first_hart()`，完成 UART 串口、内存（DDR）、当前 hart 状态、CLINT 和 PLIC 的基本配置与 chosen 节点查询，然后调用 `wake_harts()` 发送软件中断（IPI）唤醒其它 hart（参考：`build/huaprop3/ariane-sdk/build-bbl-debug-axi16550-force/minit.c:161`）。
2. **BBL 设备树（DTB）处理**
   `boot_loader()` 负责将编译好的设备树复制到 Payload 后面 2MB 对齐的位置（通常为 `0x81000000` 附近），并在此过程中过滤掉由 BBL 自身接管 of 节点（如 CLINT、debug 等）。如果使能了 `PK_PRINT_DEVICE_TREE`，则在此处通过串口打印出当前捕获的完整 DTB（参考：`build/a7203x/ariane-sdk/riscv-pk/bbl/bbl.c:68`）。
3. **BBL 选择 Linux 入口地址**
   由于未指定外部 `kernel_start`，BBL 将入口地址默认指向内嵌的 Payload 头部：
   `entry_point = &_payload_start`
   根据当前的 BBL ELF 符号表，`.payload` 物理起始地址为 `0x80200000`。
4. **BBL 切换至 S-mode（Supervisor 模式）**
   主核心执行 `enter_supervisor_mode()`，处理以下关键寄存器与状态切换：
   * 配置物理内存保护（PMP），放开 S-mode 对全内存的访问权限；
   * 设置 `mstatus.MPP = S`（指定下一级特权态为 S-mode）；
   * 设置 `mepc = 0x80200000`（指向 Linux 启动入口点）；
   * 设定寄存器 `a0 = hartid`（传递当前启动 hart id）；
   * 设定寄存器 `a1 = dtb_output`（传递已复制好的 DTB 基地址，约为 `0x81000000`）；
   * 执行 `mret` 指令，硬件跳转至 `mepc`（参考：`build/huaprop3/ariane-sdk/build-bbl-debug-axi16550-force/minit.c:211`）。
5. **Linux 早期引导与控制台初始化**
   Linux 内核从 `0x80200000` 的 `head.S` 汇编入口点开始执行：
   * 暂存 `a0` (hartid) 与 `a1` (DTB 物理地址)；
   * 区分主启动核心（Boot Hart）与辅助核心（Secondary Hart）；
   * 构建早期临时页表并开启 MMU（配置 `satp` 寄存器）；
   * 解析设备树中的 bootargs 与 chosen 配置；
   * 初始化 `earlycon`（早期控制台驱动）；
   * 打印第一行标志性信息：`Linux version ...`；
   * 进一步初始化 timer、irq、PLIC、内核子系统并根据 `bootargs` 进入 `/bin/sh`。

**停点定位分析**：目前终端能够完整输出 BBL 设备树，但在进入 Linux 后没有任何 `Linux version` 的控制台输出。这表明**系统死锁点大概率位于 BBL 执行 `mret` 之后、至 Linux `earlycon` 成功输出第一行打印前的极早期初始化区间（或该区间附近）**。

---

## 五、 本周多核启动的最可疑根因分析

针对上述停点特征，我们梳理出以下四项最高嫌疑的根因：

### 1. Hart 1 / SMP 交接与同步问题（最高优先级）
在 Build 67 的双核配置下，设备树同时暴露了 `cpu@0` 和 `cpu@1`，BBL 会通过软中断唤醒 `hart 1` 并让两个 hart 同时进入 Linux 空间。
* **死锁机理**：如果 Linux 5.1 内核中的 SMP 启动协议（SMP Boot Protocol）、BBL 实现的 SBI 服务、CLINT 的核间中断（IPI）机制，或者 `hart 1` 物理上的复位/时钟/缓存相干性（Coherence）有任何微小的 Mismatch，都会在 Linux 开启页表或多核同步锁时导致内存破坏或 CPU 锁死。
* **快速验证**：通过屏蔽 `cpu@1` 降级为单核，排除多核同步的硬件和软件干扰。

### 2. Linux 早期控制台（Early Console）与 UART 初始化冲突
在 BBL 结束时，终端输出了一段少量的乱码字节流。
* **死锁机理**：由于单核 Build 66 在同一 UART 硬件上可完美工作，这排除了串口 IP 本身的物理链路故障。乱码极有可能是 Linux 早期驱动开始尝试接管并初始化 UART 寄存器时，由于核间竞争或 divisor 寄存器配置冲突，导致输出时序被破坏，或者多核心同时并发向同一 UART 寄存器执行写操作引起总线冲突。

### 3. 设备树（DTB）与硬件 CLINT/PLIC 拓扑不匹配
在双核模式下，硬件的中断引脚和地址区间会发生改变。
* **死锁机理**：BBL 在加载时会过滤 CLINT 节点，强制让 Linux 必须通过 BBL/SBI 接口使用 timer 和 IPI 中断服务。如果设备树中 `hart 1` 的 CLINT 地址偏移量、PLIC 中断源个数或核间中断向量与 FPGA 物理网表不一致，Linux 试图查询 PLIC 中断线时就会访问非法地址触发 Exception 挂死。

### 4. 内核镜像（Payload）与双核启动协议不兼容
当前打包在 BBL 内部的 Linux 内核在 Build 66 单核下能够工作，但这并不能确保其完全具备多核运行条件。
* **死锁机理**：如果内核编译配置中未启用多核支持（如缺少 `CONFIG_SMP`）、未配置 RISC-V SBI 核心协议，或者 `8250 console` 驱动未正确编译入核，内核在遭遇双核交接时就无法正确路由 `hart 1` 的启动请求，从而导致引导异常。

---

## 六、 当前挂起点与下一步排查计划

我们建议下一步**不应重跑 Vivado 硬件综合**，因为当前 2x1 物理网表已被证明可以成功烧录且 Done 位拉高。最快的排查路径是在软件和 SD 镜像层面实施以下两个对照实验：

1. **测试单核 SMP 降级镜像 (`nosmp`)**：
   * 使用 [p3_make_build67_linux_handoff_images.sh](file:///L:/home/illya/openpiton/scripts/p3_make_build67_linux_handoff_images.sh) 编译排查镜像：保留双核硬件，但在 BBL 设备树中将 `cpu@1` 设为 `disabled`，并向 bootargs 注入 `maxcpus=1 nosmp`。
   * *分析依据*：这会使辅助核心 `hart 1` 留在 wfi 闲置循环中，仅由主核 `hart 0` 启动单核 Linux。若能启动，说明死锁位于 **SMP 多核同步层** 或中断级联映射。
2. **测试 BBL 跳转节点追踪镜像 (`bbl_markers`)**：
   * 在 BBL 的关键跳转入口、双核分配入口和执行 `mret` 进入 Linux 之前的节点插入打印标记 `B67M`，并关闭设备树信息打印以防控制台溢出。
   * *分析依据*：这可以精确定位处理器是在 BBL 内部执行 `mret` 之前死锁，还是已跳转到 Linux 空间（通常由于早期的 Page Fault 乱码导致）。

---

> [!NOTE]
> 本周报所述之三态 DRC 解决方法及 Build 57–65 的具体 RTL 改动代码，可进一步查阅 Wiki 中的专题周报：
> * 物理层连线与三态 DRC 分析：[weekly_report_sd_issue.md](file:///L:/home/illya/openpiton/wiki/weekly_report_sd_issue.md)
