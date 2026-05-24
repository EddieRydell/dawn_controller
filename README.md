# Dawn Controller

Production-oriented PYNQ-Z2 foundation for Ethernet-to-PL projects and an E1.31-to-WS2811 light controller.

The foundation is intentionally one path:

```text
Zynq PS bare-metal app
  -> onboard PS ENET0 + lwIP UDP E1.31 receive
  -> frame assembly in PS memory
  -> M_AXI_GP0 AXI-Lite writes
  -> pl_frame_control control/status
  -> double-buffered axil_frame_ram window
  -> deterministic PL WS281x serializer
```

The current PL contract supports full-frame delivery into PL-owned storage with explicit two-bank ownership. The PS writes only the `WRITE_BANK`, commits that bank atomically, and the PL WS281x consumer reads only committed frames from the `ACTIVE_BANK`. Ethernet receive runs behind this same contract, not as parallel scripts or alternate runtime modes.

## Commands

Run from a Xilinx-enabled shell where Vivado, Vitis, Bootgen, XSDB, and hw_server are on `PATH`.
This will install four peakrdl dependencies globally and then test and build the project. 
Create a python venv if you don't want the peakrdl deps installed globally.

```sh
python -m pip install -r requirements-regs.txt
make clean
make regs-check
make rtl-check
make rtl-sim
make hw
make ps
make boot
```

For JTAG development:

```sh
make run
```

For UART telemetry:

```sh
make logs
make logs PORT=COMx
```

For a host-side E1.31 packet source:

```sh
make e131-send
```

For deployment, copy this file to the FAT partition of the SD card:

```text
build/sd/BOOT.BIN
```

The boot image contains:

```text
FSBL
FPGA bitstream
bare-metal controller app
```

## Active Files

```text
hw/regs/pl_control.rdl       SystemRDL source of truth for PL/register/runtime contract
hw/rtl/generated/            PeakRDL-generated AXI-Lite control register block
hw/rtl/pl_frame_control.sv       Reusable PS-to-PL AXI-Lite control and frame commit foundation
hw/rtl/ws281x_frame_consumer.sv  WS281x frame reader and serializer
hw/rtl/ws281x_controller_core.v  Light-controller wrapper that wires the foundation to the WS281x consumer
hw/rtl/axil_frame_ram.v      AXI-Lite frame RAM with a second PL read port
hw/sim/tb_ws281x_consumer.v  Focused WS281x consumer RTL simulation
hw/scripts/build.tcl         Vivado batch hardware build
hw/scripts/ps_bd.tcl         Zynq PS + control/frame-RAM block design
hw/constraints/pynq_z2.xdc   PYNQ-Z2 Arduino/PMOD output constraints
ps/app/                      Bare-metal controller app
ps/scripts/create_app_vitis.py
ps/scripts/package_boot.py
ps/scripts/run_controller.tcl
ps/scripts/run_xsdb_checked.py
Makefile
```

## PL Address Map

| Region | Base | Size | Purpose |
| --- | --- | --- | --- |
| Control | `DAWN_PL_CONTROL_BASEADDR` | `DAWN_PL_CONTROL_RANGE_BYTES` | Identity, status, counters, commit |
| Frame RAM | `DAWN_PL_FRAME_RAM_BASEADDR` | `DAWN_PL_FRAME_RAM_RANGE_BYTES` | `DAWN_PL_FRAME_WORDS` 32-bit frame words |

The control register map and runtime defaults are authored in `hw/regs/pl_control.rdl`. Run `make regs` to regenerate the committed PS header, Python/Tcl config, RTL packages, and local HTML docs under `build/docs/regs/pl_control/index.html`. Run `make regs-check` to fail if committed generated artifacts are stale.

Current frame format is fixed output-major storage. The synthesized dimensions are generated as `DAWN_PL_OUTPUT_COUNT` and `DAWN_PL_PIXELS_PER_OUTPUT`; word 0 is output 0 pixel 0, then pixels continue through each output before moving to the next output. Each word is `0x00RRGGBB`. Frame RAM sizing and bank sizing are generated as `DAWN_PL_FRAME_WORDS`, `DAWN_PL_FRAME_WORDS_PER_BANK`, and `DAWN_PL_FRAME_BANKS`. Runtime configuration selects the active output count and per-output lengths within those maxima; boot defaults are generated as `DAWN_PL_DEFAULT_ACTIVE_OUTPUT_COUNT`, `DAWN_PL_DEFAULT_STRAND_PIXEL_COUNT`, and `DAWN_PL_DEFAULT_OUTPUT_INVERT_MASK`.

## Ethernet E1.31 Bring-Up

The PS app uses a static direct Ethernet link:

```text
Host NIC: DAWN_PL_HOST_IP*/DAWN_PL_NETMASK_IP*
Board:    DAWN_PL_BOARD_IP*/DAWN_PL_NETMASK_IP*
Gateway:  DAWN_PL_GATEWAY_IP*
UDP port: DAWN_PL_E131_PORT
```

Configure the host Ethernet adapter manually to the generated `DAWN_PL_HOST_IP*` address with `DAWN_PL_NETMASK_IP*`, connect it directly to the PYNQ-Z2 Ethernet port, then run the app and observe UART logs:

```sh
make run
make logs
```

Runtime status is machine-readable:

```text
e131_status link=... rx_packets=... rx_bytes=... rx_oversized=... rx_ring_depth=... rx_ring_high_water=... rx_ring_dropped=... rx_ring_processed=... rx_pbuf_alloc_failures=... rx_pbuf_pool_used=... rx_pbuf_pool_max=... rx_pbuf_pool_avail=... rx_input_calls=... rx_input_active_calls=... rx_input_max_packets=... rx_poll_max_drained=... rx_poll_budget_hits=... e131_valid=... e131_rejected=... universes_seen=... frames_committed=... frames_dropped=... packet_gap_ms=... max_packet_gap_ms=... commit_gap_ms=... max_commit_gap_ms=... last_universe=... last_sequence=... last_error=...
```

Send E1.31 from the host:

```sh
make e131-send
python ps/tools/e131_send.py --dest-ip "$(python -c 'from ps.tools.generated import pl_config; print(pl_config.BOARD_IP_STRING)')" --pattern bars --packet-count 10 --rate 30
```

The sender is send-only. UART remains the canonical observer. A successful packet test shows increasing `rx_packets`, `e131_valid`, and `frames_committed`. Malformed packets or packets outside the configured universe range increment `e131_rejected` and do not commit a frame.

For the throughput benchmark, configure the host NIC, board address, UDP port, and UART baud from the generated `ps/tools/generated/pl_config.py` values:

```sh
make bench-e131
python ps/tools/e131_benchmark.py --skip-build --duration 20
python ps/tools/e131_benchmark.py --skip-build --sanity-only
python ps/tools/e131_benchmark.py --skip-build --pixels 300 --rates 60
```

`make bench-e131` runs `python ps/tools/e131_benchmark.py`. Use `--skip-build` when the app is already built, `--sanity-only` for the first generated-default active-output/pixel-count gate at 30 FPS, `--duration` to change each send duration, and `--pixels` / `--rates` to select cells. The practical gate for the current throughput work is:

```sh
python ps/tools/e131_benchmark.py --skip-build --pixels 300 --rates 60
```

The current benchmark matrix is:

| pixels/output | target FPS |
| ---: | --- |
| 50 | 30, 60, 120, 240, 480 |
| 100 | 30, 60, 120, 240, 360 |
| 300 | 30, 60, 90, 110, 130 |
| 500 | 30, 50, 60, 70, 90 |
| 750 | 20, 30, 40, 50 |
| 1024 | 20, 25, 30, 35, 40 |

The benchmark writes per-run artifacts under `build/bench/<timestamp>/`: `results.csv`, `summary.md`, `uart.log`, per-cell sender logs, JTAG run logs, and JTAG snapshots. It programs the FPGA/app for each pixels-per-output setting after writing runtime strand registers over JTAG, then sends timed E1.31 sweeps from the generated host endpoint.

Stop throughput investigation if any cell at or below `60 FPS` reports pbuf allocation failures, RX ring drops, sequence anomalies, PL/consumer errors, or committed FPS below 99% of target.

For the non-DMA ingress profile, run:

```sh
python ps/tools/e131_ingress_profile.py --duration 20
```

The profile rebuilds `make ps` for each explicit lwIP candidate, records unsupported Vitis settings instead of substituting values, runs the generated-default active-output/pixel-count guard at 30 FPS once, then runs the local scenario cells listed in `ps/tools/e131_ingress_profile.py` per candidate. Artifacts are written under `build/bench/<timestamp>-ingress-profile/`.

To run the full repeatable profile bundle and write a root-level Markdown report:

```sh
make e131-profile-report
```

This target auto-detects the board UART, runs host PS tests, Python compile checks, the full ingress candidate profile, a `30x500` ceiling sweep using the repo-default lwIP settings, and writes `E131_PROFILE_RESULTS.md` with links to the generated artifacts. Use `SERIAL_PORT=COMx` to override detection and `E131_PROFILE_DURATION=20` for longer cells.

E1.31 universe data is accepted starting at `DAWN_FIRST_UNIVERSE`. RGB slots are interpreted as the same linear output-major stream used by PL frame RAM: output 0 pixels first, then output 1, and onward through the configured active output count. The PS writes those slots directly into the inactive frame bank before committing through `frame_pipeline_commit()`.
