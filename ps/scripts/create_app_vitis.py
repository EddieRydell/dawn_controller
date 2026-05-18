#!/usr/bin/env python3
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from datetime import datetime

import vitis


def mark(message):
    print(message, flush=True)


def vitis_server_pids():
    if os.name != "nt":
        return set()

    command = (
        "Get-CimInstance Win32_Process | "
        "Where-Object { $_.Name -eq 'java.exe' -and "
        "$_.CommandLine -like '*Vitis*vitis-server*RigelApp*' } | "
        "ForEach-Object { $_.ProcessId }"
    )
    result = subprocess.run(
        ["powershell", "-NoProfile", "-Command", command],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        mark(f"warning: could not list Vitis server PIDs: {result.stderr.strip()}")
        return set()

    pids = set()
    for line in result.stdout.splitlines():
        line = line.strip()
        if line:
            pids.add(int(line))
    return pids


def stop_new_vitis_servers(existing_pids):
    new_pids = vitis_server_pids() - existing_pids
    for pid in sorted(new_pids):
        mark(f"stop lingering Vitis server PID {pid}")
        subprocess.run(
            ["powershell", "-NoProfile", "-Command", f"Stop-Process -Id {pid} -Force"],
            check=False,
        )


repo_root = Path(__file__).resolve().parents[2]
workspace_base = repo_root / "build" / "vitis_py"
workspace = workspace_base / datetime.now().strftime("%Y%m%d_%H%M%S")
xsa = repo_root / "build" / "vivado" / "donder_controller.xsa"

if not xsa.exists():
    raise SystemExit(f"Missing XSA: {xsa}")

if workspace_base.exists():
    def clear_readonly(func, path, exc_info):
        os.chmod(path, stat.S_IWRITE)
        func(path)

    # Best effort cleanup of previous completed runs. Active Vitis backends can
    # hold .lock files; in that case the new timestamped workspace still works.
    try:
        shutil.rmtree(workspace_base, onexc=clear_readonly)
    except PermissionError as exc:
        mark(f"warning: could not remove stale workspace base: {exc}")

existing_vitis_server_pids = vitis_server_pids()

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

mark("get_domain")
domain = platform.get_domain("standalone")

mark("platform build")
try:
    platform.build()
except Exception as exc:
    mark(f"error: platform build failed: {exc}")
    vitis.dispose()
    stop_new_vitis_servers(existing_vitis_server_pids)
    sys.exit(1)

mark("find platform")
platform_xpfm = client.find_platform_in_repos("donder_platform")

mark("create app")
app = client.create_app_component(
    name="donder_ps",
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

stop_new_vitis_servers(existing_vitis_server_pids)
app_elf = workspace / "donder_ps" / "build" / "donder_ps.elf"
fsbl_elf = workspace / "donder_platform" / "zynq_fsbl" / "build" / "fsbl.elf"
if not app_elf.exists():
    mark(f"error: missing app ELF: {app_elf}")
    sys.exit(1)
if not fsbl_elf.exists():
    mark(f"error: missing FSBL ELF: {fsbl_elf}")
    sys.exit(1)
mark("complete")
