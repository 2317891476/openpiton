# AX7023/AX7203 Linux 启动复现说明

当前仓库实际使用的是 `a7203x` 原型验证目标和 AX7203 板级文件。如果实验记录里把板卡写作 AX7023，请先确认 FPGA 型号、DDR3 连线、SD 卡连线、UART 引脚以及 XDC 约束是否与仓库里的 `a7203x` 目标一致。下面流程按已经验证过的 `a7203x`/AX7203 路径描述。

## 总体流程

完整复现可以拆成五个阶段：

1. 准备 OpenPiton/Ariane 工程和 RISC-V 工具链。
2. 生成或取得 SD 卡启动镜像 `bbl.bin`。
3. 给 SD 卡分 GPT 两个分区，把 `bbl.bin` 写到第一个分区，把测试程序放到第二个分区。
4. 综合并烧录 FPGA bitstream。
5. 通过串口启动 Linux，挂载第二分区并运行 `hello`、`XSBench`。

当前启动链路是：

```text
FPGA bootrom -> SD 卡 GPT 第 1 分区 raw bbl.bin -> BBL -> Linux kernel + initramfs rootfs -> Buildroot login
```

注意：第 1 分区不是普通文件系统，而是 raw 写入的 `bbl.bin`。第 2 分区才是 Linux 启动后挂载使用的文件系统，用来放 `hello`、`XSBench` 等测试程序。

## 硬件准备

- FPGA 板卡：兼容 `a7203x` 目标的 ALINX AX7203 板卡。
- UART 终端：115200 波特率，8 位数据位，无校验，1 位停止位，关闭流控。
- JTAG：Vivado Hardware Manager 能够识别并烧录 FPGA。
- SD 卡：建议使用 8 GB 或更大的卡。所有写卡命令都会破坏原卡内容，执行前必须确认设备名。

在 Linux/WSL 主机上查看 SD 卡设备名：

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,RM,MOUNTPOINTS
sudo fdisk -l
```

下面命令用 `/dev/sdX` 表示整张 SD 卡。实际执行时必须替换成真实设备，例如 `/dev/sdb`。不要写成系统盘。

## 准备工程环境

从仓库根目录执行：

```bash
export PITON_ROOT=/home/illya/openpiton
cd $PITON_ROOT
source piton/piton_settings.bash
source piton/ariane_setup.sh
```

首次搭建 Ariane 工具链时，执行：

```bash
cd $PITON_ROOT
piton/ariane_build_tools.sh
```

这个脚本会初始化 Ariane submodule，并构建 RISC-V GCC、FESVR、Spike、Verilator 和 RISC-V tests。它不等同于生成 SD 卡 Linux 镜像；SD 卡镜像由 ariane-sdk 的 `bbl.bin` 流程生成。

## 生成 SD 卡启动镜像

SD 卡第 1 分区需要写入 `bbl.bin`。这个文件不是单独的 bootloader，它通常包含：

- BBL/RISC-V proxy kernel 启动代码。
- Linux kernel `vmlinux` 作为 BBL payload。
- Buildroot 生成的 initramfs/rootfs，被 Linux config 以 `rootfs.cpio` 形式打进内核。

也就是说，板上 bootrom 从 SD 第 1 分区把 `bbl.bin` 拷到 DDR `0x80000000` 附近执行，后续 BBL 再进入 Linux。Buildroot 根文件系统已经在内核 initramfs 里，所以 Linux 正常启动不依赖第 2 分区。第 2 分区只用于额外测试程序和数据。

### 方式一：使用预编译 bbl.bin

如果已经有可工作的 `bbl.bin`，可以直接使用。当前本机曾验证过的产物路径包括：

```text
build/a7203x/bbl.bin
build/a7203x/working_snapshot_20260506/bbl_working.bin
```

这些 `build/` 目录下的文件是本地生成物，不应该提交到 GitHub。为了避免误写旧文件，写卡前建议记录大小和哈希：

```bash
sha256sum build/a7203x/bbl.bin
stat -c '%n %s bytes' build/a7203x/bbl.bin
```

第 1 分区大小是 32 MiB，`bbl.bin` 必须小于这个大小。当前验证过的 `bbl.bin` 大约 15 MiB。

### 方式二：用 ariane-sdk 重新生成

官方 OpenPiton README 原始流程建议使用 ariane-sdk 生成 Linux 镜像。典型命令如下：

```bash
cd /path/to/ariane-sdk
make bbl.bin
```

本地 `build/a7203x/ariane-sdk/Makefile` 中的依赖关系是：

```text
make bbl.bin
  -> make bbl
    -> make vmlinux
      -> make -C buildroot defconfig BR2_DEFCONFIG=../configs/buildroot_defconfig
      -> make -C buildroot
    -> riscv-pk/configure --with-payload=vmlinux --enable-logo ...
    -> make -C build
  -> riscv64-unknown-elf-objcopy ... bbl bbl.bin
```

几个关键配置文件：

```text
configs/buildroot_defconfig
configs/linux_defconfig
configs/busybox.config
configs/0099-Piton-SD-Driver.patch
rootfs/
```

其中 `buildroot_defconfig` 会：

- 使用外部 RISC-V Linux 工具链。
- 从 `pulp-platform/linux` 的 `ariane-v0.7` 分支取内核。
- 应用 `0099-Piton-SD-Driver.patch`。
- 使用 `rootfs/` 作为 Buildroot overlay。
- 启用 OpenSSH、NFS、e2fsprogs、ncurses、zlib、lynx 等软件包。
- 生成 initramfs：`BR2_TARGET_ROOTFS_INITRAMFS=y`。

`linux_defconfig` 会：

- 启用 initramfs：`CONFIG_INITRAMFS_SOURCE="${BR_BINARIES_DIR}/rootfs.cpio"`。
- 启用 8250 串口控制台。
- 启用 SiFive PLIC。
- 启用 OpenPiton/Ariane ramdisk 相关配置。
- 启用 `piton_sd` 所需的 SD/MMC/SPI/EXT3/NFS 等内核功能。

如果只是在调 RTL 或重新综合 bitstream，通常不需要重新生成 `bbl.bin`。如果改了 Linux、Buildroot、rootfs overlay、BBL、SD 驱动补丁或启动参数，就需要重新生成并重新写 SD 卡第 1 分区。

## 准备 SD 卡

### 1. 卸载旧分区

先确认设备名，再卸载已经自动挂载的分区：

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,RM,MOUNTPOINTS
sudo umount /dev/sdX1 2>/dev/null || true
sudo umount /dev/sdX2 2>/dev/null || true
```

### 2. 创建 GPT 分区表

仓库 README 使用以下分区布局：

```bash
sudo sgdisk --clear \
  --new=1:2048:67583 \
  --new=2 \
  --typecode=1:3000 \
  --typecode=2:8300 \
  /dev/sdX
```

含义：

- 第 1 分区：LBA 2048 到 67583，共 65536 个 512B sector，也就是 32 MiB。这里 raw 写入 `bbl.bin`。
- 第 2 分区：剩余空间，Linux 文件系统，板上启动后显示为 `/dev/piton_sd2`。
- `typecode=1:3000` 是 ONIE boot 类型，bootrom 只需要 GPT 第一个分区的起始位置，不需要里面有文件系统。
- `typecode=2:8300` 是普通 Linux filesystem。

分区后让系统重新读取分区表：

```bash
sudo partprobe /dev/sdX
lsblk /dev/sdX
```

### 3. 写入 bbl.bin 到第 1 分区

如果使用本地生成物：

```bash
sudo dd if=build/a7203x/bbl.bin of=/dev/sdX1 bs=1M status=progress oflag=sync
sync
```

如果使用其他路径：

```bash
sudo dd if=/path/to/bbl.bin of=/dev/sdX1 bs=1M status=progress oflag=sync
sync
```

必须写到分区 `/dev/sdX1`，不要写到整盘 `/dev/sdX`，否则会覆盖 GPT 分区表。

### 4. 格式化第 2 分区并放测试程序

内核配置里明确启用了 EXT3，因此建议把第 2 分区格式化为 ext3：

```bash
sudo mkfs.ext3 -F -L PITON_TEST /dev/sdX2
sudo mkdir -p /mnt/piton-sd
sudo mount /dev/sdX2 /mnt/piton-sd
```

把测试程序复制到第 2 分区：

```bash
sudo cp /path/to/hello /mnt/piton-sd/hello
sudo cp /path/to/XSBench /mnt/piton-sd/XSBench
sudo chmod +x /mnt/piton-sd/hello /mnt/piton-sd/XSBench
sync
sudo umount /mnt/piton-sd
```

如果本机已有交叉编译好的 XSBench，可参考当前本地路径：

```text
build/a7203x/XSBench/openmp-threading/XSBench
```

`hello` 可以是任意 RISC-V Linux 用户态可执行文件。一个最小示例：

```c
#include <stdio.h>

int main(void) {
    puts("hello from OpenPiton/Ariane");
    return 0;
}
```

交叉编译：

```bash
riscv64-unknown-linux-gnu-gcc -static -O2 hello.c -o hello
```

编译 XSBench 的一般方式：

```bash
git clone https://github.com/ANL-CESAR/XSBench.git
cd XSBench/openmp-threading
make clean
make CC=riscv64-unknown-linux-gnu-gcc OPENMP=no
```

如果要打开 OpenMP，需要确认 Buildroot/rootfs 中有匹配的 OpenMP runtime。为了先验证板上能跑通，建议先用 `OPENMP=no` 构建单线程版本。

## 构建 Bitstream

从仓库根目录执行：

```bash
export PITON_ROOT=/home/illya/openpiton
source $PITON_ROOT/piton/piton_settings.bash
cd $PITON_ROOT/build
protosyn -b a7203x -d system --core=ariane --uart-dmw ddr
```

第一次完整复现时建议不要设置 `PITON_SKIP_ARIANE_FW_BUILD=1`，因为 `protosyn` 的 setup 阶段会重新生成：

- baremetal bootrom。
- Linux bootrom。
- Ariane PLIC register map。

`setup.tcl` 里对 Ariane 的 PLIC 生成逻辑是：

```text
NUM_TARGETS = 2 * PITON_NUM_TILES
NUM_SOURCES = 2
gen_plic_addrmap.py -t NUM_TARGETS -s NUM_SOURCES > plic_regmap.sv
```

如果设置了 `PITON_SKIP_ARIANE_FW_BUILD=1`，这一步也会被跳过。只有在 bootrom 和 `plic_regmap.sv` 都已经确认正确、只是重复综合 RTL 时，才建议使用：

```bash
export PITON_SKIP_ARIANE_FW_BUILD=1
cd $PITON_ROOT/build
protosyn -b a7203x -d system --core=ariane --uart-dmw ddr
```

生成的 bitstream 路径为：

```text
build/a7203x/system/a7203x_system.runs/impl_1/system.bit
```

实现结束后检查 timing：

```bash
rg -n "All user specified timing constraints are met|WNS|WHS" \
  build/a7203x/system/a7203x_system.runs/impl_1/system_timing_summary_routed.rpt
```

检查 PLIC 宽度告警：

```bash
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

把 SD 卡插回 FPGA 板卡。烧录 FPGA 前或烧录完成后立刻打开串口终端。串口参数为：

```text
115200 8N1, no flow control
```

正常启动时应能看到以下关键输出：

```text
OpenPiton+Ariane Platform
sd initialized!
gpt partition table header:
copying boot image
done!
bbl loader
Linux version 5.1.0-rc7
plic: mapped 2 interrupts with 1 handlers for 2 contexts.
fff0c2c000.uart: ttyS0 at MMIO 0xfff0c2c000 (irq = 1, base_baud = 1875000) is a 16550
Starting logging: OK
Starting sshd: OK
NFS preparation skipped, OK
Welcome to Buildroot
buildroot login:
```

除非 SD 镜像被改过账号配置，否则使用 `root` 登录。

## 运行 SD 卡测试程序

登录后在串口终端执行：

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

如果 `/dev/piton_sd2` 存在但 `mount` 失败，优先确认第 2 分区是否被格式化成内核支持的文件系统。当前推荐 ext3。

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
- bootrom 能打印，但 SD 初始化失败：检查 SD 卡是否插好、分区表是否为 GPT、SD 卡引脚约束是否对应当前板卡。
- 能看到 GPT，但不能进入 BBL/Linux：确认 `bbl.bin` 写到了 `/dev/sdX1`，不是 `/dev/sdX`，并确认 `bbl.bin` 小于 32 MiB。
- 启动停在 user-space 的 random 或 ssh 相关信息附近：检查 Vivado 综合日志中是否存在 PLIC `plic_regs` 端口宽度不匹配告警。
- 旧 bitstream 能启动，但重新构建的 bitstream 不能启动：对比 `system.bit` 的 SHA256，并确认源码中使用的是 2-source `plic_regmap.sv`。
- `XSBench` 看起来像卡住：先用 `-s small -l 100` 做小规模验证；单核 50 MHz 构建在更大的 lookup 次数下会运行很久。
- `XSBench` 缺动态库：重新用 `riscv64-unknown-linux-gnu-gcc -static` 或关闭 OpenMP 构建，或者把所需运行库加入 Buildroot/rootfs。
