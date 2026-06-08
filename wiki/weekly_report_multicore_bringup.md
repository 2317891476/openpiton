# 移植与多核扩展技术周报：单核 Linux 调通与 2x1 多核扩展验证 (5月26日 - 6月8日)

本报告汇总了自 **5月26日（上周二）至 6月8日（本周一）** 期间，在 **HuaPro P3 (Versal VP1902)** 评估板上移植 **OpenPiton + Ariane (CVA6)** 平台的全部调试进展。本双周我们攻克了系统总线死锁、DDR4 译码限制、SD 卡物理层协议不匹配、Versal 架构 DRC 限制等关键瓶颈，成功闭环了单核 Linux 启动并运行跑分程序（基线 Build 66），同时完成了双核（2x1）系统的布线与上板初步测试（Build 67）。

---

## 一、 双周核心调试里程碑

自 5月26日 以来，我们采取了递进式硬件调试与物理信号探测方法，完成了以下重要节点：

```mermaid
gantt
    title P3 移植与多核扩展进度 (5月26日 - 6月8日)
    dateFormat  YYYY-MM-DD
    section UART & DDR4
    Build 37-43: AFE流控与字对齐修复,免栈汇编UART连通 :active, 2026-05-26, 2026-05-30
    Build 44-46: NoC DDR 读通道挂起分析,地址折叠调通DDR4 :crit, 2026-05-30, 2026-05-31
    section SD卡物理层
    Build 47-52: SD-CD复位解除,CMD55超时死循环分析 :active, 2026-05-31, 2026-06-01
    Build 53-56: Standalone探针测试,发现SPI引脚交叉 :crit, 2026-06-01, 2026-06-02
    Build 57-61: 移植SPI-SD控制器,修正MOSI空闲电平 :active, 2026-06-02, 2026-06-03
    section Full-shell 闭环
    Build 62-63: 攻克Versal AVAL-352 DRC限制,引入显式IOBUF :crit, 2026-06-03, 2026-06-03
    Build 64-65: 调通SPI-SD初始化与AXI Block-Read数据传输 :active, 2026-06-03, 2026-06-03
    Build 66: 单核正常引导BBL+Linux 5.1,交互式Shell与XSBench运行 :crit, 2026-06-04, 2026-06-05
    section 2x1 多核扩展
    Build 67: 2x1双核系统综合实现,双核BBL引导成功,进行Linux跳转调试 :active, 2026-06-05, 2026-06-08
```

---

## 二、 关键技术突破与根本原因剖析

### 1. UART 控制器硬件死锁与位宽对齐修复 (Build 37 - Build 43)
* **死锁表现**：Done 指示灯拉高，但物理串口（115200 8N1）完全没有输出。
* **原因剖析**：
  1. **AFE 自动流控死锁**：驱动配置使能了自动硬件流控（MCR 寄存器 Bit 5 = 1），但子卡仅连出了 TX/RX，无 CTS/RTS 信号，串口发送状态机被拉死。
  2. **数据右移错位**：64位 NoC 桥接在读取 LSR (寄存器偏移 5) 时会对 AXI 数据右移 40 位，而 AXI IP 在 32位字对齐下把 LSR 放在 Byte 0，移位后 LSR 读回值永久为 `0x00`，使 CPU 判定串口始终 Busy。
* **修复方法**：驱动禁用 AFE；在 [uart_top.v](file:///L:/home/illya/openpiton/piton/design/chipset/io_ctrl/rtl/uart_top.v) 读通路中对 LSR 状态执行 **8通道字节复制广播映射** (`{8{core_axi_rdata[7:0]}}`)。在纯汇编镜像中成功跑通。

### 2. Versal NoC 地址译码局限与 DDR 读挂起解决 (Build 44 - Build 46)
* **死锁表现**：汇编级内存测试中，AW/W/B 通道顺利握手（写成功），但 AR 读通道请求发出后，RVALID 始终为 `0`，CPU 发生读挂死。
* **原因剖析**：Versal NoC 硬核对 AXI 端口 `S_AXI_MEM` 规定了 LOW0 地址空间限制，其只映射基址为 `0x00000000` 的 2GB 空间。而 Ariane CPU 访问物理 DDR 的基址被硬性编址在 `0x80000000`。
* **修复方法**：在顶层 [p3_top.v](file:///L:/home/illya/openpiton/piton/design/xilinx/huaprop3/p3_top.v) 中实现顶层 AXI 地址折叠翻译：
  ```verilog
  assign bd_m_axi_awaddr = m_axi_awaddr - 64'h0000000080000000;
  assign bd_m_axi_araddr = m_axi_araddr - 64'h0000000080000000;
  ```
  修改后 DDR 物理读写彻底畅通。

### 3. SD 控制器硬复位释放与引脚线序交叉纠正 (Build 49 - Build 56)
* **死锁表现**：启动停在块拷贝循环。内部探针显示 `sd_buf_noc2_ready` 恒为 0。
* **原因剖析**：
  1. **复位门控卡死**：物理引脚的 card-detect (`sd_cd`) 悬空为 `1`。由于 `rst = sys_rst | sd_cd`，导致 SD 模块被锁定在硬复位中。
  2. **Native SD 引脚错位**：评估板子卡实际可工作的链路是 **SPI-mode SD**；原 Native 模式配置误将逻辑 `sd_cmd` 和 `sd_dat[3]` 连接到错位的物理管脚，导致卡收不到 CMD。
* **修复方法**：
  1. 在 [piton_sd_top.v](file:///L:/home/illya/openpiton/piton/design/chipset/noc_sd_bridge/rtl/piton_sd_top.v) 中添加 `P3_SD_IGNORE_CARD_DETECT_RESET` 屏蔽 `sd_cd` 参与复位树。
  2. Build 56 Standalone 测试探针证实了 SPI 协议在参考引脚下的可用性。SoC 全面切换为 SPI 控制器 [piton_spi_sd_top.v](file:///L:/home/illya/openpiton/piton/design/chipset/noc_sd_bridge/rtl/piton_spi_sd_top.v)。

### 4. Versal Bitgen DRC AVAL-352 规避与 IOBUF 显式实例化 (Build 62 - Build 65)
* **报错表现**：全功能 SPI-SD 整合后，Vivado Bitgen 报错中止，触发 DRC 校验 **AVAL-352**。
* **原因剖析**：Versal 物理层架构禁止对顶层 `inout` 端口（`sd_cmd`、`sd_dat`）进行隐式的三态推断（直接赋值 `assign port = oe ? out : 1'bz` 会被推断为 OBUFT，这在 Versal 上是不合法的）。
* **修复方法**：在 [piton_spi_sd_top.v](file:///L:/home/illya/openpiton/piton/design/chipset/noc_sd_bridge/rtl/piton_spi_sd_top.v) 中移除隐式三态，为双向端口**显式实例化 IOBUF 原语**：
  ```verilog
  IOBUF sd_cmd_iobuf (
      .O  (sd_cmd_i),
      .IO (sd_cmd),
      .I  (sd_cmd_o),
      .T  (~sd_cmd_oe)
  );
  ```
  该架构调整后，Build 64 与 Build 65 顺利调通了 SPI-SD 卡初始化与 AXI Block-Read 通路。

---

## 三、 单核 Linux 启动基线建立 (Build 66)

在 6月4日，我们基于 SPI-SD 架构和 IOBUF 约束，利用自包含源码重构（`P3_SELF_CONTAINED_SOURCES=1`）成功建立了单核（1x1）的 Linux 启动基线工程：

* **自包含重构**：重写了 [p3_create_bd.tcl](file:///L:/home/illya/openpiton/scripts/p3_create_bd.tcl)，自动在 `p3b66/source_snapshot/` 中复制所有 RTL 代码、约束和 CVA6 头文件，排除了外部动态链接库与 live 目录依赖。
* **引导流程连通**：板载运行时成功显示了 Bootrom Banner $\rightarrow$ SPI SDHC 初始化（[init_sd_p3.v](file:///L:/home/illya/openpiton/piton/design/chipset/axi_sd_bridge/rtl/init_sd_p3.v) 状态机正常拉高 `INIT_DONE`） $\rightarrow$ 65,536 块 Payload 自动拷贝至 DDR4 并完成校验 $\rightarrow$ 进入 BBL $\rightarrow$ 启动 Linux 5.1.0-rc7 内核。
* **控制台交互**：通过 picocom 以 `115200 8N1` 成功与 Linux 系统的交互式 `/bin/sh` shell 完成连接。
* **跑分程序验证**：手动在 `/dev/piton_sd2` 上以只读模式挂载了 ext2 跑分分区，成功触发 `/mnt/XSBench -s small -p 1 -l 1` 并获取跑分输出。

---

## 四、 2x1 多核扩展调试进展 (Build 67)

自 6月5日 以来，我们正式向多核扩展阶段（P1 阶段：2x1 Mesh，双核）发起攻关，由 [p3_build67_2x1_normal_spi_sd_boot.tcl](file:///L:/home/illya/openpiton/scripts/p3_build67_2x1_normal_spi_sd_boot.tcl) 驱动：

1. **多核参数与时钟/复位树生成**：
   * 重新生成了多核 PyHP 互连逻辑，并增强了自动化校验。确保 `define.tmp.h`、`chip.tmp.v`、`flat_id_to_xy.tmp.v` 等 tile 相关文件的一致性，防止 Vivado 在 sizing 外部 PLIC/CLINT 中断向量时出现端口宽度的 mismatch 报错。
   * 布线完成，WNS 时序裕量充足，PDI 与 LTX 文件生成成功。
2. **硬件烧录与 Bootrom 表现**：
   * 上板成功拉高 DONE，AXI 调试总线及四个 BD ILA 刷新正常。
   * 串口抓取表明，双核 Bootrom 执行顺利，打印出双核属性 `#Cores: 2`，完成了 SD 引导块的拷贝，并顺利跳转至 BBL。
   * BBL 成功输出了设备树信息（包含 `cpu@0` 和 `cpu@1` 以及对应的中断级联树）。
3. **当前挂起点**：
   * 在 BBL 设备树输出完毕后，跳转进入 Linux 的临界区，串口输出了一串乱码字节流并挂起，未能输出 `Linux version` 标志。

---

## 五、 下阶段工作与调试排查计划

针对 2x1 多核在 BBL 转向 Linux 阶段的乱码/挂死问题，我们设计了两个专门的 **SD 引导镜像排查方案（Discriminator Images）**，将在不重新跑 Vivado 综合的情况下，直接在板上定位故障源：

1. **验证单核 SMP 降级镜像 (`nosmp`)**：
   * 使用 [p3_make_build67_linux_handoff_images.sh](file:///L:/home/illya/openpiton/scripts/p3_make_build67_linux_handoff_images.sh) 编译一个排查镜像：保留 2x1 多核硬件，但在 BBL 设备树中将 `cpu@1` 的状态标记为 `disabled`，同时在内核 bootargs 中强行注入 `maxcpus=1 nosmp`。
   * *分析依据*：这会强制让 BBL 把辅助核心 `hart 1` 限制在 `wfi` 循环中，仅由主核心 `hart 0` 启动单核 Linux。如果能成功进入 Shell，说明故障原因为**多核同步冲突（SMP Bootup）**或 PLIC 多核中断映射未对齐。
2. **验证 BBL 跳转节点追踪镜像 (`bbl_markers`)**：
   * 在 BBL 的关键跳转入口、双核分配入口和执行 `mret` 指令进入 Linux 之前的节点插入特定的串口打印宏（`B67M` 标记），同时关闭冗长的设备树信息打印以规避控制台溢出。
   * *分析依据*：这可以精确定位处理器是在 BBL 内部执行 `mret` 之前死锁，还是已经成功执行了 `mret` 并跳转到了 Linux 的 `stvec` 空间（由于 earlycon 或 page table 未对齐触发了早期内核 Page Fault 乱码）。

我们将在下一步使用上述排查工具，依次写入 SD 卡并采集硬件串口波形，直至多核 Linux 控制台打通。

---

> [!NOTE]
> 本周报所述之分层定位机理、三态 DRC 解决方法及 Build 37–65 的具体 RTL 改动代码，可进一步查阅 Wiki 中的专题周报：
> * 物理层连线与三态 DRC 分析：[weekly_report_sd_issue.md](file:///L:/home/illya/openpiton/wiki/weekly_report_sd_issue.md)
> * 控制流死锁与字节通道错位分析：[weekly_report_uart_issue.md](file:///L:/home/illya/openpiton/wiki/weekly_report_uart_issue.md)
