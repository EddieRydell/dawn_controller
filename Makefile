.DEFAULT_GOAL := help

PYTHON ?= python
VIVADO ?= vivado
XVLOG ?= xvlog
XELAB ?= xelab
XSIM ?= xsim
VITIS ?= vitis
BOOTGEN ?= bootgen
POWERSHELL ?= powershell

XSA := build/vivado/donder_controller.xsa
PS_STAMP := build/vitis/.app-built
BOOT_BIN := build/sd/BOOT.BIN
SIM_DIR := build/xsim

.PHONY: help all rtl-check rtl-sim hw ps boot run clean

help:
	@echo Common targets:
	@echo   make hw      Build Vivado hardware and export XSA
	@echo   make rtl-check  Run fast Vivado Verilog syntax checks
	@echo   make rtl-sim  Run focused WS281x consumer RTL simulation
	@echo   make ps      Build the bare-metal controller app
	@echo   make boot    Package deployable SD-card BOOT.BIN
	@echo   make run     Program FPGA and run the controller app over JTAG
	@echo   make all     Run hw, ps, and boot
	@echo   make clean   Remove generated Xilinx output and root log clutter

all: hw ps boot

rtl-check: hw/rtl/pl_contract.vh
	$(POWERSHELL) -NoProfile -Command "New-Item -ItemType Directory -Force '$(SIM_DIR)' | Out-Null"
	cd $(SIM_DIR) && $(XVLOG) --nolog -i ../../hw/rtl -sv ../../hw/rtl/eth_control_core.v ../../hw/rtl/axil_frame_ram.v
	$(POWERSHELL) -NoProfile -Command "Get-ChildItem -Force -File '$(SIM_DIR)' | Where-Object { $$_.Extension -in '.log','.jou','.pb' } | Remove-Item -Force"

rtl-sim: hw/rtl/pl_contract.vh
	$(POWERSHELL) -NoProfile -Command "New-Item -ItemType Directory -Force '$(SIM_DIR)' | Out-Null"
	cd $(SIM_DIR) && $(XVLOG) --nolog -i ../../hw/rtl -sv ../../hw/rtl/eth_control_core.v ../../hw/rtl/axil_frame_ram.v ../../hw/sim/tb_ws281x_consumer.v
	cd $(SIM_DIR) && $(XELAB) --nolog tb_ws281x_consumer -s tb_ws281x_consumer_sim
	cd $(SIM_DIR) && $(XSIM) --nolog tb_ws281x_consumer_sim -runall
	$(POWERSHELL) -NoProfile -Command "Get-ChildItem -Force -File '$(SIM_DIR)' | Where-Object { $$_.Extension -in '.log','.jou','.pb' } | Remove-Item -Force"

hw: $(XSA)

$(XSA): hw/rtl/pl_contract.vh hw/rtl/eth_control_core.v hw/rtl/axil_frame_ram.v hw/constraints/pynq_z2.xdc hw/scripts/build.tcl hw/scripts/ps_bd.tcl
	$(VIVADO) -mode batch -nolog -nojournal -source hw/scripts/build.tcl

ps: $(PS_STAMP)

$(PS_STAMP): $(XSA) $(wildcard ps/app/*.c) $(wildcard ps/app/*.h) ps/scripts/create_app_vitis.py Makefile
	$(VITIS) -s ps/scripts/create_app_vitis.py

boot: $(BOOT_BIN)

$(BOOT_BIN): $(PS_STAMP) ps/scripts/package_boot.py
	$(PYTHON) ps/scripts/package_boot.py --bootgen $(BOOTGEN)

run: $(PS_STAMP)
	$(PYTHON) ps/scripts/run_xsdb_checked.py ps/scripts/run_controller.tcl

clean:
	$(POWERSHELL) -NoProfile -Command "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'build','.Xil','NA'"
	$(POWERSHELL) -NoProfile -Command "$$patterns = @('vivado*.log','vivado*.jou','vivado_*.backup.*','*.log','*.jou','*.pb','*.wdb','*.vcd','dfx_runtime.txt'); Get-ChildItem -Force -File | Where-Object { $$name = $$_.Name; $$patterns | Where-Object { $$name -like $$_ } } | Remove-Item -Force"
