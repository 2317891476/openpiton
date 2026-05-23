#!/usr/bin/env python3
# p3_serial.py — Connect to P3 UART via remote SSH
# Usage: python3 scripts/p3_serial.py [--capture N]
#   --capture N: capture for N seconds and print output, then exit
#   default: interactive mode

import pexpect, sys, argparse, time, os

REMOTE_HOST = "100.93.77.36"
REMOTE_USER = "illya"
REMOTE_PASS = "123456"
UART_DEVICE = "/dev/ttyUSB0"
BAUD = "115200"

def ssh_connect():
    """Connect to remote machine via SSH using pexpect."""
    child = pexpect.spawn(
        f'ssh -o StrictHostKeyChecking=no {REMOTE_USER}@{REMOTE_HOST}',
        timeout=15, encoding='utf-8'
    )
    i = child.expect(['password:', 'Password:', pexpect.EOF, pexpect.TIMEOUT])
    if i <= 1:
        child.sendline(REMOTE_PASS)
        child.expect(['\$', '#'], timeout=10)
        return child
    else:
        raise RuntimeError(f"SSH auth failed: {child.before}")

def capture_mode(seconds):
    """Capture UART output for N seconds and print to stdout."""
    print(f"Capturing UART for {seconds} seconds...")
    child = ssh_connect()

    # Kill any stale picocom sessions
    child.sendline('pkill -f picocom 2>/dev/null; sleep 0.5')
    child.expect(['\$', '#'], timeout=5)

    # Run picocom with timeout
    child.sendline(f'timeout {seconds} picocom -b {BAUD} --noreset {UART_DEVICE} 2>&1')
    time.sleep(seconds + 5)

    try:
        child.expect(['\$', '#'], timeout=5)
    except:
        pass

    output = child.before if hasattr(child, 'before') and child.before else ""
    # Extract actual content between "Terminal ready" and "Terminating"
    if "Terminal ready" in output:
        output = output.split("Terminal ready", 1)[-1]
    if "Terminating" in output:
        output = output.split("Terminating", 1)[0]
    if "Picocom was killed" in output:
        output = output.split("Picocom was killed", 1)[0]

    print(output.strip() or "(no output)")
    child.sendline('exit')

def interactive_mode():
    """Interactive serial console (pass-through to picocom)."""
    print(f"Connecting to P3 UART ({UART_DEVICE} @ {BAUD}) via {REMOTE_HOST}...")
    print("Press Ctrl-A then Ctrl-Q to exit.")
    print("=" * 50)

    child = ssh_connect()

    # Kill any stale sessions
    child.sendline('pkill -f picocom 2>/dev/null; sleep 0.5')
    child.expect(['\$', '#'], timeout=5)

    # Interactive picocom
    child.sendline(f'picocom -b {BAUD} {UART_DEVICE}')
    child.interact()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='P3 Serial Console')
    parser.add_argument('--capture', type=int, metavar='SECONDS',
                        help='Capture mode: collect output for N seconds and print')
    args = parser.parse_args()

    if args.capture:
        capture_mode(args.capture)
    else:
        interactive_mode()
