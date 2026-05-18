.DEFAULT_GOAL := help

PYTHON ?= python
VIVADO ?= vivado
VITIS ?= vitis
POWERSHELL ?= powershell

.PHONY: help all memmap hw ps run sim sim-pl-top sim-controller-core clean clean-generated clean-logs

help:
	@echo Common targets:
	@echo   make memmap      Generate register headers/packages/docs from memory_map.yaml
	@echo   make hw          Build/export Vivado hardware without root logs or journals
	@echo   make ps          Build the Vitis bare-metal PS app
	@echo   make run         Program FPGA, run the bare-metal app, and read PL registers
	@echo   make sim         Run RTL testbenches without root log clutter
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

sim: sim-pl-top sim-controller-core

sim-pl-top:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File tools/run_xsim.ps1 -Top pl_top_tb -Sources "hw/rtl/frame_reader.sv,hw/rtl/ws2811_tx.sv,hw/rtl/output_bank.sv,hw/rtl/pl_top.sv,hw/sim/pl_top_tb.sv"

sim-controller-core:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File tools/run_xsim.ps1 -Top controller_core_bd_tb -Sources "hw/rtl/regs_pkg.sv,hw/rtl/axil_reg_if_rd.v,hw/rtl/axil_reg_if_wr.v,hw/rtl/axil_reg_if.v,hw/rtl/controller_regs.sv,hw/rtl/axi_regs.sv,hw/rtl/frame_reader.sv,hw/rtl/ws2811_tx.sv,hw/rtl/output_bank.sv,hw/rtl/pl_top.sv,hw/rtl/controller_core_bd.v,hw/sim/controller_core_bd_tb.sv"

clean: clean-generated clean-logs

clean-generated:
	$(POWERSHELL) -NoProfile -Command "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'build','.Xil','xsim.dir','NA'"

clean-logs:
	$(POWERSHELL) -NoProfile -Command "$$patterns = @('vivado*.log','vivado*.jou','vivado_*.backup.*','xvlog.log','xvlog.pb','xelab.log','xelab.pb','xsim.log','xsim.jou','xsim.pb','xsim_*.backup.log','xsim_*.backup.jou','*.wdb','*.vcd','dfx_runtime.txt'); Get-ChildItem -Force -File | Where-Object { $$name = $$_.Name; $$patterns | Where-Object { $$name -like $$_ } } | Remove-Item -Force"
