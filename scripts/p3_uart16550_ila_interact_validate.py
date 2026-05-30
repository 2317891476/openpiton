#!/usr/bin/env python3
"""Program-independent serial + ILA interaction check for the P3 UART16550 smoke design."""

import argparse
import os
import subprocess
import sys
import time

import pexpect


REMOTE_HOST = os.environ.get("P3_REMOTE_HOST", "100.93.77.36")
REMOTE_USER = os.environ.get("P3_REMOTE_USER", "illya")
REMOTE_PASS = os.environ.get("P3_REMOTE_PASS")
UART_DEVICE = os.environ.get("P3_UART_DEVICE", "/dev/ttyUSB0")
BAUD = int(os.environ.get("P3_UART_BAUD", "115200"))
TEST_TEXT = "P3UART?\r\n"


def ssh_connect():
    ssh_cmd = (
        f"ssh -o StrictHostKeyChecking=no "
        f"-o PreferredAuthentications=publickey,password "
        f"{REMOTE_USER}@{REMOTE_HOST}"
    )
    child = pexpect.spawn(
        ssh_cmd,
        timeout=20,
        encoding="utf-8",
    )
    idx = child.expect(["password:", "Password:", r"\$", "#", pexpect.EOF, pexpect.TIMEOUT])
    if idx in (0, 1):
        if REMOTE_PASS is None:
            child.close(force=True)
            raise RuntimeError("SSH password requested; set P3_REMOTE_PASS or configure SSH key auth")
        child.sendline(REMOTE_PASS)
        child.expect([r"\$", "#"], timeout=15)
        return child
    if idx in (2, 3):
        return child
    if idx > 3:
        raise RuntimeError(f"SSH auth failed: {child.before}")


def serial_interact(capture_seconds):
    child = ssh_connect()
    try:
        child.sendline("pkill -f 'picocom|cat .*ttyUSB0|python3 .*ttyUSB0' 2>/dev/null; sleep 0.5")
        child.expect([r"\$", "#"], timeout=10)

        remote_py = (
            "python3 - <<'PY'\n"
            "import os, select, sys, termios, time\n"
            f"dev = {UART_DEVICE!r}\n"
            f"baud = {BAUD}\n"
            f"payload = {TEST_TEXT.encode('latin1')!r}\n"
            "rates = {115200: termios.B115200}\n"
            "fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)\n"
            "attrs = termios.tcgetattr(fd)\n"
            "attrs[0] = 0\n"
            "attrs[1] = 0\n"
            "attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL\n"
            "attrs[3] = 0\n"
            "attrs[4] = rates[baud]\n"
            "attrs[5] = rates[baud]\n"
            "attrs[6][termios.VMIN] = 0\n"
            "attrs[6][termios.VTIME] = 0\n"
            "termios.tcsetattr(fd, termios.TCSANOW, attrs)\n"
            "termios.tcflush(fd, termios.TCIOFLUSH)\n"
            "time.sleep(0.5)\n"
            "start = time.time()\n"
            "banner = b''\n"
            "while time.time() - start < 2.0:\n"
            "    r, _, _ = select.select([fd], [], [], 0.1)\n"
            "    if r:\n"
            "        try:\n"
            "            banner += os.read(fd, 4096)\n"
            "        except BlockingIOError:\n"
            "            pass\n"
            "os.write(fd, payload)\n"
            "echo = b''\n"
            f"deadline = time.time() + {capture_seconds:.1f}\n"
            "while time.time() < deadline:\n"
            "    r, _, _ = select.select([fd], [], [], 0.1)\n"
            "    if r:\n"
            "        try:\n"
            "            echo += os.read(fd, 4096)\n"
            "        except BlockingIOError:\n"
            "            pass\n"
            "os.close(fd)\n"
            "print('BANNER_HEX=' + banner.hex())\n"
            "print('ECHO_HEX=' + echo.hex())\n"
            "print('BANNER_TEXT=' + banner.decode('latin1', errors='replace').replace('\\r', '<CR>').replace('\\n', '<LF>'))\n"
            "print('ECHO_TEXT=' + echo.decode('latin1', errors='replace').replace('\\r', '<CR>').replace('\\n', '<LF>'))\n"
            "PY"
        )
        child.sendline(remote_py)
        child.expect([r"\$", "#"], timeout=capture_seconds + 20)
        output = child.before
        return output
    finally:
        child.sendline("exit")
        child.close(force=True)


def wait_for_capture_arm(proc, timeout):
    lines = []
    deadline = time.time() + timeout
    while time.time() < deadline:
        line = proc.stdout.readline()
        if line:
            sys.stdout.write(line)
            sys.stdout.flush()
            lines.append(line)
            if "P3_ILA_ARMED" in line and not line.lstrip().startswith("#"):
                return lines
            if "ERROR:" in line and not line.lstrip().startswith("#"):
                raise RuntimeError("ILA capture failed before arming")
        elif proc.poll() is not None:
            raise RuntimeError("ILA capture exited before arming")
        else:
            time.sleep(0.1)
    raise TimeoutError("Timed out waiting for ILA capture to arm")


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def drain_process(proc):
    remaining = proc.communicate()[0] or ""
    if remaining:
        sys.stdout.write(remaining)
    return proc.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-ila", action="store_true", help="only run serial interaction")
    parser.add_argument("--capture-seconds", type=float, default=5.0)
    parser.add_argument("--arm-timeout", type=float, default=600.0)
    args = parser.parse_args()

    repo_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    capture_script = os.path.join(repo_dir, "scripts", "p3_uart16550_ila_interact_capture.tcl")

    proc = None
    if not args.no_ila:
        cmd = ["vivado", "-mode", "batch", "-source", capture_script]
        print("Starting ILA capture:", " ".join(cmd))
        proc = subprocess.Popen(
            cmd,
            cwd=repo_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
        try:
            wait_for_capture_arm(proc, args.arm_timeout)
        except Exception:
            stop_process(proc)
            raise

    print(f"Sending serial test payload: {TEST_TEXT!r}")
    serial_output = serial_interact(args.capture_seconds)
    print(serial_output)

    if proc is not None:
        rc = drain_process(proc)
        if rc != 0:
            print(f"ERROR: ILA capture exited with {rc}", file=sys.stderr)
            return rc

    if "4158493136353530205245414459" not in serial_output and "AXI16550 READY" not in serial_output:
        print("WARNING: ready banner was not observed in the short serial pre-capture window")
    if TEST_TEXT.encode("latin1").hex() not in serial_output:
        print("ERROR: expected echo payload was not observed", file=sys.stderr)
        return 1

    print("PASS: serial echo observed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
