# Donder Controller

Production-oriented PYNQ-Z2 foundation for Ethernet-to-PL projects and an E1.31-to-WS2811 light controller.

The foundation is intentionally one path:

```text
Zynq PS bare-metal app
  -> onboard PS Ethernet path, next integration step
  -> frame assembly in PS memory
  -> M_AXI_GP0 AXI-Lite writes
  -> eth_control_core control/status
  -> double-buffered axil_frame_ram window
  -> deterministic PL WS281x serializer
```

The current PL contract supports full-frame delivery into PL-owned storage with explicit two-bank ownership. The PS writes only the `WRITE_BANK`, commits that bank atomically, and the PL WS281x consumer reads only committed frames from the `ACTIVE_BANK`. Ethernet receive should be added behind this same contract, not as parallel scripts or alternate runtime modes.

## Commands

Run from a Xilinx-enabled shell where Vivado, Vitis, Bootgen, XSDB, and hw_server are on `PATH`.

```powershell
make clean
make rtl-check
make rtl-sim
make hw
make ps
make boot
```

For JTAG development:

```powershell
make run
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
hw/rtl/eth_control_core.v    AXI-Lite control/status core
hw/rtl/axil_frame_ram.v      AXI-Lite frame RAM with a second PL read port
hw/sim/tb_ws281x_consumer.v  Focused WS281x consumer RTL simulation
hw/scripts/build.tcl         Vivado batch hardware build
hw/scripts/ps_bd.tcl         Zynq PS + control/frame-RAM block design
hw/constraints/pynq_z2.xdc   PYNQ-Z2 PMOD output constraints
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
| Frame RAM | `0x43C10000` | 32 KiB | 8192 32-bit frame words |

| Offset | Name | Access | Purpose |
| --- | --- | --- | --- |
| `0x000` | `ID` | RO | Must read `0x4546504c` |
| `0x004` | `VERSION` | RO | Must read `0x00030000` |
| `0x008` | `CONTROL` | RW | Bit 1 clears sticky status |
| `0x00c` | `STATUS` | RO | Bit 0 ready, bit 1 frame overflow, bit 2 consumer error |
| `0x010` | `PIN_OUT` | RW | Debug mirror of the first committed frame word |
| `0x014` | `COUNTER` | RO | Free-running PL clock counter |
| `0x018` | `FRAME_CAPACITY` | RO | PL frame storage capacity in 32-bit words |
| `0x020` | `FRAME_COMMIT` | WO | Atomic commit: bit 31 bank, bits 30:0 word count |
| `0x024` | `FRAME_COUNT` | RO | Accepted frame commits |
| `0x028` | `COMMITTED_WORDS` | RO | Word count from last commit |
| `0x02c` | `FIRST_FRAME_WORD` | RW | First word metadata for commit proof |
| `0x030` | `LAST_FRAME_WORD` | RW | Last word metadata for commit proof |
| `0x034` | `ERROR_COUNT` | RO | Protocol errors detected by PL |
| `0x038` | `FRAME_BANK_WORDS` | RO | Words per frame bank |
| `0x03c` | `ACTIVE_BANK` | RO | Bank currently committed to PL/debug |
| `0x040` | `WRITE_BANK` | RO | Bank currently owned by PS writes |
| `0x044` | `FRAME_SEQUENCE` | RO | Monotonic accepted-commit sequence |
| `0x048` | `CONSUMER_CONTROL` | RW | Bit 0 enables WS281x consumer, bit 1 resets consumer FSM |
| `0x04c` | `CONSUMER_STATUS` | RO | Bit 0 enabled, bit 1 busy, bit 2 reset-low period, bit 3 sticky error |
| `0x050` | `CONSUMER_SEQUENCE` | RO | Last frame sequence fully consumed by WS281x serializer |
| `0x054` | `CONSUMER_FRAME_COUNT` | RO | Completed WS281x frame transmissions |
| `0x058` | `CONSUMER_ERROR_COUNT` | RO | Consumer-side protocol/read errors |
| `0x05c` | `WS281X_BIT_RATE` | RO | Configured serializer bit rate, currently 800000 |
| `0x060` | `WS281X_OUTPUT_COUNT` | RO | Configured parallel outputs, currently 4 |
| `0x064` | `WS281X_PIXELS_PER_OUTPUT` | RO | Configured pixels per output, currently 1024 |
| `0x068` | `CONSUMER_DEBUG` | RO | Packed FSM debug snapshot for JTAG bring-up |

Current frame format is pixel-major: for each pixel index, output 0 through output 3 are stored as one `0x00RRGGBB` word each. The frame RAM capacity is `8192` words split into two `4096` word banks, matching the current configured frame size of `4 * 1024` pixels.

## Next Integration Boundary

The PS app currently generates deterministic test frames and commits them through the same `pl_ingest_write_frame()` path that Ethernet receive will use. The Ethernet step should add lwIP UDP receive on the PS and map E1.31 slots into the inactive frame returned by `frame_pipeline_inactive_words()`. Commit remains a single write to `FRAME_COMMIT`; the PL side already consumes committed frames through the WS281x serializer.
