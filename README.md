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
hw/regs/pl_control.rdl       SystemRDL source of truth for PL control registers
hw/rtl/generated/            PeakRDL-generated AXI-Lite control register block
hw/rtl/eth_control_core.v    Vivado block-design module top
hw/rtl/eth_control_core.sv   Custom commit/status and WS281x consumer implementation
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

The control register map is authored in `hw/regs/pl_control.rdl`. Run `make regs` to regenerate the committed PS header, generated RTL register block, and HTML docs. The generated docs entry point is `docs/regs/pl_control/index.html`; `make regs-check` fails if committed generated artifacts are stale.

Current frame format is pixel-major: for each pixel index, output 0 through output 3 are stored as one `0x00RRGGBB` word each. The frame RAM capacity is `8192` words split into two `4096` word banks, matching the current configured frame size of `4 * 1024` pixels.

## Next Integration Boundary

The PS app currently generates deterministic test frames and commits them through the same `pl_ingest_write_frame()` path that Ethernet receive will use. The Ethernet step should add lwIP UDP receive on the PS and map E1.31 slots into the inactive frame returned by `frame_pipeline_inactive_words()`. Commit remains a single write to `FRAME_COMMIT`; the PL side already consumes committed frames through the WS281x serializer.
