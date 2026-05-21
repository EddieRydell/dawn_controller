#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime

import vitis


def mark(message):
    print(message, flush=True)


repo_root = Path(__file__).resolve().parents[2]
workspace = repo_root / "build" / "vitis" / datetime.now().strftime("%Y%m%d_%H%M%S")
xsa = repo_root / "build" / "vivado" / "dawn_controller.xsa"

if not xsa.exists():
    raise SystemExit(f"Missing XSA: {xsa}")

mark("create_client")
client = vitis.create_client()

mark(f"set_workspace {workspace}")
client.set_workspace(str(workspace))

mark("create_platform_component")
platform = client.create_platform_component(
    name="dawn_platform",
    hw_design=str(xsa),
    cpu="ps7_cortexa9_0",
    os="standalone",
    domain_name="standalone",
)

mark("set stdout uart0")
for domain_name in ("standalone", "zynq_fsbl"):
    domain = platform.get_domain(domain_name)
    domain.set_config("os", "standalone_stdin", "ps7_uart_0")
    domain.set_config("os", "standalone_stdout", "ps7_uart_0")
    domain.set_config(
        "proc",
        "proc_extra_compiler_flags",
        " -O2 -g -fno-tree-loop-distribute-patterns",
    )

mark("enable lwip")
standalone_domain = platform.get_domain("standalone")
if not any(lib.get("name") == "lwip220" for lib in standalone_domain.get_libs()):
    standalone_domain.set_lib("lwip220")

mark("silence generated fsbl warnings")
fsbl_user_config = workspace / "dawn_platform" / "zynq_fsbl" / "UserConfig.cmake"
fsbl_config = fsbl_user_config.read_text()
fsbl_config = fsbl_config.replace(
    "set(USER_COMPILE_WARNINGS_INHIBIT_ALL )",
    "set(USER_COMPILE_WARNINGS_INHIBIT_ALL -w)",
)
fsbl_user_config.write_text(fsbl_config)

mark("platform build")
platform.build()

mark("find platform")
platform_xpfm = client.find_platform_in_repos("dawn_platform")

mark("create app")
app = client.create_app_component(
    name="dawn_controller",
    platform=platform_xpfm,
    domain="standalone",
    template="empty_application",
)

mark("import app files")
app.import_files(from_loc=str(repo_root / "ps" / "app"), dest_dir_in_cmp="src")

mark("link lwip")
app_cmake = workspace / "dawn_controller" / "src" / "CMakeLists.txt"
app_cmake_text = app_cmake.read_text()
app_cmake_text = app_cmake_text.replace(
    "collect(PROJECT_LIB_DEPS xilstandalone;xiltimer)",
    "collect(PROJECT_LIB_DEPS xilstandalone;xiltimer;lwip220)",
)
app_cmake.write_text(app_cmake_text)

mark("app build")
app.build()

mark("dispose")
vitis.dispose()

app_elf = workspace / "dawn_controller" / "build" / "dawn_controller.elf"
fsbl_elf = workspace / "dawn_platform" / "zynq_fsbl" / "build" / "fsbl.elf"
stamp = repo_root / "build" / "vitis" / ".app-built"
if not app_elf.exists():
    raise SystemExit(f"Missing app ELF: {app_elf}")
if not fsbl_elf.exists():
    raise SystemExit(f"Missing FSBL ELF: {fsbl_elf}")
stamp.parent.mkdir(parents=True, exist_ok=True)
stamp.touch()

mark("complete")
