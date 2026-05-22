#!/usr/bin/env python3
"""Small cross-shell helpers for the project Makefile."""

from __future__ import annotations

import argparse
import fnmatch
import os
import shutil
import sys
from pathlib import Path


ROOT_SIDE_EFFECTS = (".Xil", "NA", "dfx_runtime.txt")
ROOT_CLEAN_PATTERNS = (
    "vivado*.log",
    "vivado*.jou",
    "vivado_*.backup.*",
    "*.log",
    "*.jou",
    "*.pb",
    "*.wdb",
    "*.vcd",
    "dfx_runtime.txt",
)


def remove_path(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path, onerror=force_remove)
    else:
        unlink_file(path)


def force_remove(func, path: str, exc_info) -> None:
    try:
        os.chmod(path, 0o700)
        func(path)
    except FileNotFoundError:
        pass
    except Exception:
        raise exc_info[1]


def unlink_file(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass
    except PermissionError:
        os.chmod(path, 0o700)
        path.unlink()


def mkdir(args: argparse.Namespace) -> int:
    for path in args.paths:
        Path(path).mkdir(parents=True, exist_ok=True)
    return 0


def collect_root_side_effects(args: argparse.Namespace) -> int:
    dest = Path(args.dest)
    dest.mkdir(parents=True, exist_ok=True)
    for name in ROOT_SIDE_EFFECTS:
        source = Path(name)
        if not source.exists():
            continue
        target = dest / name
        remove_path(target)
        shutil.move(str(source), str(dest))
    return 0


def remove_paths(args: argparse.Namespace) -> int:
    for path in args.paths:
        remove_path(Path(path))
    return 0


def clean_root_files(_: argparse.Namespace) -> int:
    for path in Path.cwd().iterdir():
        if not path.is_file():
            continue
        if any(fnmatch.fnmatchcase(path.name, pattern) for pattern in ROOT_CLEAN_PATTERNS):
            unlink_file(path)
    return 0


def import_serial():
    try:
        import serial
        from serial.tools import list_ports
    except ImportError:
        print(
            "pyserial is required for serial logging. Install it with "
            "`python -m pip install -r requirements-regs.txt`.",
            file=sys.stderr,
        )
        return None, None
    return serial, list_ports


def port_description(port) -> str:
    parts = [port.device]
    if port.description and port.description != "n/a":
        parts.append(port.description)
    details = []
    if port.manufacturer:
        details.append(port.manufacturer)
    if port.product:
        details.append(port.product)
    if port.vid is not None and port.pid is not None:
        details.append(f"VID:PID={port.vid:04X}:{port.pid:04X}")
    if details:
        parts.append(f"({', '.join(details)})")
    return " ".join(parts)


def score_port(port) -> int:
    haystack = " ".join(
        str(value or "")
        for value in (
            port.device,
            port.name,
            port.description,
            port.hwid,
            port.manufacturer,
            port.product,
            port.interface,
        )
    ).lower()

    score = 0
    for token in ("pynq", "digilent", "xilinx", "usb-serial controller d"):
        if token in haystack:
            score += 100
    for token in ("ftdi", "future technology"):
        if token in haystack:
            score += 50
    for token in ("usb uart", "usb-uart", "usb serial", "usb-serial", "uart bridge"):
        if token in haystack:
            score += 20
    return score


def list_detected_ports():
    _, list_ports = import_serial()
    if list_ports is None:
        return None
    return list(list_ports.comports())


def choose_port(explicit_port: str) -> str | None:
    if explicit_port:
        return explicit_port

    ports = list_detected_ports()
    if ports is None:
        return None

    if not ports:
        print("No serial ports detected. Re-run with PORT=<port> after connecting the board.", file=sys.stderr)
        return None

    if len(ports) == 1:
        port = ports[0]
        print(f"Selected serial port {port_description(port)}")
        return port.device

    scored = [(score_port(port), port) for port in ports]
    best_score = max(score for score, _ in scored)
    best = [port for score, port in scored if score == best_score and score > 0]
    if len(best) == 1:
        port = best[0]
        print(f"Selected serial port {port_description(port)}")
        return port.device

    print("Multiple serial ports detected; choose one explicitly with PORT=<port>:", file=sys.stderr)
    for score, port in sorted(scored, key=lambda item: (item[0], item[1].device), reverse=True):
        print(f"  {port_description(port)} score={score}", file=sys.stderr)
    return None


def logs(args: argparse.Namespace) -> int:
    serial, _ = import_serial()
    if serial is None:
        return 2

    port = choose_port(args.port.strip())
    if not port:
        return 2

    ser = serial.Serial()
    ser.port = port
    ser.baudrate = args.baud
    ser.bytesize = serial.EIGHTBITS
    ser.parity = serial.PARITY_NONE
    ser.stopbits = serial.STOPBITS_ONE
    ser.timeout = 0.2
    ser.xonxoff = False
    ser.rtscts = False
    ser.dsrdtr = False
    ser.dtr = False
    ser.rts = False

    try:
        try:
            ser.open()
        except serial.SerialException as exc:
            print(f"Could not open serial port {port}: {exc}", file=sys.stderr)
            return 2
        print(f"Streaming {port} at {args.baud} baud. Press Ctrl+C to stop.")
        while True:
            line = ser.readline()
            if line:
                print(line.decode(errors="replace").rstrip("\n").rstrip("\r"))
    except KeyboardInterrupt:
        return 130
    finally:
        if ser.is_open:
            ser.close()
    return 0


def list_serial_ports(_: argparse.Namespace) -> int:
    ports = list_detected_ports()
    if ports is None:
        return 2
    if not ports:
        print("No serial ports detected.")
        return 0
    for port in ports:
        print(port_description(port))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    mkdir_parser = subparsers.add_parser("mkdir", help="create directories")
    mkdir_parser.add_argument("paths", nargs="+")
    mkdir_parser.set_defaults(func=mkdir)

    collect_parser = subparsers.add_parser(
        "collect-root-side-effects",
        help="move root Xilinx side-effect files into a destination directory",
    )
    collect_parser.add_argument("dest")
    collect_parser.set_defaults(func=collect_root_side_effects)

    remove_parser = subparsers.add_parser("remove-paths", help="delete files or directories if present")
    remove_parser.add_argument("paths", nargs="+")
    remove_parser.set_defaults(func=remove_paths)

    clean_parser = subparsers.add_parser("clean-root-files", help="delete known root log/journal clutter")
    clean_parser.set_defaults(func=clean_root_files)

    logs_parser = subparsers.add_parser("logs", help="stream serial telemetry")
    logs_parser.add_argument("--port", default="")
    logs_parser.add_argument("--baud", type=int, default=115200)
    logs_parser.set_defaults(func=logs)

    list_parser = subparsers.add_parser("list-serial-ports", help="list detected serial ports")
    list_parser.set_defaults(func=list_serial_ports)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
