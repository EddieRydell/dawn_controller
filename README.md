# Donder Controller

Bare-metal Zynq/PYNQ-Z2 scaffold for a WS281x Christmas light controller.

The intended architecture is:

```text
Vixen -> Ethernet -> Zynq PS bare-metal UDP receiver -> shared frame buffers -> PL WS2811 engines
```

The onboard PYNQ-Z2 Ethernet PHY is connected to the Zynq PS MIO pins, so this project starts with packet ingress on the PS and keeps deterministic pixel timing in PL.

## Layout

```text
hw/
  constraints/       XDC files
  scripts/           Vivado batch Tcl
  rtl/               PL SystemVerilog
ps/
  app/               bare-metal C application
  scripts/           Vitis batch scripts
docs/
  memory_map.md      PS/PL register and buffer contract
```

## First Build Targets

1. Generate/export a Vivado hardware design with Zynq PS, AXI-Lite control, and an AXI HP path for PL frame reads.
2. Build the bare-metal PS app from batch mode.
3. Generate a known sample frame in the PS.
4. Commit the frame to PL at a deterministic boundary.
5. Later: receive UDP port `5568` E1.31 packets on the PS and map them into the same framebuffer.

The current program generates sample pixel data only in the PS. The PL must not contain a sample-pattern generator or alternate data source. The PL register contract is centralized in `memory_map.yaml`; generated C/SystemVerilog/docs outputs are derived from that file.

## Tooling

Vivado/Vitis are expected to be run in batch mode. If the Xilinx tools are not on `PATH`, launch these from the Xilinx command prompt or call the full executable paths.

```powershell
make memmap
make hw
make ps
make run
```

`make all` runs `memmap`, `hw`, and `ps`. `make hw` suppresses Vivado's root-level log and journal files.

`memory_map.yaml` is the source of truth for PS/PL registers. Do not edit `ps/app/pl_regs.h`, `hw/rtl/regs_pkg.sv`, or `docs/memory_map.md` by hand.

The PS app build uses the current Vitis Python CLI flow. The script creates a platform from the exported XSA, configures the standalone domain, imports `ps/app`, and builds the application component. Older XSCT/Tcl app-generation scripts are intentionally not kept in this tree because they hang in Vitis 2025.1 on this machine.

`make run` programs the main FPGA bitstream, runs the generated FSBL to initialize PS/DDR, downloads the single bare-metal app, and reads back the PL registers that the app configured over AXI.

## Software Notes

The PS app currently generates one deterministic sample frame in C, flushes it from cache, writes the framebuffer base address to PL, and commits it. E1.31 receive code is intentionally not in the build yet.

The hot path should stay boring:

```text
UDP callback -> validate E1.31 -> map universe slots -> write inactive frame bank -> commit register
```

No pixel timing belongs in PS code.
