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

## 四、 当前挂起点与下周排查计划

目前 Build 67 双核系统能够成功引导并打印出包含双核信息的设备树，但**在 BBL 转向 Linux 阶段发生乱码并挂死**。

为定位此跳转边界故障，我们设计了两个专门的 **SD 引导镜像排查方案（Discriminator Images）**，将在不重跑 Vivado 的情况下进行板级定位：

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
