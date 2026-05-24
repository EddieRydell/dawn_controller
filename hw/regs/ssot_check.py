#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ALLOWED_PREFIXES = (
    "hw/regs/pl_control.rdl",
    "hw/regs/ssot_check.py",
    "ps/app/generated/",
    "ps/tools/generated/",
    "hw/scripts/generated/",
    "hw/rtl/generated/",
    "build/",
    "third_party/",
)

LITERAL_PATTERNS = (
    re.compile(r"192\.168\.7\.[12]"),
    re.compile(r"\b5568\b"),
    re.compile(r"\b63999\b"),
    re.compile(r"\b115200\b"),
    re.compile(r"\b3121\b"),
    re.compile(r"\b638u?\b"),
)

SUSPICIOUS_PATTERNS = (
    re.compile(r"env_int\([^,\n]+,\s*(?:0x[0-9a-fA-F]+|\d+)"),
    re.compile(r"add_argument\(\"--(?:source-ip|dest-ip|port|first-universe|outputs|pixels-per-output|baud)\"[^\n]*default=(?:\"[^\"]+\"|\d+)"),
    re.compile(r"#\s*define\s+(?:DAWN_)?DEFAULT_[A-Z0-9_]+\s+(?:0x[0-9a-fA-F]+|\d+)"),
    re.compile(r"#\s*define\s+RX_PACKET_RING_(?:DEPTH|PAYLOAD_BYTES)\s+(?:0x[0-9a-fA-F]+|\d+)"),
)


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return [REPO_ROOT / line for line in result.stdout.splitlines() if line]


def is_allowed(path: Path) -> bool:
    rel = path.relative_to(REPO_ROOT).as_posix()
    return any(rel == prefix or rel.startswith(prefix) for prefix in ALLOWED_PREFIXES)


def text_lines(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return []


def main() -> int:
    findings: list[str] = []
    for path in tracked_files():
        if is_allowed(path):
            continue
        rel = path.relative_to(REPO_ROOT).as_posix()
        for line_no, line in enumerate(text_lines(path), start=1):
            for pattern in LITERAL_PATTERNS:
                if pattern.search(line):
                    findings.append(f"{rel}:{line_no}: contract literal matched {pattern.pattern}: {line.strip()}")
            for pattern in SUSPICIOUS_PATTERNS:
                if pattern.search(line):
                    findings.append(f"{rel}:{line_no}: suspicious fallback/default matched {pattern.pattern}: {line.strip()}")

    if findings:
        print("SSOT contract check failed:", file=sys.stderr)
        for finding in findings:
            print(f"  {finding}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
