#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime

import vitis


def mark(message):
    print(message, flush=True)


repo_root = Path(__file__).resolve().parents[2]
workspace = repo_root / "build" / "vitis" / datetime.now().strftime("%Y%m%d_%H%M%S")
xsa = repo_root / "build" / "vivado" / "donder_controller.xsa"

if not xsa.exists():
    raise SystemExit(f"Missing XSA: {xsa}")

mark("create_client")
client = vitis.create_client()

mark(f"set_workspace {workspace}")
client.set_workspace(str(workspace))

mark("create_platform_component")
platform = client.create_platform_component(
    name="donder_platform",
    hw_design=str(xsa),
    cpu="ps7_cortexa9_0",
    os="standalone",
    domain_name="standalone",
)

mark("platform build")
platform.build()

mark("find platform")
platform_xpfm = client.find_platform_in_repos("donder_platform")

mark("create app")
app = client.create_app_component(
    name="donder_controller",
    platform=platform_xpfm,
    domain="standalone",
    template="empty_application",
)

mark("import app files")
app.import_files(from_loc=str(repo_root / "ps" / "app"), dest_dir_in_cmp="src")

mark("app build")
app.build()

mark("dispose")
vitis.dispose()

app_elf = workspace / "donder_controller" / "build" / "donder_controller.elf"
fsbl_elf = workspace / "donder_platform" / "zynq_fsbl" / "build" / "fsbl.elf"
stamp = repo_root / "build" / "vitis" / ".app-built"
if not app_elf.exists():
    raise SystemExit(f"Missing app ELF: {app_elf}")
if not fsbl_elf.exists():
    raise SystemExit(f"Missing FSBL ELF: {fsbl_elf}")
stamp.parent.mkdir(parents=True, exist_ok=True)
stamp.touch()

mark("complete")
