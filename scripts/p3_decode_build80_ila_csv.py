#!/usr/bin/env python3
"""Decode synchronized Build 80 S-to-M trap/CSR ILA captures."""

import argparse
import glob
import json
import os
import sys

import p3_decode_build76_ila_csv as csvutil


PRIV_NAMES = {0: "U", 1: "S", 3: "M"}
FU_NAMES = csvutil.FU_NAMES
OP_NAMES = {
    **csvutil.OP_NAMES,
    0x1F: "CSR_WRITE",
    0x20: "CSR_READ",
    0x21: "CSR_SET",
    0x22: "CSR_CLEAR",
}
CSR_FUNCT3_NAMES = {
    1: "CSRRW",
    2: "CSRRS",
    3: "CSRRC",
    5: "CSRRWI",
    6: "CSRRSI",
    7: "CSRRCI",
}
CSR_NAMES = {0xC00: "cycle", 0xC01: "time", 0xC02: "instret"}


def find_capture_set(directory):
    axis0_matches = []
    for prefix in ("ila_capture", "ila_snapshot"):
        pattern = os.path.join(
            directory,
            f"{prefix}_build80_*_u_bd_openpiton_top_i_axis_ila_0.csv",
        )
        axis0_matches.extend(glob.glob(pattern))
    axis0_matches.sort(key=os.path.getmtime)
    if not axis0_matches:
        raise FileNotFoundError(f"no Build 80 axis_ila_0 CSV in {directory}")
    axis0 = axis0_matches[-1]
    result = [axis0]
    for index in range(1, 4):
        path = axis0.replace("_axis_ila_0.csv", f"_axis_ila_{index}.csv")
        if not os.path.isfile(path):
            raise FileNotFoundError(f"matching axis_ila_{index} CSV is missing: {path}")
        result.append(path)
    return result


def find_ltx(capture_directory, explicit_path=None):
    if explicit_path:
        if not os.path.isfile(explicit_path):
            raise FileNotFoundError(f"Build 80 LTX does not exist: {explicit_path}")
        return explicit_path
    matches = sorted(
        glob.glob(
            os.path.join(
                os.path.abspath(capture_directory),
                "..",
                "p3_top_build80_trap_csr_eco.ltx",
            )
        )
    )
    if len(matches) != 1:
        raise FileNotFoundError(
            "expected one Build 80 LTX beside the capture directory; "
            f"found {matches}"
        )
    return matches[0]


def load_ltx_layout(path):
    with open(path) as stream:
        document = json.load(stream)
    cores = {}
    for probeset in document["ltx_root"]["ltx_data"]:
        if probeset.get("name") != "EDA_PROBESET":
            continue
        for core in probeset.get("debug_cores", []):
            name = core.get("name", "")
            if "axis_ila_" not in name:
                continue
            layout = cores.setdefault(name, {})
            for pin in core.get("pins", []):
                nets = pin.get("nets", [])
                if len(nets) != 1:
                    raise ValueError(f"{name} pin has {len(nets)} nets: {pin}")
                key = (int(pin["portIndex"]), int(pin["leftIndex"]))
                net = nets[0]["name"]
                if key in layout and layout[key] != net:
                    raise ValueError(f"conflicting LTX mapping for {name} {key}")
                layout[key] = net
    expected = {f"u_bd/openpiton_top_i/axis_ila_{index}" for index in range(4)}
    if set(cores) != expected:
        raise ValueError(f"Build 80 LTX ILA set mismatch: {sorted(cores)}")
    return cores


def column_for_net(columns, net):
    if net in columns:
        return columns[net]
    basename = net.rsplit("/", 1)[-1]
    matches = [
        series for name, series in columns.items() if name.rsplit("/", 1)[-1] == basename
    ]
    if len(matches) != 1:
        raise ValueError(f"expected one CSV column for LTX net {net!r}, found {len(matches)}")
    return matches[0]


def reconstruct_from_net_map(columns, bit_to_net, width):
    missing = sorted(set(range(width)) - set(bit_to_net))
    extra = sorted(set(bit_to_net) - set(range(width)))
    if missing or extra:
        raise ValueError(f"LTX vector map mismatch: missing={missing} extra={extra}")
    by_bit = {bit: column_for_net(columns, bit_to_net[bit]) for bit in range(width)}
    values = []
    for sample in range(len(by_bit[0])):
        value = 0
        for bit in range(width):
            if by_bit[bit][sample] not in (0, 1):
                raise ValueError(f"ILA bit {bit} sample {sample} is not binary")
            value |= by_bit[bit][sample] << bit
        values.append(value)
    return values


def build_vector_maps(layouts):
    axis0 = layouts["u_bd/openpiton_top_i/axis_ila_0"]
    pc = {
        (port - 1) * 16 + bit: net
        for (port, bit), net in axis0.items()
        if 1 <= port <= 4
    }
    vectors = {"pc": pc}
    for index in range(1, 4):
        name = f"u_bd/openpiton_top_i/axis_ila_{index}"
        vectors[f"ila{index}"] = {
            bit: net for (port, bit), net in layouts[name].items() if port == 0
        }
    vectors["ila0_trigger"] = {0: axis0[(0, 0)]}
    return vectors


def decode_packed_state(value):
    mcause = ((value >> 30) & 0x3F) | (((value >> 60) & 0x7) << 6)
    mcause |= ((value >> 36) & 1) << 63
    return {
        "ex_commit_valid": value & 1,
        "csr_illegal": (value >> 1) & 1,
        "commit_valid": (value >> 2) & 1,
        "commit_ack": (value >> 3) & 1,
        "fu": (value >> 4) & 0xF,
        "op": (value >> 8) & 0xFF,
        "csr_addr": (value >> 16) & 0xFFF,
        "priv": (value >> 28) & 0x3,
        "mcause": mcause,
        "mcounteren": (value >> 37) & 0x3F,
        "wfi": (value >> 43) & 1,
        "mstatus_mie": (value >> 44) & 1,
        "mstatus_sie": (value >> 45) & 1,
        "mie": (value >> 46) & 0x3F,
        "mip": (value >> 52) & 0x7,
        "mideleg": (value >> 55) & 0x7,
        "no_st_pending": (value >> 58) & 1,
        "wbuffer_empty": (value >> 59) & 1,
        "trigger": (value >> 63) & 1,
    }


def decode_csr_instruction(instruction):
    opcode = instruction & 0x7F
    funct3 = (instruction >> 12) & 0x7
    return {
        "instruction": instruction & 0xFFFFFFFF,
        "opcode": opcode,
        "funct3": funct3,
        "operation": CSR_FUNCT3_NAMES.get(funct3),
        "rd": (instruction >> 7) & 0x1F,
        "rs1_or_zimm": (instruction >> 15) & 0x1F,
        "csr": (instruction >> 20) & 0xFFF,
        "is_csr": opcode == 0x73 and funct3 in CSR_FUNCT3_NAMES,
        "is_ecall": instruction == 0x00000073,
    }


def rising_edges(series):
    return [index for index in range(1, len(series)) if not series[index - 1] and series[index]]


def validate_synchronized_capture(trigger_series, trigger_samples):
    if len({len(series) for series in trigger_series}) != 1:
        raise ValueError("Build 80 ILA sample counts differ")
    if len(set(trigger_samples)) != 1:
        raise ValueError(f"Build 80 CSV trigger indices differ: {trigger_samples}")
    reference = trigger_series[0]
    for index, series in enumerate(trigger_series[1:], start=1):
        if series != reference:
            raise ValueError(f"axis_ila_{index} common-trigger samples are not synchronized")
    trigger = trigger_samples[0]
    if trigger not in rising_edges(reference):
        raise ValueError(
            f"CSV trigger sample {trigger} is not a priv_lvl_q[1] rising edge"
        )
    return trigger


def validate_snapshot_capture(trigger_series, trigger_samples):
    if len({len(series) for series in trigger_series}) != 1:
        raise ValueError("Build 80 ILA sample counts differ")
    if len(set(trigger_samples)) != 1:
        raise ValueError(f"Build 80 CSV trigger indices differ: {trigger_samples}")
    for index, series in enumerate(trigger_series):
        if len(set(series)) != 1:
            raise ValueError(
                f"axis_ila_{index} privilege trigger is not stable in snapshot"
            )
    levels = [series[0] for series in trigger_series]
    if len(set(levels)) != 1:
        raise ValueError(f"Build 80 snapshot privilege levels differ: {levels}")
    return trigger_samples[0]


def find_csr_match(states, csr, first, last):
    matches = [
        index
        for index in range(max(0, first), min(len(states), last + 1))
        if states[index]["csr_addr"] == csr
    ]
    return matches


def linux_linked_address(pc):
    """Map a Build 66 physical Linux PC to the kernel ELF link address."""
    if 0x80200000 <= pc < 0x88000000:
        return 0xFFFFFFFF80000000 + (pc - 0x80200000)
    return pc


def acknowledged_pc_timeline(pc, states, first, last):
    timeline = []
    previous = None
    for index in range(max(0, first), min(len(pc), last)):
        if not states[index]["commit_ack"]:
            continue
        gap = None if previous is None else index - previous
        timeline.append((index, pc[index], gap))
        previous = index
    return timeline


def is_s_mode_ecall(interrupt, cause, instruction, pre_states):
    return (
        not interrupt
        and cause == 9
        and instruction["is_ecall"]
        and any(state["priv"] == 1 for state in pre_states)
    )


def format_row(index, trigger, pc, mepc, mtval, state):
    cause = state["mcause"] & 0x1FF
    interrupt = (state["mcause"] >> 63) & 1
    return (
        f"  {index - trigger:+4d} sample={index:4d} "
        f"priv={PRIV_NAMES.get(state['priv'], str(state['priv']))} "
        f"pc=0x{pc:016x} mepc=0x{mepc:016x} "
        f"mcause={'irq' if interrupt else 'exc'}:{cause} "
        f"mtval=0x{mtval & 0xFFFFFFFF:08x} csr=0x{state['csr_addr']:03x} "
        f"FU={FU_NAMES.get(state['fu'], hex(state['fu']))} "
        f"op={OP_NAMES.get(state['op'], hex(state['op']))} "
        f"ex={state['ex_commit_valid']} csr_illegal={state['csr_illegal']} "
        f"v/a={state['commit_valid']}/{state['commit_ack']} "
        f"mcounteren=0x{state['mcounteren']:02x}"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", help="directory containing Build 80 CSV files")
    parser.add_argument("--ltx", help="matching Build 80 LTX; defaults beside captures/")
    parser.add_argument("--firmware-elf", help="OpenSBI ELF used to resolve post-trap PCs")
    parser.add_argument("--vmlinux", help="matching Linux ELF used to resolve trap mepc")
    parser.add_argument(
        "--snapshot",
        action="store_true",
        help="decode a trigger-now final-state snapshot with stable privilege",
    )
    parser.add_argument("--window", type=int, default=8, help="samples shown around trigger")
    args = parser.parse_args()

    try:
        paths = find_capture_set(args.capture)
        ltx_path = find_ltx(args.capture, args.ltx)
        vector_maps = build_vector_maps(load_ltx_layout(ltx_path))
        captures = [csvutil.read_capture(path) for path in paths]
        columns = [capture[0] for capture in captures]
        sample_counts = [capture[1] for capture in captures]
        trigger_samples = [capture[2] for capture in captures]
        pc = reconstruct_from_net_map(columns[0], vector_maps["pc"], 64)
        ila0_trigger = reconstruct_from_net_map(
            columns[0], vector_maps["ila0_trigger"], 1
        )
        ila1 = reconstruct_from_net_map(columns[1], vector_maps["ila1"], 64)
        ila2 = reconstruct_from_net_map(columns[2], vector_maps["ila2"], 64)
        ila3 = reconstruct_from_net_map(columns[3], vector_maps["ila3"], 64)
        trigger_series = [
            ila0_trigger,
            [value & 1 for value in ila1],
            [(value >> 63) & 1 for value in ila2],
            [(value >> 63) & 1 for value in ila3],
        ]
        if args.snapshot:
            trigger = validate_snapshot_capture(trigger_series, trigger_samples)
        else:
            trigger = validate_synchronized_capture(trigger_series, trigger_samples)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    mepc = [value & ~1 for value in ila1]
    states = [decode_packed_state(value) for value in ila2]
    mtval = [value & ((1 << 63) - 1) for value in ila3]
    print("Build 80 synchronized trap capture:")
    print(f"  LTX: {ltx_path}")
    for path in paths:
        print(f"  {path}")
    print(f"  samples={sample_counts} trigger={trigger_samples}")
    edges = rising_edges(trigger_series[0])
    print(f"  S/U-to-M rising edges={len(edges)} samples={edges[:16]}")

    first = max(0, trigger - args.window)
    last = min(sample_counts[0] - 1, trigger + args.window)
    for index in range(first, last + 1):
        print(format_row(index, trigger, pc[index], mepc[index], mtval[index], states[index]))

    event = states[trigger]
    cause = event["mcause"] & 0x1FF
    interrupt = (event["mcause"] >> 63) & 1
    instruction = decode_csr_instruction(mtval[trigger] & 0xFFFFFFFF)
    print(
        "Trigger state: mepc=0x%016x mcause=%s:%d mtval=0x%08x"
        % (
            mepc[trigger],
            "interrupt" if interrupt else "exception",
            cause,
            instruction["instruction"],
        )
    )
    if instruction["is_ecall"]:
        matches = []
        print("  instruction=ECALL")
    elif instruction["is_csr"]:
        csr_name = CSR_NAMES.get(instruction["csr"], "unknown")
        print(
            "  instruction=%s x%d, csr=0x%03x(%s), x%d/zimm=%d"
            % (
                instruction["operation"],
                instruction["rd"],
                instruction["csr"],
                csr_name,
                instruction["rs1_or_zimm"],
                instruction["rs1_or_zimm"],
            )
        )
        matches = find_csr_match(states, instruction["csr"], trigger - 8, trigger + 2)
        print(f"  matching CSR-address samples near trigger: {matches}")
    else:
        matches = []
        print("  mtval does not decode as a CSR SYSTEM instruction")

    linux_mepc = linux_linked_address(mepc[trigger])
    if linux_mepc != mepc[trigger]:
        print(f"  Linux linked-address candidate: 0x{linux_mepc:016x}")
    if args.vmlinux:
        for text in csvutil.resolve_pc(linux_mepc, args.vmlinux):
            print(text)

    timeline = acknowledged_pc_timeline(pc, states, trigger, len(pc))
    print(f"Post-trigger acknowledged commit timeline ({len(timeline)} commits):")
    for index, commit_pc, gap in timeline:
        gap_text = "-" if gap is None else str(gap)
        print(
            f"  rel={index - trigger:+4d} sample={index:4d} "
            f"pc=0x{commit_pc:016x} cycles_since_ack={gap_text}"
        )
    firmware_timeline = [
        entry for entry in timeline if 0x80000000 <= entry[1] < 0x80200000
    ]
    if args.firmware_elf and firmware_timeline:
        endpoints = [firmware_timeline[0][1], firmware_timeline[-1][1]]
        for label, commit_pc in zip(("first", "last"), endpoints):
            print(f"Post-trigger {label} OpenSBI commit PC: 0x{commit_pc:016x}")
            for text in csvutil.resolve_pc(commit_pc, args.firmware_elf):
                print(text)

    same_traps = [
        index
        for index in edges
        if mepc[index] == mepc[trigger]
        and (mtval[index] & 0xFFFFFFFF) == instruction["instruction"]
    ]
    print(f"  matching mepc/mtval trap entries in capture: {same_traps}")

    pre_states = states[max(0, trigger - 4):trigger]
    s_mode_time_denied = (
        not interrupt
        and cause == 2
        and instruction["is_csr"]
        and instruction["csr"] == 0xC01
        and any(state["priv"] == 1 and not (state["mcounteren"] & 0x2) for state in pre_states)
        and bool(matches)
    )
    if s_mode_time_denied:
        print(
            "PASS: captured an S-mode read of CSR time (0xc01) entering an "
            "M-mode illegal-instruction trap while mcounteren.TM=0"
        )
        if len(same_traps) > 1:
            print("PASS: the same mepc/mtval trap repeats within one synchronized window")
        else:
            print("NOTE: this window contains only one matching trap entry")
        return 0

    s_mode_ecall = is_s_mode_ecall(
        interrupt, cause, instruction, pre_states
    )
    if s_mode_ecall:
        print("PASS: captured a normal S-mode ECALL entering the OpenSBI trap handler")
        print(
            "NOTE: this ILA does not capture a7/a6; identify the SBI extension and "
            "function from an exact Linux ELF or a follow-up register capture"
        )
        return 0

    print("INCONCLUSIVE: capture does not satisfy the complete S-mode rdtime denial signature")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
