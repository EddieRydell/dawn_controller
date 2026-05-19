# Donder Controller

Production-oriented PYNQ-Z2 foundation for Ethernet-to-PL projects and an E1.31-to-WS2811 light controller.

The foundation is intentionally one path:

```text
Zynq PS bare-metal app
  -> onboard PS Ethernet path, next integration step
  -> frame assembly in PS memory
  -> M_AXI_GP0 AXI-Lite writes
  -> eth_control_core control/status
  -> axil_frame_ram frame window backed by alexforencich/verilog-axi axil_ram
  -> deterministic PL consumer, next integration step
```

The current PL contract already supports full-frame delivery into PL-owned storage. Ethernet receive and WS2811 output should be added behind this same contract, not as parallel scripts or alternate runtime modes.

## Commands

Run from a Xilinx-enabled shell where Vivado, Vitis, Bootgen, XSDB, and hw_server are on `PATH`.

```powershell
make clean
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
hw/rtl/axil_frame_ram.v      Vivado module wrapper around upstream axil_ram
third_party/verilog-axi/     MIT-licensed AXI components from alexforencich/verilog-axi
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
| `0x004` | `VERSION` | RO | Must read `0x00020000` |
| `0x008` | `CONTROL` | RW | Bit 1 clears sticky status |
| `0x00c` | `STATUS` | RO | Bit 0 ready, bit 1 frame overflow |
| `0x010` | `PIN_OUT` | RW | Low four bits drive `pl_data[3:0]` |
| `0x014` | `COUNTER` | RO | Free-running PL clock counter |
| `0x018` | `FRAME_CAPACITY` | RO | PL frame storage capacity in 32-bit words |
| `0x020` | `FRAME_COMMIT` | WO | Write committed word count |
| `0x024` | `FRAME_COUNT` | RO | Accepted frame commits |
| `0x028` | `COMMITTED_WORDS` | RO | Word count from last commit |
| `0x02c` | `FIRST_FRAME_WORD` | RW | First word metadata for commit proof |
| `0x030` | `LAST_FRAME_WORD` | RW | Last word metadata for commit proof |
| `0x034` | `ERROR_COUNT` | RO | Protocol errors detected by PL |

Current frame format is one `0x00RRGGBB` word per pixel. The frame RAM capacity is `8192` words, enough for double the current configured frame size of `4 * 1024` pixels.

## Next Integration Boundary

The PS app currently generates deterministic test frames and commits them through the same `pl_ingest_write_frame()` path that Ethernet receive will use. The Ethernet step should add lwIP UDP receive on the PS and map E1.31 slots into the inactive frame returned by `frame_pipeline_inactive_words()`. The PL side should then replace the PMOD pin proof with a deterministic consumer of the committed frame storage.
