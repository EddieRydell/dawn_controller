.DEFAULT_GOAL := help

PYTHON ?= python
VIVADO ?= vivado
VITIS ?= vitis
BOOTGEN ?= bootgen
POWERSHELL ?= powershell

XSA := build/vivado/donder_controller.xsa
PS_STAMP := build/vitis/.app-built
BOOT_BIN := build/sd/BOOT.BIN

.PHONY: help all hw ps boot run clean

help:
	@echo Common targets:
	@echo   make hw      Build Vivado hardware and export XSA
	@echo   make ps      Build the bare-metal controller app
	@echo   make boot    Package deployable SD-card BOOT.BIN
	@echo   make run     Program FPGA and run the controller app over JTAG
	@echo   make all     Run hw, ps, and boot
	@echo   make clean   Remove generated Xilinx output and root log clutter

all: hw ps boot

hw: $(XSA)

$(XSA): hw/rtl/eth_control_core.v hw/rtl/axil_frame_ram.v third_party/verilog-axi/rtl/axil_ram.v hw/constraints/pynq_z2.xdc hw/scripts/build.tcl hw/scripts/ps_bd.tcl
	$(VIVADO) -mode batch -nolog -nojournal -source hw/scripts/build.tcl

ps: $(PS_STAMP)

$(PS_STAMP): $(XSA) $(wildcard ps/app/*.c) $(wildcard ps/app/*.h) ps/scripts/create_app_vitis.py
	$(VITIS) -s ps/scripts/create_app_vitis.py
	$(PYTHON) -c "from pathlib import Path; Path('$(PS_STAMP)').parent.mkdir(parents=True, exist_ok=True); Path('$(PS_STAMP)').touch()"

boot: $(BOOT_BIN)

$(BOOT_BIN): $(PS_STAMP) ps/scripts/package_boot.py
	$(PYTHON) ps/scripts/package_boot.py --bootgen $(BOOTGEN)

run: $(PS_STAMP)
	$(PYTHON) ps/scripts/run_xsdb_checked.py ps/scripts/run_controller.tcl

clean:
	$(POWERSHELL) -NoProfile -Command "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'build','.Xil','NA'"
	$(POWERSHELL) -NoProfile -Command "$$patterns = @('vivado*.log','vivado*.jou','vivado_*.backup.*','*.wdb','*.vcd','dfx_runtime.txt'); Get-ChildItem -Force -File | Where-Object { $$name = $$_.Name; $$patterns | Where-Object { $$name -like $$_ } } | Remove-Item -Force"
