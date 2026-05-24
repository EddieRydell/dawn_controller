#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
from pathlib import Path
import subprocess
import sys
import time

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ps.tools.generated import pl_config


def run_logged(command: list[str], log_path: Path, env: dict[str, str] | None = None) -> None:
    print(f"run: {' '.join(command)}", flush=True)
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        process = subprocess.run(
            command,
            cwd=REPO_ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        log.write(process.stdout)
    if process.returncode != 0:
        raise RuntimeError(f"Command failed ({process.returncode}): {' '.join(command)}")


def newest_dir(glob_pattern: str, after: float) -> Path:
    candidates = [
        path for path in (REPO_ROOT / "build" / "bench").glob(glob_pattern)
        if path.is_dir() and path.stat().st_mtime >= after
    ]
    if not candidates:
        raise RuntimeError(f"No artifact directory matched {glob_pattern}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def newest_benchmark_dir(after: float) -> Path:
    candidates = []
    for path in (REPO_ROOT / "build" / "bench").glob("20*"):
        if not path.is_dir() or path.stat().st_mtime < after:
            continue
        if len(path.name) == 15 and path.name[8] == "-":
            candidates.append(path)
    if not candidates:
        raise RuntimeError("No benchmark artifact directory found")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def as_float(row: dict[str, str], key: str) -> float:
    try:
        return float(row.get(key, "") or 0.0)
    except ValueError:
        return 0.0


def as_int(row: dict[str, str], key: str) -> int:
    try:
        return int(float(row.get(key, "") or 0))
    except ValueError:
        return 0


def ws281x_max_fps(pixels: int) -> float:
    return 1_000_000.0 / ((pixels * 30.0) + 50.0)


def link(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def write_report(
    report_path: Path,
    out_dir: Path,
    ingress_dir: Path,
    ceiling_dir: Path,
    duration: float,
) -> None:
    ingress_rows = read_rows(ingress_dir / "results.csv")
    ceiling_rows = read_rows(ceiling_dir / "results.csv")
    stable_rows = [
        row for row in ingress_rows + ceiling_rows
        if row.get("classification") in ("pass", "stable")
    ]
    best = max(stable_rows, key=lambda row: as_float(row, "packet_rate"), default={})

    with report_path.open("w", encoding="utf-8") as f:
        f.write("# E1.31 Ingress Profile Results\n\n")
        f.write(f"Generated: {dt.datetime.now().isoformat(timespec='seconds')}\n\n")
        f.write("## Summary\n\n")
        if best:
            f.write(
                "Best observed stable end-to-end ingress: "
                f"`{as_float(best, 'packet_rate'):.2f} packets/sec` "
                f"at `{best.get('outputs', str(pl_config.DEFAULT_ACTIVE_OUTPUT_COUNT))}x{best.get('pixels_per_output')} @ {best.get('target_fps')} FPS`.\n\n"
            )
        f.write(
            "Pass criteria: committed FPS at least 99% of target with zero pbuf allocation failures, "
            "RX ring drops, E1.31 rejects, sequence anomalies, PL drops/rejects, and consumer errors.\n\n"
        )
        f.write("## Artifacts\n\n")
        f.write(f"- Run directory: `{link(out_dir)}`\n")
        f.write(f"- Coarse ingress profile: `{link(ingress_dir / 'results.csv')}`\n")
        f.write(f"- Ceiling sweep: `{link(ceiling_dir / 'results.csv')}`\n")
        f.write(f"- Host test log: `{link(out_dir / 'host_tests.log')}`\n")
        f.write(f"- Python compile log: `{link(out_dir / 'py_compile.log')}`\n\n")

        f.write("## Coarse Profile\n\n")
        f.write("| candidate | cell | committed FPS | packet rate | class | pbuf | ring | seq | PL drops |\n")
        f.write("| --- | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |\n")
        for row in ingress_rows:
            if row.get("classification") == "unsupported":
                f.write(f"| {row.get('candidate')} | build |  |  | unsupported |  |  |  |  |\n")
                continue
            cell = f"{row.get('outputs', str(pl_config.DEFAULT_ACTIVE_OUTPUT_COUNT))}x{row.get('pixels_per_output')} @ {row.get('target_fps')}"
            f.write(
                f"| {row.get('candidate', '')} | {cell} | {as_float(row, 'committed_fps'):.2f} | "
                f"{as_float(row, 'packet_rate'):.2f} | {row.get('classification', '')} | "
                f"{as_int(row, 'rx_delta_rx_pbuf_alloc_failures')} | "
                f"{as_int(row, 'rx_delta_rx_ring_dropped')} | "
                f"{as_int(row, 'rx_delta_sequence_anomalies')} | "
                f"{as_int(row, 'rx_delta_pl_dropped')} |\n"
            )

        f.write("\n## Ceiling Sweep\n\n")
        f.write("| cell | committed FPS | packet rate | class | pbuf | seq | PL drops |\n")
        f.write("| --- | ---: | ---: | --- | ---: | ---: | ---: |\n")
        for row in ceiling_rows:
            cell = f"{row.get('outputs', str(pl_config.DEFAULT_ACTIVE_OUTPUT_COUNT))}x{row.get('pixels_per_output')} @ {row.get('target_fps')}"
            f.write(
                f"| {cell} | {as_float(row, 'committed_fps'):.2f} | "
                f"{as_float(row, 'packet_rate'):.2f} | {row.get('classification', '')} | "
                f"{as_int(row, 'rx_delta_rx_pbuf_alloc_failures')} | "
                f"{as_int(row, 'rx_delta_sequence_anomalies')} | "
                f"{as_int(row, 'rx_delta_pl_dropped')} |\n"
            )

        f.write("\n## WS281x Protocol Limits\n\n")
        f.write("Assumes 1250 ns per bit, 24 bits per RGB pixel, and 50 us reset/latch time.\n\n")
        f.write("| pixels/output | protocol max FPS | notes |\n")
        f.write("| ---: | ---: | --- |\n")
        for pixels in (300, 500, 1024):
            notes = ""
            if pixels == 500:
                notes = "60 FPS has margin; 64-65 FPS is near the hard limit."
            elif pixels == 1024:
                notes = "30 FPS is near the hard limit."
            f.write(f"| {pixels} | {ws281x_max_fps(pixels):.2f} | {notes} |\n")

        f.write("\n## Command\n\n")
        f.write("```sh\n")
        f.write(f"make e131-profile-report E131_PROFILE_DURATION={duration:g}\n")
        f.write("```\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run E1.31 checks/profile and write a root-level Markdown report.")
    parser.add_argument("--serial-port", default="")
    parser.add_argument("--baud", type=int, default=pl_config.UART_BAUD)
    parser.add_argument("--duration", type=float, default=10.0)
    parser.add_argument("--report", default="E131_PROFILE_RESULTS.md")
    parser.add_argument("--ceiling-rates", type=float, nargs="*", default=[61.0, 62.0, 63.0, 64.0, 65.0])
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = REPO_ROOT / "build" / "bench" / f"{timestamp}-e131-profile-report"
    out_dir.mkdir(parents=True, exist_ok=True)

    run_logged(["make", "ps-host-test"], out_dir / "host_tests.log")
    run_logged(
        [
            sys.executable,
            "-m",
            "py_compile",
            "ps/tools/e131_send.py",
            "ps/tools/e131_benchmark.py",
            "ps/tools/e131_ingress_profile.py",
            "ps/tools/e131_profile_report.py",
            "ps/scripts/create_app_vitis.py",
        ],
        out_dir / "py_compile.log",
    )

    ingress_start = time.time()
    run_logged(
        [
            sys.executable,
            "ps/tools/e131_ingress_profile.py",
            "--serial-port",
            args.serial_port,
            "--baud",
            str(args.baud),
            "--duration",
            str(args.duration),
        ],
        out_dir / "ingress_profile.log",
    )
    ingress_dir = newest_dir("*-ingress-profile", ingress_start)

    stamp = REPO_ROOT / "build" / "vitis" / ".app-built"
    if stamp.exists():
        stamp.unlink()
    run_logged(["make", "ps"], out_dir / "default_make_ps.log")

    ceiling_start = time.time()
    run_logged(
        [
            sys.executable,
            "ps/tools/e131_benchmark.py",
            "--skip-build",
            "--skip-sanity-cell",
            "--serial-port",
            args.serial_port,
            "--baud",
            str(args.baud),
            "--duration",
            str(args.duration),
            "--pixels",
            "500",
            "--rates",
            *[f"{rate:g}" for rate in args.ceiling_rates],
        ],
        out_dir / "ceiling_sweep.log",
    )
    ceiling_dir = newest_benchmark_dir(ceiling_start)

    report_path = REPO_ROOT / args.report
    write_report(report_path, out_dir, ingress_dir, ceiling_dir, args.duration)
    print(f"wrote {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
