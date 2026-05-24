#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import math
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import make_helpers
from ps.tools.generated import pl_config


MATRIX = {
    50: (30, 60, 120, 240, 480),
    100: (30, 60, 120, 240, 360),
    300: (30, 60, 90, 110, 130),
    500: (30, 50, 60, 70, 90),
    750: (20, 30, 40, 50),
    1024: (20, 25, 30, 35, 40),
}

STATUS_KEYS = (
    "rx_packets",
    "rx_bytes",
    "rx_oversized",
    "rx_ring_depth",
    "rx_ring_high_water",
    "rx_ring_dropped",
    "rx_ring_processed",
    "rx_pbuf_alloc_failures",
    "rx_pbuf_pool_used",
    "rx_pbuf_pool_max",
    "rx_pbuf_pool_avail",
    "rx_input_calls",
    "rx_input_active_calls",
    "rx_input_max_packets",
    "rx_poll_max_drained",
    "rx_poll_budget_hits",
    "e131_valid",
    "e131_rejected",
    "frames_committed",
    "frames_dropped",
    "complete_frames",
    "incomplete_sweeps",
    "sequence_anomalies",
    "blackouts",
    "packet_gap_ms",
    "max_packet_gap_ms",
    "commit_gap_ms",
    "max_commit_gap_ms",
    "ps_write_last_us",
    "ps_write_max_us",
    "ps_write_active_words",
    "ps_write_required_words",
    "ps_no_free_bank_waits",
    "ps_no_free_bank_drops",
    "pl_dropped",
    "pl_rejected",
    "consumer_frames",
    "consumer_errors",
    "pl_frame_count",
    "pl_committed_words",
    "pl_error_count",
    "pl_status",
    "consumer_status",
    "config_status",
)


def parse_kv_line(line: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for key, value in re.findall(r"([A-Za-z0-9_]+)=([^ \r\n]+)", line):
        result[key] = value
    return result


def number(value: str | None) -> int | float | str:
    if value is None:
        return ""
    if value.startswith("0x"):
        return int(value, 16)
    try:
        return int(value)
    except ValueError:
        try:
            return float(value)
        except ValueError:
            return value


def numeric_status(status: dict[str, str]) -> dict[str, int | float | str]:
    return {key: number(status.get(key)) for key in STATUS_KEYS}


def diff_status(before: dict[str, str], after: dict[str, str]) -> dict[str, int | float | str]:
    diff: dict[str, int | float | str] = {}
    for key in STATUS_KEYS:
        a = number(after.get(key))
        b = number(before.get(key))
        if isinstance(a, (int, float)) and isinstance(b, (int, float)):
            diff[f"rx_delta_{key}"] = a - b
        else:
            diff[f"rx_after_{key}"] = a
    return diff


def classify(row: dict[str, int | float | str]) -> str:
    target = float(row["target_fps"])
    committed = float(row.get("rx_delta_frames_committed", 0))
    duration = float(row.get("actual_duration", 0))
    achieved = committed / duration if duration > 0 else 0.0
    row["committed_fps"] = achieved
    hard_errors = (
        "rx_delta_e131_rejected",
        "rx_delta_rx_oversized",
        "rx_delta_rx_ring_dropped",
        "rx_delta_rx_pbuf_alloc_failures",
        "rx_delta_frames_dropped",
        "rx_delta_incomplete_sweeps",
        "rx_delta_sequence_anomalies",
        "rx_delta_pl_dropped",
        "rx_delta_pl_rejected",
        "rx_delta_consumer_errors",
    )
    errors = sum(int(row.get(key, 0) or 0) for key in hard_errors)
    if errors == 0 and achieved >= target * 0.99:
        return "stable"
    if achieved >= target * 0.95 and errors <= 1:
        return "marginal"
    return "broken"


def infer_bottleneck(row: dict[str, int | float | str]) -> str:
    target = float(row["target_fps"])
    pixels = int(row["pixels_per_output"])
    theoretical_led_fps = 1000000.0 / ((pixels * 30.0) + 50.0)
    row["theoretical_led_fps"] = theoretical_led_fps
    if row.get("classification") != "broken":
        return "none_observed"
    write_max_us = float(row.get("rx_delta_ps_write_max_us", 0) or row.get("after_ps_write_max_us", 0) or 0)
    frame_interval_us = 1000000.0 / target if target > 0 else 0.0
    incomplete = int(row.get("rx_delta_incomplete_sweeps", 0) or 0)
    sequence = int(row.get("rx_delta_sequence_anomalies", 0) or 0)
    pl_dropped = int(row.get("rx_delta_pl_dropped", 0) or 0)
    if target <= theoretical_led_fps and (write_max_us > frame_interval_us * 0.25 or incomplete > 0 or sequence > 0):
        return "dma_likely_needed"
    if target > theoretical_led_fps or pl_dropped > 0:
        return "not_dma_limited"
    return "undetermined"


class SerialCapture:
    def __init__(self, port: str, baud: int, log_path: Path):
        self.port = port
        self.baud = baud
        self.log_path = log_path
        self.lines: list[str] = []
        self._queue: queue.Queue[str] = queue.Queue()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._serial = None

    def start(self) -> None:
        serial_mod, _ = make_helpers.import_serial()
        if serial_mod is None:
            raise RuntimeError("pyserial is required for benchmark UART capture")
        candidates = make_helpers.candidate_ports(self.port.strip())
        if candidates is None or not candidates:
            raise RuntimeError("No serial port available for benchmark UART capture")
        errors = []
        for port, description, explicit in candidates:
            try:
                if description != port:
                    print(f"Opening {description}", flush=True)
                self._serial = make_helpers.open_serial_port(serial_mod, port, self.baud)
                self.port = self._serial.port
                break
            except serial_mod.SerialException as exc:
                errors.append((port, exc))
                if explicit:
                    raise RuntimeError(f"Could not open serial port {port}: {exc}") from exc
                print(f"Could not open serial port {port}: {exc}", file=sys.stderr, flush=True)
        if self._serial is None:
            detail = "; ".join(f"{port}: {exc}" for port, exc in errors)
            raise RuntimeError(f"No auto-detected serial port could be opened. {detail}")
        self._thread = threading.Thread(target=self._reader, daemon=True)
        self._thread.start()

    def _reader(self) -> None:
        assert self._serial is not None
        with self.log_path.open("a", encoding="utf-8", errors="replace") as log:
            while not self._stop.is_set():
                raw = self._serial.readline()
                if not raw:
                    continue
                line = raw.decode(errors="replace").rstrip("\r\n")
                self.lines.append(line)
                self._queue.put(line)
                log.write(line + "\n")
                log.flush()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=1.0)
        if self._serial is not None and self._serial.is_open:
            self._serial.close()

    def drain_pending(self) -> None:
        while True:
            try:
                self._queue.get_nowait()
            except queue.Empty:
                return

    def wait_for(self, pattern: str, timeout: float, start_index: int = 0) -> str:
        deadline = time.monotonic() + timeout
        compiled = re.compile(pattern)
        for line in self.lines[start_index:]:
            if compiled.search(line):
                return line
        while time.monotonic() < deadline:
            try:
                line = self._queue.get(timeout=0.2)
            except queue.Empty:
                continue
            if compiled.search(line):
                return line
        raise TimeoutError(f"Timed out waiting for UART pattern: {pattern}")

    def latest_status(self, start_index: int = 0) -> dict[str, str]:
        for line in reversed(self.lines[start_index:]):
            if line.startswith("e131_status "):
                return parse_kv_line(line)
        return {}

    def wait_for_status_counter(self, key: str, minimum: int, timeout: float, start_index: int = 0) -> dict[str, str]:
        deadline = time.monotonic() + timeout
        latest = self.latest_status(start_index)
        while time.monotonic() < deadline:
            value = number(latest.get(key)) if latest else ""
            if isinstance(value, int) and value >= minimum:
                return latest
            try:
                line = self._queue.get(timeout=0.2)
            except queue.Empty:
                latest = self.latest_status(start_index)
                continue
            if line.startswith("e131_status "):
                latest = parse_kv_line(line)
        return self.latest_status(start_index) or latest


def run_checked(command: list[str], log_path: Path) -> None:
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        process = subprocess.run(
            command,
            cwd=REPO_ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        log.write(process.stdout)
    if process.returncode != 0:
        raise RuntimeError(f"Command failed ({process.returncode}): {' '.join(command)}")


def parse_snapshot_log(log_path: Path) -> dict[str, int | str]:
    snapshot: dict[str, int | str] = {}
    if not log_path.exists():
        return snapshot
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        for key, value in parse_kv_line(line).items():
            snapshot[f"jtag_{key}"] = number(value)
    return snapshot


def run_json(command: list[str], log_path: Path) -> dict[str, int | float | str]:
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        process = subprocess.run(
            command,
            cwd=REPO_ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        log.write(process.stdout)
    if process.returncode != 0:
        raise RuntimeError(f"Command failed ({process.returncode}): {' '.join(command)}")
    for line in reversed(process.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise RuntimeError(f"No JSON result from sender: {' '.join(command)}")


def write_summary(out_dir: Path, rows: list[dict[str, int | float | str]]) -> None:
    summary = out_dir / "summary.md"
    with summary.open("w", encoding="utf-8") as f:
        f.write("# E1.31 30-Output Throughput Benchmark\n\n")
        f.write(f"Generated: {dt.datetime.now().isoformat(timespec='seconds')}\n\n")
        f.write("| pixels/output | target fps | committed fps | classification | bottleneck | notes |\n")
        f.write("| ---: | ---: | ---: | --- | --- | --- |\n")
        for row in rows:
            notes = []
            if int(row.get("rx_delta_frames_dropped", 0) or 0):
                notes.append(f"drops={row['rx_delta_frames_dropped']}")
            if int(row.get("rx_delta_rx_ring_dropped", 0) or 0):
                notes.append(f"ring_drops={row['rx_delta_rx_ring_dropped']}")
            if int(row.get("rx_delta_rx_pbuf_alloc_failures", 0) or 0):
                notes.append(f"pbuf_alloc={row['rx_delta_rx_pbuf_alloc_failures']}")
            if int(row.get("rx_delta_e131_rejected", 0) or 0):
                notes.append(f"rejects={row['rx_delta_e131_rejected']}")
            if int(row.get("rx_delta_sequence_anomalies", 0) or 0):
                notes.append(f"seq={row['rx_delta_sequence_anomalies']}")
            f.write(
                f"| {row['pixels_per_output']} | {row['target_fps']} | "
                f"{float(row.get('committed_fps', 0.0)):.2f} | {row['classification']} | {row.get('bottleneck', '')} | "
                f"{', '.join(notes)} |\n"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the 30-output E1.31 throughput benchmark on PYNQ-Z2.")
    parser.add_argument("--source-ip", default=pl_config.HOST_IP_STRING)
    parser.add_argument("--dest-ip", default=pl_config.BOARD_IP_STRING)
    parser.add_argument("--port", type=int, default=pl_config.E131_PORT)
    parser.add_argument("--serial-port", default="")
    parser.add_argument("--baud", type=int, default=pl_config.UART_BAUD)
    parser.add_argument("--duration", type=float, default=20.0)
    parser.add_argument("--outputs", type=int, default=pl_config.DEFAULT_ACTIVE_OUTPUT_COUNT)
    parser.add_argument("--pixels", type=int, nargs="*", default=[])
    parser.add_argument("--rates", type=float, nargs="*", default=[])
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--sanity-only", action="store_true")
    parser.add_argument("--skip-sanity-cell", action="store_true", help="Do not prepend the 30x50 @ 30 FPS sanity cell.")
    args = parser.parse_args()

    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = REPO_ROOT / "build" / "bench" / timestamp
    out_dir.mkdir(parents=True, exist_ok=True)

    if not args.skip_build:
        run_checked(["make", "ps"], out_dir / "make_ps.log")

    cells: list[tuple[int, float]] = [] if args.skip_sanity_cell else [(50, 30.0)]
    if not args.sanity_only:
        selected_pixels = args.pixels or list(MATRIX.keys())
        for pixels in selected_pixels:
            rates = args.rates or MATRIX[pixels]
            for rate in rates:
                if (pixels, float(rate)) != (50, 30.0):
                    cells.append((pixels, float(rate)))

    rows: list[dict[str, int | float | str]] = []
    results_csv = out_dir / "results.csv"
    uart_log = out_dir / "uart.log"

    capture = SerialCapture(args.serial_port, args.baud, uart_log)
    capture.start()
    try:
        for index, (pixels, rate) in enumerate(cells):
            cell_name = f"{index:02d}_{args.outputs}x{pixels}_{rate:g}fps"
            total_pixels = args.outputs * pixels
            universe_count = math.ceil((total_pixels * 3) / pl_config.E131_SLOTS_PER_UNIVERSE)
            uart_start = len(capture.lines)
            capture.drain_pending()
            print(
                f"{cell_name}: programming active_outputs={args.outputs} "
                f"pixels_per_output={pixels} universes={universe_count}",
                flush=True,
            )

            run_checked(
                [
                    sys.executable,
                    "ps/scripts/run_xsdb_checked.py",
                    "ps/scripts/run_controller.tcl",
                    "--active-outputs",
                    str(args.outputs),
                    "--pixels-per-output",
                    str(pixels),
                ],
                out_dir / f"{cell_name}_jtag_run.log",
            )
            config_line = capture.wait_for(
                rf"strand_config active_outputs={args.outputs} .*total_pixels={total_pixels} .*expected_universes={universe_count}",
                20.0,
                start_index=uart_start,
            )
            cell_status_start = max(0, len(capture.lines) - 1)
            before_line = capture.wait_for(r"^e131_status .*rx_packets=0 ", 8.0, start_index=cell_status_start)
            before = parse_kv_line(before_line)
            capture.drain_pending()
            print(f"{cell_name}: sending {args.duration:g}s at target_fps={rate:g}", flush=True)
            sender = run_json(
                [
                    sys.executable,
                    "ps/tools/e131_send.py",
                    "--source-ip",
                    args.source_ip,
                    "--dest-ip",
                    args.dest_ip,
                    "--port",
                    str(args.port),
                    "--outputs",
                    str(args.outputs),
                    "--pixels-per-output",
                    str(pixels),
                    "--duration",
                    str(args.duration),
                    "--rate",
                    str(rate),
                    "--json",
                ],
                out_dir / f"{cell_name}_sender.log",
            )
            before_packets = number(before.get("rx_packets"))
            expected_packets = int(before_packets if isinstance(before_packets, int) else 0) + int(sender["packets_sent"])
            after = capture.wait_for_status_counter("rx_packets", expected_packets, 2.5, start_index=cell_status_start)
            snapshot_log = out_dir / f"{cell_name}_jtag_snapshot.log"
            run_checked([sys.executable, "ps/scripts/run_xsdb_checked.py", "ps/scripts/pl_snapshot.tcl"], snapshot_log)

            row: dict[str, int | float | str] = {
                "cell": cell_name,
                "configured_line": config_line,
                "outputs": args.outputs,
                "pixels_per_output": pixels,
                "total_pixels": total_pixels,
                "universe_count": universe_count,
                **sender,
                **diff_status(before, after),
                **{f"after_{key}": value for key, value in numeric_status(after).items()},
                **parse_snapshot_log(snapshot_log),
            }
            row["classification"] = classify(row)
            row["bottleneck"] = infer_bottleneck(row)
            rows.append(row)

            fieldnames = sorted({key for result in rows for key in result.keys()})
            with results_csv.open("w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(rows)
            write_summary(out_dir, rows)
            print(
                f"{cell_name}: {row['classification']} "
                f"committed_fps={float(row['committed_fps']):.2f} "
                f"drops={row.get('rx_delta_frames_dropped', 0)} "
                f"rejects={row.get('rx_delta_e131_rejected', 0)} "
                f"seq={row.get('rx_delta_sequence_anomalies', 0)}",
                flush=True,
            )
    finally:
        capture.stop()

    print(f"wrote {results_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
