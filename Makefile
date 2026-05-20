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
BITSTREAM := build/vivado/donder_controller.runs/impl_1/donder_system_wrapper.bit
PS_STAMP := build/vitis/.app-built
BOOT_BIN := build/sd/BOOT.BIN
RTL_CHECK_DIR := build/rtl-check
RTL_SIM_DIR := build/rtl-sim

.PHONY: help all regs regs-check rtl-check rtl-sim hw ps boot run clean

help:
	@echo Common targets:
	@echo   make hw      Build Vivado hardware and export XSA
	@echo   make regs    Regenerate SystemRDL-derived software, RTL, and local docs
	@echo   make regs-check  Check committed register artifacts are fresh
	@echo   make rtl-check  Run fast Vivado Verilog syntax checks
	@echo   make rtl-sim  Run focused WS281x consumer RTL simulation
	@echo   make ps      Build the bare-metal controller app
	@echo   make boot    Package deployable SD-card BOOT.BIN
	@echo   make run     Program FPGA and run the controller app over JTAG
	@echo   make all     Run hw, ps, and boot
	@echo   make clean   Remove generated Xilinx output and root log clutter

all: hw ps boot

regs:
	$(PYTHON) hw/regs/generate_regs.py

regs-check:
	$(PYTHON) hw/regs/generate_regs.py --check

rtl-check: regs-check
	$(POWERSHELL) -NoProfile -Command "New-Item -ItemType Directory -Force '$(RTL_CHECK_DIR)' | Out-Null"
	cd $(RTL_CHECK_DIR) && $(XVLOG) -sv ../../hw/rtl/generated/pl_control_regs_pkg.sv ../../hw/rtl/generated/pl_control_regs.sv ../../hw/rtl/pl_frame_control.sv ../../hw/rtl/ws281x_frame_consumer.sv ../../hw/rtl/ws281x_controller_core.v ../../hw/rtl/axil_frame_ram.v

rtl-sim: regs-check
	$(POWERSHELL) -NoProfile -Command "New-Item -ItemType Directory -Force '$(RTL_SIM_DIR)' | Out-Null"
	cd $(RTL_SIM_DIR) && $(XVLOG) -sv ../../hw/rtl/generated/pl_control_regs_pkg.sv ../../hw/rtl/generated/pl_control_regs.sv ../../hw/rtl/pl_frame_control.sv ../../hw/rtl/ws281x_frame_consumer.sv ../../hw/rtl/ws281x_controller_core.v ../../hw/rtl/axil_frame_ram.v ../../hw/sim/tb_ws281x_consumer.v
	cd $(RTL_SIM_DIR) && $(XELAB) tb_ws281x_consumer -s tb_ws281x_consumer_sim
	cd $(RTL_SIM_DIR) && $(XSIM) tb_ws281x_consumer_sim -runall

hw: $(XSA) $(BITSTREAM)

$(XSA) $(BITSTREAM): hw/rtl/generated/pl_control_regs_pkg.sv hw/rtl/generated/pl_control_regs.sv hw/rtl/pl_frame_control.sv hw/rtl/ws281x_frame_consumer.sv hw/rtl/ws281x_controller_core.v hw/rtl/axil_frame_ram.v hw/constraints/pynq_z2.xdc hw/scripts/build.tcl hw/scripts/ps_bd.tcl | regs-check
	$(POWERSHELL) -NoProfile -Command "New-Item -ItemType Directory -Force 'build/vivado' | Out-Null"
	cd build/vivado && $(VIVADO) -mode batch -source ../../hw/scripts/build.tcl

ps: $(PS_STAMP)

$(PS_STAMP): $(XSA) $(BITSTREAM) $(wildcard ps/app/*.c) $(wildcard ps/app/*.h) ps/scripts/create_app_vitis.py Makefile | regs-check
	$(POWERSHELL) -NoProfile -Command "New-Item -ItemType Directory -Force 'build/vitis' | Out-Null"
	cd build/vitis && $(VITIS) -s ../../ps/scripts/create_app_vitis.py

boot: $(BOOT_BIN)

$(BOOT_BIN): $(PS_STAMP) ps/scripts/package_boot.py
	$(PYTHON) ps/scripts/package_boot.py --bootgen $(BOOTGEN)

run: $(PS_STAMP)
	$(PYTHON) ps/scripts/run_xsdb_checked.py ps/scripts/run_controller.tcl

clean:
	$(POWERSHELL) -NoProfile -Command "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'build','.Xil','NA'"
	$(POWERSHELL) -NoProfile -Command "$$patterns = @('vivado*.log','vivado*.jou','vivado_*.backup.*','*.log','*.jou','*.pb','*.wdb','*.vcd','dfx_runtime.txt'); Get-ChildItem -Force -File | Where-Object { $$name = $$_.Name; $$patterns | Where-Object { $$name -like $$_ } } | Remove-Item -Force"
