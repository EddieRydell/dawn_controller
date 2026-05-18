from pathlib import Path
import argparse
import shutil
import subprocess
import time
import traceback

import xsdb


REPO_ROOT = Path(__file__).resolve().parents[2]
HW_SERVER_URL = "TCP:localhost:3121"
BIT_FILE = REPO_ROOT / "build" / "vivado" / "donder_controller.runs" / "impl_1" / "donder_system_wrapper.bit"
VITIS_WORKSPACE = REPO_ROOT / "build" / "vitis_py"
PL_BASE = 0x43C00000
PL_ENABLE = 0x00000001
PL_PIN_TEST = 0x00000100

SLCR_UNLOCK = 0xF8000008
SLCR_LOCK = 0xF8000004
SLCR_UNLOCK_KEY = 0x0000DF0D
SLCR_LOCK_KEY = 0x0000767B
FPGA_RST_CTRL = 0xF8000240
LVL_SHFTR_EN = 0xF8000900


def newest(pattern):
    candidates = sorted(
        VITIS_WORKSPACE.glob(pattern),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        raise RuntimeError(f"No file found under {VITIS_WORKSPACE}: {pattern}")
    return candidates[0]


def newest_app_elf():
    return newest("*/donder_ps/build/donder_ps.elf")


def newest_fsbl_elf():
    return newest("*/donder_platform/zynq_fsbl/build/fsbl.elf")


def start_hw_server():
    hw_server = shutil.which("hw_server.bat")
    if hw_server is None:
        raise RuntimeError("hw_server.bat is not on PATH")

    log_dir = REPO_ROOT / "build" / "jtag"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "hw_server_run_controller.log"
    log_file = log_path.open("w")
    process = subprocess.Popen(
        [hw_server, "-sTCP::3121", "-I60"],
        stdout=log_file,
        stderr=subprocess.STDOUT,
    )
    return process, log_file, log_path


def connect_with_retry(session, timeout_seconds=20):
    deadline = time.time() + timeout_seconds
    last_exc = None
    while time.time() < deadline:
        try:
            session.connect(url=HW_SERVER_URL)
            return
        except Exception as exc:
            last_exc = exc
            time.sleep(1)
    raise RuntimeError(f"could not connect to {HW_SERVER_URL}") from last_exc


def select_target(session, filter_expr):
    return session.targets("-s", filter=filter_expr, timeout=10000)


def mrd32(session, address):
    value = session.mrd(address, "-v")
    if isinstance(value, list):
        return int(value[0])
    return int(value)


def mwr32(session, address, value):
    session.mwr(address=address, words=int(value))


def mask_write32(session, address, mask, value):
    current = mrd32(session, address)
    mwr32(session, address, (current & ~mask) | (value & mask))


def ps7_post_config(session):
    # Equivalent to the generated ps7_post_config operation: enable PS-PL
    # level shifters and release FPGA resets after programming the bitstream.
    select_target(session, "name=~APU")
    session.configparams("force-mem-accesses", 1)
    mwr32(session, SLCR_UNLOCK, SLCR_UNLOCK_KEY)
    mask_write32(session, LVL_SHFTR_EN, 0x0000000F, 0x0000000F)
    mask_write32(session, FPGA_RST_CTRL, 0xFFFFFFFF, 0x00000000)
    mwr32(session, SLCR_LOCK, SLCR_LOCK_KEY)


def print_pl_registers(session):
    select_target(session, "name=~APU")
    for offset, name in [
        (0x000, "CONTROL"),
        (0x004, "STATUS"),
        (0x008, "ACTIVE_BANK"),
        (0x00C, "WRITE_BANK"),
        (0x010, "FRAME_COUNTER"),
        (0x014, "DROPPED_FRAME_COUNTER"),
        (0x018, "LATE_COMMIT_COUNTER"),
        (0x020, "OUTPUT_COUNT"),
        (0x024, "MAX_PIXELS_PER_OUTPUT"),
        (0x028, "FRAME_BASE_ADDR"),
        (0x100, "OUTPUT0_PIXEL_COUNT"),
        (0x104, "OUTPUT0_BUFFER_OFFSET"),
        (0x108, "OUTPUT0_FLAGS"),
        (0x110, "OUTPUT1_PIXEL_COUNT"),
        (0x114, "OUTPUT1_BUFFER_OFFSET"),
        (0x118, "OUTPUT1_FLAGS"),
        (0x120, "OUTPUT2_PIXEL_COUNT"),
        (0x124, "OUTPUT2_BUFFER_OFFSET"),
        (0x128, "OUTPUT2_FLAGS"),
        (0x130, "OUTPUT3_PIXEL_COUNT"),
        (0x134, "OUTPUT3_BUFFER_OFFSET"),
        (0x138, "OUTPUT3_FLAGS"),
        (0x300, "DBG_READER_STATE"),
        (0x304, "DBG_READER_OUTPUT_INDEX"),
        (0x308, "DBG_READER_PIXEL_INDEX"),
        (0x30C, "DBG_AXI_ARVALID_CYCLES"),
        (0x310, "DBG_AXI_AR_HANDSHAKES"),
        (0x314, "DBG_AXI_R_HANDSHAKES"),
        (0x318, "DBG_AXI_LAST_ARADDR"),
        (0x31C, "DBG_AXI_LAST_RRESP"),
        (0x320, "DBG_PIXEL_ACCEPT_COUNT"),
        (0x324, "DBG_WS_HIGH_COUNT"),
    ]:
        value = mrd32(session, PL_BASE + offset)
        print(f"{name}=0x{value:08x}", flush=True)


def enable_pin_test(session):
    select_target(session, "name=~APU")
    mwr32(session, PL_BASE + 0x000, PL_ENABLE | PL_PIN_TEST)
    time.sleep(0.2)
    print("PIN_TEST_ENABLED", flush=True)
    print_pl_registers(session)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pin-test", action="store_true", help="drive PMOD outputs with slow PL square waves instead of running the app")
    parser.add_argument("--poll-seconds", type=float, default=5.0, help="register polling interval while the run is held open")
    args = parser.parse_args()

    if not BIT_FILE.exists():
        raise RuntimeError(f"Missing bitstream: {BIT_FILE}")

    fsbl = newest_fsbl_elf()
    app = newest_app_elf()

    session = xsdb.start_debug_session()
    hw_server = None
    hw_server_log = None
    try:
        try:
            session.connect(url=HW_SERVER_URL)
        except Exception:
            hw_server, hw_server_log, hw_server_log_path = start_hw_server()
            connect_with_retry(session)

        print("TARGETS_START", flush=True)
        print(session.targets(), flush=True)

        select_target(session, "name=~*Cortex-A9*#0*")
        try:
            session.stop()
        except Exception:
            pass

        print("RESET_CPU", flush=True)
        session.rst("-s", "-c", type="processor")
        session.stop()

        print(f"DOWNLOAD_FSBL {fsbl}", flush=True)
        session.dow(file=str(fsbl))
        session.con()
        time.sleep(3)
        session.stop()

        print(f"PROGRAM_FPGA {BIT_FILE}", flush=True)
        select_target(session, "name=~xc7z020")
        session.fpga(file=str(BIT_FILE))

        print("PS7_POST_CONFIG", flush=True)
        ps7_post_config(session)

        if args.pin_test:
            enable_pin_test(session)
            return 0

        print(f"DOWNLOAD_APP {app}", flush=True)
        select_target(session, "name=~*Cortex-A9*#0*")
        session.rst("-s", "-c", type="processor")
        session.stop()
        session.dow(file=str(app))
        session.con()

        sample = 0
        while True:
            time.sleep(args.poll_seconds)
            sample += 1
            print(f"PL_REGS_SAMPLE_{sample}", flush=True)
            print_pl_registers(session)

    except Exception as exc:
        print(f"ERROR: {exc}", flush=True)
        traceback.print_exc()
        if hw_server is not None and hw_server.poll() is not None:
            print(f"hw_server exited with code {hw_server.returncode}", flush=True)
            print(f"hw_server log: {hw_server_log_path}", flush=True)
        return 1
    finally:
        try:
            session.disconnect()
        except Exception:
            pass
        if hw_server_log is not None:
            hw_server_log.close()
        if hw_server is not None and hw_server.poll() is None:
            hw_server.terminate()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
