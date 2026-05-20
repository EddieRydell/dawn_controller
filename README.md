# Donder Controller

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

For UART telemetry:

```powershell
make logs PORT=COMx
```

For a host-side E1.31 packet source:

```powershell
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

The control register map is authored in `hw/regs/pl_control.rdl`. Run `make regs` to regenerate the committed PS header and RTL register block, plus local HTML docs under `build/docs/regs/pl_control/index.html`. Run `make regs-check` to fail if committed generated artifacts are stale.

Current frame format is output-major: each bank stores output 0 pixels first, then output 1, output 2, and output 3. Word `0` is output 0 pixel 0, word `1023` is output 0 pixel 1023, word `1024` is output 1 pixel 0, and so on. Each word is `0x00RRGGBB`. The frame RAM capacity is `8192` words split into two `4096` word banks, matching the current configured frame size of `4 * 1024` pixels.

## Ethernet E1.31 Bring-Up

The PS app uses a static direct Ethernet link:

```text
Host NIC: 192.168.7.1/24
Board:    192.168.7.2/24
Gateway:  0.0.0.0
UDP port: 5568
```

Configure the host Ethernet adapter manually to `192.168.7.1` with netmask `255.255.255.0`, connect it directly to the PYNQ-Z2 Ethernet port, then run the app and observe UART logs:

```powershell
make run
make logs PORT=COMx
```

On Windows with the tested USB-C adapter, the board link appears as `Ethernet 2` / `ASIX USB to Gigabit Ethernet Family Adapter`. If the alias differs, find it with `Get-NetAdapter`. To make the static host address persistent, run PowerShell as Administrator:

```powershell
Set-NetIPInterface -InterfaceAlias "Ethernet 2" -AddressFamily IPv4 -Dhcp Disabled
New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress 192.168.7.1 -PrefixLength 24
```

If `192.168.7.1/24` already exists, only the `Set-NetIPInterface` command is needed. Verify the link before sending packets:

```powershell
Get-NetIPAddress -InterfaceAlias "Ethernet 2" -AddressFamily IPv4
Test-Connection 192.168.7.2 -Count 2
```

Expected startup telemetry includes `net status=ready`, `ip=192.168.7.2`, and `udp_port=5568`. Runtime status is machine-readable:

```text
e131_status link=... rx_packets=... rx_bytes=... e131_valid=... e131_rejected=... universes_seen=... frames_committed=... frames_dropped=... last_universe=... last_sequence=... last_error=...
```

Send deterministic E1.31 from the host:

```powershell
make e131-send
python ps/tools/e131_send.py --dest-ip 192.168.7.2 --pattern bars --packet-count 10 --rate 30
```

The sender is send-only. UART remains the canonical observer. A successful packet test shows increasing `rx_packets`, `e131_valid`, and `frames_committed`. Malformed packets or packets outside the configured universe range increment `e131_rejected` and do not commit a frame.

E1.31 universe data is accepted starting at `DONDER_FIRST_UNIVERSE`. RGB slots are interpreted as the same linear output-major stream used by PL frame RAM: output 0 pixels first, then output 1, output 2, and output 3. The PS writes those slots directly into the inactive frame bank before committing through `frame_pipeline_commit()`.
