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
hw/regs/pl_control.rdl       SystemRDL source of truth for PL control registers
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
| Control | `0x43C00000` | 4 KiB | Identity, status, counters, commit |
| Frame RAM | `0x43C80000` | 256 KiB | 61440 32-bit frame words |

The control register map is authored in `hw/regs/pl_control.rdl`. Run `make regs` to regenerate the committed PS header and RTL register block, plus local HTML docs under `build/docs/regs/pl_control/index.html`. Run `make regs-check` to fail if committed generated artifacts are stale.

Current frame format is fixed output-major storage for 30 synthesized outputs with 1024 pixels per output. Word `0` is output 0 pixel 0, word `1023` is output 0 pixel 1023, word `1024` is output 1 pixel 0, and so on through output 29. Each word is `0x00RRGGBB`. The frame RAM capacity is `61440` words split into two `30720` word banks. Runtime configuration selects the active output count and per-output lengths within those maxima; boot defaults are 30 active outputs, 50 pixels each, and output invert mask `0x3fffffff`.

## Ethernet E1.31 Bring-Up

The PS app uses a static direct Ethernet link:

```text
Host NIC: 192.168.7.1/24
Board:    192.168.7.2/24
Gateway:  0.0.0.0
UDP port: 5568
```

Configure the host Ethernet adapter manually to `192.168.7.1` with netmask `255.255.255.0`, connect it directly to the PYNQ-Z2 Ethernet port, then run the app and observe UART logs:

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
python ps/tools/e131_send.py --dest-ip 192.168.7.2 --pattern bars --packet-count 10 --rate 30
```

The sender is send-only. UART remains the canonical observer. A successful packet test shows increasing `rx_packets`, `e131_valid`, and `frames_committed`. Malformed packets or packets outside the configured universe range increment `e131_rejected` and do not commit a frame.

For the 30-output throughput benchmark, configure the host NIC as `192.168.7.1/24`, keep the board at `192.168.7.2`, use UDP `5568`, and keep UART on `COM4` at `115200` baud:

```sh
make bench-e131
python ps/tools/e131_benchmark.py --skip-build --duration 20 --serial-port COM4
python ps/tools/e131_benchmark.py --skip-build --sanity-only
python ps/tools/e131_benchmark.py --skip-build --pixels 300 --rates 60
```

`make bench-e131` runs `python ps/tools/e131_benchmark.py`. Use `--skip-build` when the app is already built, `--sanity-only` for the first `30x50 @ 30 FPS` gate, `--duration` to change each send duration, and `--pixels` / `--rates` to select cells. The practical gate for the current throughput work is:

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

The benchmark writes per-run artifacts under `build/bench/<timestamp>/`: `results.csv`, `summary.md`, `uart.log`, per-cell sender logs, JTAG run logs, and JTAG snapshots. It programs the FPGA/app for each pixels-per-output setting after writing runtime strand registers over JTAG, then sends timed E1.31 sweeps from `192.168.7.1`.

Stop throughput investigation if any cell at or below `60 FPS` reports pbuf allocation failures, RX ring drops, sequence anomalies, PL/consumer errors, or committed FPS below 99% of target.

For the non-DMA ingress profile, run:

```sh
python ps/tools/e131_ingress_profile.py --serial-port COM4 --duration 20
```

The profile rebuilds `make ps` for each explicit lwIP candidate, records unsupported Vitis settings instead of substituting values, runs `30x50 @ 30 FPS` once as a guard, then runs `30x300 @ 60 FPS`, `30x500 @ 60 FPS`, and `30x1024 @ 30 FPS` per candidate. Artifacts are written under `build/bench/<timestamp>-ingress-profile/`.

E1.31 universe data is accepted starting at `DAWN_FIRST_UNIVERSE`. RGB slots are interpreted as the same linear output-major stream used by PL frame RAM: output 0 pixels first, then output 1, and onward through the configured active output count. The PS writes those slots directly into the inactive frame bank before committing through `frame_pipeline_commit()`.
