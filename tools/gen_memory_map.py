#!/usr/bin/env python3
import argparse
from pathlib import Path

try:
    import yaml
except ImportError as exc:
    raise SystemExit("PyYAML is required: python -m pip install pyyaml") from exc


def int_value(value):
    if isinstance(value, int):
        return value
    return int(str(value), 0)


def c_hex(value):
    return f"0x{value:03x}u"


def sv_hex(value):
    return f"'h{value:03x}"


def guard_from_path(path):
    name = path.name.upper().replace(".", "_").replace("-", "_")
    return f"DONDER_GENERATED_{name}"


def write_if_changed(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return
    path.write_text(text, newline="\n")


def generate_c_header(spec):
    guard = "PL_REGS_H"
    reg_prefix = spec.get("register_prefix", "PL_REG")
    field_prefix = spec.get("field_prefix", "PL")
    lines = [
        "/* Generated from memory_map.yaml. Do not edit by hand. */",
        f"#ifndef {guard}",
        f"#define {guard}",
        "",
        "#include <stdint.h>",
        "",
    ]

    output_stride = None
    output_base = None
    for reg in spec["registers"]:
        name = reg["name"]
        offset = int_value(reg["offset"])
        lines.append(f"#define {reg_prefix}_{name:<30} {c_hex(offset)}")
        if "stride" in reg:
            stride = int_value(reg["stride"])
            lines.append(f"#define {reg_prefix}_{name}_STRIDE{'':<23} {c_hex(stride)}")
            if output_stride is None:
                output_stride = stride
            if output_base is None:
                output_base = offset & ~0x0F
        for field in reg.get("fields", []):
            bit = int_value(field["bit"])
            width = int_value(field.get("width", 1))
            mask = ((1 << width) - 1) << bit
            lines.append(f"#define {field_prefix}_{field['name']:<35} (1u << {bit})" if width == 1 else
                         f"#define {field_prefix}_{field['name']}_MASK{'':<30} 0x{mask:08x}u")
            if width > 1:
                lines.append(f"#define {field_prefix}_{field['name']}_SHIFT{'':<29} {bit}u")
        lines.append("")

    if output_base is not None:
        lines.append(f"#define {reg_prefix}_OUTPUT_BASE{'':<24} {c_hex(output_base)}")
    if output_stride is not None:
        lines.append(f"#define {reg_prefix}_OUTPUT_STRIDE{'':<22} {c_hex(output_stride)}")
    lines.extend(["", f"#endif /* {guard} */", ""])
    return "\n".join(lines)


def generate_sv_package(spec):
    reg_prefix = spec.get("register_prefix", "PL_REG")
    field_prefix = spec.get("field_prefix", "PL")
    lines = [
        "// Generated from memory_map.yaml. Do not edit by hand.",
        "package regs_pkg;",
        "",
    ]
    output_stride = None
    output_base = None
    for reg in spec["registers"]:
        name = reg["name"]
        offset = int_value(reg["offset"])
        lines.append(f"    localparam int unsigned {reg_prefix}_{name} = 32{sv_hex(offset)};")
        if "stride" in reg:
            stride = int_value(reg["stride"])
            lines.append(f"    localparam int unsigned {reg_prefix}_{name}_STRIDE = 32{sv_hex(stride)};")
            if output_stride is None:
                output_stride = stride
            if output_base is None:
                output_base = offset & ~0x0F
        for field in reg.get("fields", []):
            bit = int_value(field["bit"])
            width = int_value(field.get("width", 1))
            if width == 1:
                lines.append(f"    localparam logic [31:0] {field_prefix}_{field['name']} = 32'h{1 << bit:08x};")
            else:
                mask = ((1 << width) - 1) << bit
                lines.append(f"    localparam logic [31:0] {field_prefix}_{field['name']}_MASK = 32'h{mask:08x};")
                lines.append(f"    localparam int unsigned {field_prefix}_{field['name']}_SHIFT = {bit};")
        lines.append("")

    if output_base is not None:
        lines.append(f"    localparam int unsigned {reg_prefix}_OUTPUT_BASE = 32{sv_hex(output_base)};")
    if output_stride is not None:
        lines.append(f"    localparam int unsigned {reg_prefix}_OUTPUT_STRIDE = 32{sv_hex(output_stride)};")
    lines.extend(["", "endpackage", ""])
    return "\n".join(lines)


def generate_markdown(spec):
    lines = [
        "# PS/PL Memory Map",
        "",
        "_Generated from `memory_map.yaml`. Do not edit by hand._",
        "",
        spec.get("description", ""),
        "",
        "## AXI-Lite Registers",
        "",
        "| Offset | Name | Access | Description |",
        "| --- | --- | --- | --- |",
    ]
    for reg in spec["registers"]:
        offset = int_value(reg["offset"])
        if "stride" in reg:
            display_offset = f"`0x{offset:03x} + n*0x{int_value(reg['stride']):03x}`"
        else:
            display_offset = f"`0x{offset:03x}`"
        lines.append(f"| {display_offset} | `{reg['name']}` | {reg['access'].upper()} | {reg.get('description', '')} |")

    field_rows = []
    for reg in spec["registers"]:
        for field in reg.get("fields", []):
            bit = int_value(field["bit"])
            width = int_value(field.get("width", 1))
            bits = str(bit) if width == 1 else f"{bit + width - 1}:{bit}"
            field_rows.append((reg["name"], field["name"], bits, field.get("description", "")))

    if field_rows:
        lines.extend(["", "## Fields", "", "| Register | Field | Bits | Description |", "| --- | --- | --- | --- |"])
        for reg_name, field_name, bits, desc in field_rows:
            lines.append(f"| `{reg_name}` | `{field_name}` | `{bits}` | {desc} |")

    fb = spec.get("framebuffer", {})
    if fb:
        lines.extend([
            "",
            "## Frame Buffer",
            "",
            fb.get("description", ""),
            "",
            f"- Pixel format: `{fb.get('pixel_format')}`",
            f"- Pixel bytes: `{fb.get('pixel_bytes')}`",
            f"- Bank count symbol: `{fb.get('banks_symbol')}`",
            f"- Output count symbol: `{fb.get('outputs_symbol')}`",
            f"- Pixels per output symbol: `{fb.get('pixels_per_output_symbol')}`",
            "",
            "Frame bank addressing:",
            "",
            "```text",
            "bank_base + output_buffer_offset[n] + pixel_index * pixel_bytes",
            "```",
        ])

    lines.extend([
        "",
        "## Determinism Contract",
        "",
        "- PL never stalls a WS2811 waveform once started.",
        "- PL only swaps banks at a frame boundary.",
        "- PL repeats the previous frame if no complete new frame is ready.",
        "- PS only writes the inactive bank.",
        "",
    ])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", default="memory_map.yaml")
    parser.add_argument("--c", default="ps/app/pl_regs.h")
    parser.add_argument("--sv", default="hw/rtl/regs_pkg.sv")
    parser.add_argument("--md", default="docs/memory_map.md")
    args = parser.parse_args()

    spec = yaml.safe_load(Path(args.spec).read_text())
    write_if_changed(Path(args.c), generate_c_header(spec))
    write_if_changed(Path(args.sv), generate_sv_package(spec))
    write_if_changed(Path(args.md), generate_markdown(spec))


if __name__ == "__main__":
    main()
