import argparse
import filecmp
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
RDL = REPO_ROOT / "hw" / "regs" / "pl_control.rdl"
PS_HEADER = REPO_ROOT / "ps" / "app" / "pl_control.h"
RTL_DIR = REPO_ROOT / "hw" / "rtl" / "generated"
DOCS_DIR = REPO_ROOT / "build" / "docs" / "regs" / "pl_control"


def run(cmd):
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def generate(out_root, include_docs=True):
    out_root.mkdir(parents=True, exist_ok=True)
    ps_header = out_root / "ps" / "app" / "pl_control.h"
    rtl_dir = out_root / "hw" / "rtl" / "generated"
    ps_header.parent.mkdir(parents=True, exist_ok=True)
    rtl_dir.mkdir(parents=True, exist_ok=True)

    run(["peakrdl", "c-header", "-o", str(ps_header), str(RDL)])
    run([
        "peakrdl",
        "regblock",
        "--cpuif",
        "axi4-lite-flat",
        "--addr-width",
        "12",
        "--default-reset",
        "rst_n",
        "--module-name",
        "pl_control_regs",
        "-o",
        str(rtl_dir),
        str(RDL),
    ])
    for sv in rtl_dir.glob("*.sv"):
        text = sv.read_text()
        if not text.startswith("`timescale"):
            sv.write_text("`timescale 1ns / 1ps\n" + text, newline="")
    if not include_docs:
        return

    docs_dir = out_root / "docs" / "regs" / "pl_control"
    docs_dir.parent.mkdir(parents=True, exist_ok=True)
    run([
        "peakrdl",
        "html",
        "-o",
        str(docs_dir),
        "--title",
        "Donder Controller PL Control Registers",
        str(RDL),
    ])
    index_html = docs_dir / "index.html"
    index_html.write_text(
        re.sub(r"BUILD_TS = \d+|ts=\d+", lambda m: "BUILD_TS = 0" if m.group(0).startswith("BUILD_TS") else "ts=0", index_html.read_text()),
        newline="",
    )


def copy_generated(src_root):
    shutil.copy2(src_root / "ps" / "app" / "pl_control.h", PS_HEADER)
    RTL_DIR.mkdir(parents=True, exist_ok=True)
    for path in RTL_DIR.glob("*"):
        if path.is_file():
            path.unlink()
    for path in (src_root / "hw" / "rtl" / "generated").glob("*"):
        shutil.copy2(path, RTL_DIR / path.name)
    if DOCS_DIR.exists():
        shutil.rmtree(DOCS_DIR)
    DOCS_DIR.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src_root / "docs" / "regs" / "pl_control", DOCS_DIR)


def compare_dirs(expected, actual):
    if not actual.exists():
        return [str(actual.relative_to(REPO_ROOT))]

    differences = []
    cmp = filecmp.dircmp(expected, actual)
    for name in cmp.left_only:
        differences.append(str((actual / name).relative_to(REPO_ROOT)))
    for name in cmp.right_only:
        differences.append(str((actual / name).relative_to(REPO_ROOT)))
    for name in cmp.diff_files:
        differences.append(str((actual / name).relative_to(REPO_ROOT)))
    for name, subcmp in cmp.subdirs.items():
        differences.extend(compare_dirs(expected / name, actual / name))
    return differences


def check_generated(src_root):
    differences = []
    if not PS_HEADER.exists() or not filecmp.cmp(src_root / "ps" / "app" / "pl_control.h", PS_HEADER, shallow=False):
        differences.append(str(PS_HEADER.relative_to(REPO_ROOT)))
    differences.extend(compare_dirs(src_root / "hw" / "rtl" / "generated", RTL_DIR))
    return differences


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.check:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            generate(tmp_root, include_docs=False)
            differences = check_generated(tmp_root)
            if differences:
                print("Generated register artifacts are stale:", file=sys.stderr)
                for path in differences:
                    print(f"  {path}", file=sys.stderr)
                return 1
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        tmp_root = Path(tmp)
        generate(tmp_root)
        copy_generated(tmp_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
