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
PS_CONFIG_HEADER = REPO_ROOT / "ps" / "app" / "generated" / "pl_config.h"
PY_CONFIG = REPO_ROOT / "ps" / "tools" / "generated" / "pl_config.py"
RTL_DIR = REPO_ROOT / "hw" / "rtl" / "generated"
RTL_CONFIG = RTL_DIR / "pl_config_pkg.sv"
TCL_CONFIG = REPO_ROOT / "hw" / "scripts" / "generated" / "pl_config.tcl"
DOCS_DIR = REPO_ROOT / "build" / "docs" / "regs" / "pl_control"


def run(cmd):
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def ceil_log2(value):
    width = 0
    limit = 1
    while limit < value:
        width += 1
        limit <<= 1
    return width


def read_config():
    config = {}
    pattern = re.compile(r"^\s*//\s*dawn_config\s+([A-Z0-9_]+)\s*=\s*([0-9]+)\s*$")
    for line in RDL.read_text().splitlines():
        match = pattern.match(line)
        if match:
            config[match.group(1)] = int(match.group(2), 10)

    required = [
        "OUTPUT_COUNT",
        "PIN_OUTPUT_COUNT",
        "PIXELS_PER_OUTPUT",
        "DEFAULT_ACTIVE_OUTPUT_COUNT",
        "DEFAULT_STRAND_PIXEL_COUNT",
        "DEFAULT_OUTPUT_INVERT_MASK",
        "WS281X_BIT_RATE",
    ]
    missing = [name for name in required if name not in config]
    if missing:
        raise RuntimeError(f"Missing dawn_config entries in {RDL}: {', '.join(missing)}")

    config["FRAME_BANKS"] = 2
    config["FRAME_WORDS_PER_BANK"] = config["OUTPUT_COUNT"] * config["PIXELS_PER_OUTPUT"]
    config["FRAME_WORDS"] = config["FRAME_BANKS"] * config["FRAME_WORDS_PER_BANK"]
    config["FRAME_BYTES"] = config["FRAME_WORDS"] * 4
    config["FRAME_ADDR_WIDTH"] = ceil_log2(config["FRAME_BYTES"])
    config["FRAME_RANGE_BYTES"] = 1 << config["FRAME_ADDR_WIDTH"]
    config["MASK_WORD_COUNT"] = (config["OUTPUT_COUNT"] + 31) // 32
    config["OUTPUT_INDEX_WIDTH"] = ceil_log2(config["OUTPUT_COUNT"])
    config["ACTIVE_OUTPUT_WIDTH"] = ceil_log2(config["OUTPUT_COUNT"] + 1)
    config["PIXEL_COUNT_WIDTH"] = ceil_log2(config["PIXELS_PER_OUTPUT"] + 1)
    return config


def write_if_changed(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, newline="")


def emit_config_artifacts(out_root, config):
    ps_config = out_root / "ps" / "app" / "generated" / "pl_config.h"
    rtl_config = out_root / "hw" / "rtl" / "generated" / "pl_config_pkg.sv"
    tcl_config = out_root / "hw" / "scripts" / "generated" / "pl_config.tcl"
    py_config = out_root / "ps" / "tools" / "generated" / "pl_config.py"

    c_lines = [
        "/* Generated from hw/regs/pl_control.rdl. Do not edit. */",
        "#ifndef PL_CONFIG_H",
        "#define PL_CONFIG_H",
        "",
    ]
    for name, value in config.items():
        c_lines.append(f"#define DAWN_PL_{name} {value}u")
    c_lines.extend(["", "#endif", ""])
    write_if_changed(ps_config, "\n".join(c_lines))

    sv_lines = [
        "`timescale 1ns / 1ps",
        "package pl_config_pkg;",
    ]
    for name, value in config.items():
        sv_lines.append(f"    localparam int {name} = {value};")
    sv_lines.extend(["endpackage", ""])
    write_if_changed(rtl_config, "\n".join(sv_lines))

    tcl_lines = ["# Generated from hw/regs/pl_control.rdl. Do not edit."]
    for name, value in config.items():
        tcl_lines.append(f"set dawn_pl_{name.lower()} {value}")
    tcl_lines.append("")
    write_if_changed(tcl_config, "\n".join(tcl_lines))

    py_lines = ["# Generated from hw/regs/pl_control.rdl. Do not edit."]
    for name, value in config.items():
        py_lines.append(f"{name} = {value}")
    py_lines.append("")
    write_if_changed(py_config, "\n".join(py_lines))


def generate(out_root, include_docs=True):
    config = read_config()
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
    emit_config_artifacts(out_root, config)
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
        "Dawn Controller PL Control Registers",
        str(RDL),
    ])
    index_html = docs_dir / "index.html"
    index_html.write_text(
        re.sub(r"BUILD_TS = \d+|ts=\d+", lambda m: "BUILD_TS = 0" if m.group(0).startswith("BUILD_TS") else "ts=0", index_html.read_text()),
        newline="",
    )


def copy_generated(src_root):
    PS_CONFIG_HEADER.parent.mkdir(parents=True, exist_ok=True)
    PY_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    TCL_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src_root / "ps" / "app" / "pl_control.h", PS_HEADER)
    shutil.copy2(src_root / "ps" / "app" / "generated" / "pl_config.h", PS_CONFIG_HEADER)
    shutil.copy2(src_root / "ps" / "tools" / "generated" / "pl_config.py", PY_CONFIG)
    shutil.copy2(src_root / "hw" / "scripts" / "generated" / "pl_config.tcl", TCL_CONFIG)
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
    for src, dst in [
        (src_root / "ps" / "app" / "generated" / "pl_config.h", PS_CONFIG_HEADER),
        (src_root / "ps" / "tools" / "generated" / "pl_config.py", PY_CONFIG),
        (src_root / "hw" / "scripts" / "generated" / "pl_config.tcl", TCL_CONFIG),
    ]:
        if not dst.exists() or not filecmp.cmp(src, dst, shallow=False):
            differences.append(str(dst.relative_to(REPO_ROOT)))
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
