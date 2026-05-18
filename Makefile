.DEFAULT_GOAL := help

PYTHON ?= python
VIVADO ?= vivado
VITIS ?= vitis
POWERSHELL ?= powershell

.PHONY: help all memmap hw ps run clean clean-generated clean-logs

help:
	@echo Common targets:
	@echo   make memmap      Generate register headers/packages/docs from memory_map.yaml
	@echo   make hw          Build/export Vivado hardware without root logs or journals
	@echo   make ps          Build the Vitis bare-metal PS app
	@echo   make run         Program FPGA, run the bare-metal app, and read PL registers
	@echo   make all         Run memmap, hw, and ps
	@echo   make clean       Remove generated Xilinx output and root log clutter

all: memmap hw ps

memmap:
	$(PYTHON) tools/gen_memory_map.py

hw:
	$(VIVADO) -mode batch -nolog -nojournal -source hw/scripts/build.tcl

ps:
	$(VITIS) -s ps/scripts/create_app_vitis.py

run:
	$(VITIS) -s ps/scripts/run_controller.py

clean: clean-generated clean-logs

clean-generated:
	$(POWERSHELL) -NoProfile -Command "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'build','.Xil','xsim.dir','NA'"

clean-logs:
	$(POWERSHELL) -NoProfile -Command "Remove-Item -Force -ErrorAction SilentlyContinue 'vivado*.log','vivado*.jou','vivado_*.backup.*','xvlog.log','xvlog.pb','dfx_runtime.txt'"
