#!/bin/busybox sh

/bin/busybox --install -s /bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mkdir -p /tmp /root /dev/shm /dev/mqueue /mnt
mount -t tmpfs tmpfs /dev/shm 2>/dev/null || true
mount -t mqueue mqueue /dev/mqueue 2>/dev/null || true
ip link set lo up

echo "=== P3_LINUX612_MPI_INIT_START ==="
echo "nproc=$(/bin/nproc)"
echo "cpuinfo_processors=$(grep -c '^processor' /proc/cpuinfo)"

if /usr/bin/p3_mpi_system_smoke; then
	echo "=== P3_LINUX612_MPI_SYSTEM_PASS ==="
else
	echo "=== P3_LINUX612_MPI_SYSTEM_FAIL ==="
fi

echo "=== P3_LINUX612_MPI_SHELL_READY ==="
exec /bin/sh
