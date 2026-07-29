#!/bin/busybox sh

/bin/busybox --install -s /bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mkdir -p /tmp /root /dev/shm /dev/mqueue /mnt
mount -t tmpfs tmpfs /dev/shm 2>/dev/null || true
mount -t mqueue mqueue /dev/mqueue 2>/dev/null || true
ip link set lo up

echo "=== P3_XSBENCH_MARKER_INIT_START ==="
echo "nproc=$(/bin/nproc)"

if /usr/bin/p3_mpi_system_smoke; then
	echo "=== P3_XSBENCH_MARKER_SYSTEM_PASS ==="
else
	echo "=== P3_XSBENCH_MARKER_SYSTEM_FAIL ==="
fi

echo "=== P3_XSBENCH_MARKER_RUN ==="
/root/XSBench_marked -t 1 -s small -p 1000 -l 1
status=$?
echo "=== P3_XSBENCH_MARKER_EXIT status=$status ==="
echo "=== P3_XSBENCH_MARKER_SHELL_READY ==="
exec /bin/sh
