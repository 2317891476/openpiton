#!/usr/bin/env python3
import argparse
from pathlib import Path

from p3_platform_config import (
    DEFAULT_DEVICE_MAP,
    format_u64_cells,
    int_arg,
    load_device_map,
)


REQUIRED_PORTS = ("mem", "sd", "uart", "ariane_clint", "ariane_plic")


def cpu_node(idx: int, cpu_frequency: int) -> str:
    return f"""        CPU{idx}: cpu@{idx} {{
            clock-frequency = <{cpu_frequency}>;
            u-boot,dm-pre-reloc;
            device_type = "cpu";
            reg = <{idx}>;
            status = "okay";
            compatible = "openhwgroup,cva6", "riscv";
            riscv,isa = "rv64imafdc";
            mmu-type = "riscv,sv39";
            tlb-split;
            CPU{idx}_intc: interrupt-controller {{
                #address-cells = <0>;
                #interrupt-cells = <1>;
                interrupt-controller;
                compatible = "riscv,cpu-intc";
            }};
        }};
"""


def interrupt_list(harts: int, supervisor: bool) -> str:
    parts = []
    for idx in range(harts):
        if supervisor:
            parts.append(f"&CPU{idx}_intc 11 &CPU{idx}_intc 9")
        else:
            parts.append(f"&CPU{idx}_intc 3 &CPU{idx}_intc 7")
    return " ".join(parts)


def dts_string(value: str) -> str:
    if any(char in value for char in "\0\r\n"):
        raise ValueError("DTS string values cannot contain NUL or newlines")
    return value.replace("\\", "\\\\").replace('"', '\\"')


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate the P3 OpenSBI/Linux DTB source for N harts."
    )
    parser.add_argument("--harts", type=int, default=64)
    parser.add_argument("--out", required=True)
    parser.add_argument(
        "--device-map",
        type=Path,
        default=DEFAULT_DEVICE_MAP,
        help="P3 devices_ariane.xml; memory and peripheral ranges come from it",
    )
    parser.add_argument(
        "--bootargs",
        default=(
            "earlycon=uart8250,mmio,0xfff0c2c000 "
            "console=ttyS0,115200n8 root=/dev/ram0 rw "
            "loglevel=8 keep_bootcon initcall_debug"
        ),
    )
    parser.add_argument("--plic-ndev", type=int_arg, default=2)
    parser.add_argument("--cpu-frequency", type=int_arg, default=30_000_000)
    parser.add_argument("--timebase-divisor", type=int_arg, default=128)
    parser.add_argument(
        "--timebase-frequency",
        type=int_arg,
        help="optional assertion; must equal cpu-frequency/timebase-divisor",
    )
    parser.add_argument(
        "--initrd",
        type=Path,
        help="initramfs file used to derive linux,initrd-end",
    )
    parser.add_argument("--initrd-addr", type=int_arg, default=0x90000000)
    args = parser.parse_args()

    if args.harts < 1:
        raise SystemExit("--harts must be positive")
    if args.plic_ndev < 1:
        raise SystemExit("--plic-ndev must be positive")
    if args.cpu_frequency < 1 or args.timebase_divisor < 1:
        raise SystemExit("CPU frequency and timebase divisor must be positive")
    if args.cpu_frequency % args.timebase_divisor:
        raise SystemExit(
            "--cpu-frequency must be exactly divisible by --timebase-divisor"
        )
    derived_timebase_frequency = args.cpu_frequency // args.timebase_divisor
    if (
        args.timebase_frequency is not None
        and args.timebase_frequency != derived_timebase_frequency
    ):
        raise SystemExit(
            "--timebase-frequency disagrees with cpu-frequency/timebase-divisor: "
            f"expected {derived_timebase_frequency}, got {args.timebase_frequency}"
        )
    timebase_frequency = derived_timebase_frequency

    try:
        regions = load_device_map(args.device_map, REQUIRED_PORTS)
        memory = regions["mem"]
        sd = regions["sd"]
        uart = regions["uart"]
        clint = regions["ariane_clint"]
        plic = regions["ariane_plic"]
        escaped_bootargs = dts_string(args.bootargs)
        chosen_initrd = ""
        if args.initrd is not None:
            if not args.initrd.is_file():
                raise ValueError(f"initramfs does not exist: {args.initrd}")
            initrd_size = args.initrd.stat().st_size
            if not memory.contains(args.initrd_addr, initrd_size):
                raise ValueError(
                    f"initramfs range [0x{args.initrd_addr:x},"
                    f"0x{args.initrd_addr + initrd_size:x}) is outside DDR "
                    f"[0x{memory.base:x},0x{memory.end:x})"
                )
            chosen_initrd = (
                "\n"
                "        linux,initrd-start = "
                f"<{format_u64_cells(args.initrd_addr)}>;\n"
                "        linux,initrd-end = "
                f"<{format_u64_cells(args.initrd_addr + initrd_size)}>;"
            )
    except (OSError, ValueError) as exc:
        raise SystemExit(f"ERROR: {exc}") from exc

    cpus = "".join(cpu_node(idx, args.cpu_frequency) for idx in range(args.harts))
    clint_interrupts = interrupt_list(args.harts, supervisor=False)
    plic_interrupts = interrupt_list(args.harts, supervisor=True)

    dts = f"""// Generated by scripts/p3_generate_opensbi_dts.py
// P3 OpenSBI/Linux DTB source for {args.harts} harts.

/dts-v1/;

/ {{
    #address-cells = <2>;
    #size-cells = <2>;
    compatible = "openpiton,cva6platform";

    chosen {{
        stdout-path = "uart0:115200";
        bootargs = "{escaped_bootargs}";{chosen_initrd}
    }};

    aliases {{
        console = &uart0;
        serial0 = &uart0;
    }};

    cpus {{
        #address-cells = <1>;
        #size-cells = <0>;
        timebase-frequency = <{timebase_frequency}>;
{cpus}
    }};

    memory@{memory.base:x} {{
        device_type = "memory";
        reg = <{format_u64_cells(memory.base)} {format_u64_cells(memory.size)}>;
    }};

    sdhci_0: sdhci@{sd.base:x} {{
        status = "okay";
        compatible = "openpiton,piton-mmc";
        reg = <{format_u64_cells(sd.base)} {format_u64_cells(sd.size)}>;
    }};

    uart0: uart@{uart.base:x} {{
        compatible = "ns16550";
        reg = <{format_u64_cells(uart.base)} {format_u64_cells(uart.size)}>;
        clock-frequency = <{args.cpu_frequency}>;
        current-speed = <115200>;
        interrupt-parent = <&PLIC0>;
        interrupts = <1>;
        reg-shift = <0>;
    }};

    clint@{clint.base:x} {{
        compatible = "sifive,clint0", "riscv,clint0";
        interrupts-extended = <{clint_interrupts}>;
        reg = <{format_u64_cells(clint.base)} {format_u64_cells(clint.size)}>;
        reg-names = "control";
    }};

    PLIC0: plic@{plic.base:x} {{
        #address-cells = <0>;
        #interrupt-cells = <1>;
        compatible = "sifive,plic-1.0.0", "riscv,plic0";
        interrupt-controller;
        interrupts-extended = <{plic_interrupts}>;
        reg = <{format_u64_cells(plic.base)} {format_u64_cells(plic.size)}>;
        riscv,max-priority = <7>;
        riscv,ndev = <{args.plic_ndev}>;
    }};
}};
"""

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(dts, encoding="utf-8")
    print(
        f"Generated {out}: harts={args.harts} "
        f"memory=[0x{memory.base:x},0x{memory.end:x}) "
        f"timebase={timebase_frequency}Hz device_map={args.device_map}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
