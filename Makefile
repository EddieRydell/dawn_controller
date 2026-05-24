.DEFAULT_GOAL := help

PYTHON ?= python
VIVADO ?= vivado
XVLOG ?= xvlog
XELAB ?= xelab
XSIM ?= xsim
VITIS ?= vitis
BOOTGEN ?= bootgen
HOST_CC ?= gcc
PORT ?=
BAUD ?= 115200

XSA := build/vivado/dawn_controller.xsa
BITSTREAM := build/vivado/dawn_controller.runs/impl_1/dawn_system_wrapper.bit
PS_STAMP := build/vitis/.app-built
BOOT_BIN := build/sd/BOOT.BIN
RTL_CHECK_DIR := build/rtl-check
RTL_SIM_DIR := build/rtl-sim
SIDE_EFFECT_DIR := build/tool-side-effects
PS_HOST_E131_TEST_EXE := build/ps-host-test/e131_host_tests.exe
PS_HOST_FRAME_TEST_EXE := build/ps-host-test/frame_pipeline_host_tests.exe

define collect_root_side_effects
	$(PYTHON) make_helpers.py collect-root-side-effects $(SIDE_EFFECT_DIR)
endef

.PHONY: help all regs regs-check rtl-check rtl-sim hw ps ps-host-test boot run logs e131-send bench-e131 clean

help:
	@echo Common targets:
	@echo   make hw      Build Vivado hardware and export XSA
	@echo   make regs    Regenerate SystemRDL-derived software, RTL, and local docs
	@echo   make regs-check  Check committed register artifacts are fresh
	@echo   make rtl-check  Run fast Vivado Verilog syntax checks
	@echo   make rtl-sim  Run focused WS281x consumer RTL simulation
	@echo   make ps      Build the bare-metal controller app
	@echo   make ps-host-test  Build and run host-side PS protocol tests
	@echo   make boot    Package deployable SD-card BOOT.BIN
	@echo   make run     Program FPGA and run the controller app over JTAG
	@echo   make logs   Stream UART telemetry at BAUD=115200
	@echo   make logs PORT=COMx  Stream UART telemetry from an explicit port
	@echo   make e131-send  Send deterministic E1.31 UDP to 192.168.7.2:5568
	@echo   make bench-e131  Run the 30-output E1.31 throughput benchmark
	@echo   make all     Run hw, ps, and boot
	@echo   make clean   Remove generated Xilinx output and root log clutter

all: hw ps boot

regs:
	$(PYTHON) hw/regs/generate_regs.py
	$(collect_root_side_effects)

regs-check:
	$(PYTHON) hw/regs/generate_regs.py --check
	$(collect_root_side_effects)

rtl-check: regs-check
	$(PYTHON) make_helpers.py mkdir $(RTL_CHECK_DIR)
	cd $(RTL_CHECK_DIR) && $(XVLOG) -sv ../../hw/rtl/generated/pl_config_pkg.sv ../../hw/rtl/generated/pl_control_regs_pkg.sv ../../hw/rtl/generated/pl_control_regs.sv ../../hw/rtl/pl_frame_control.sv ../../hw/rtl/ws281x_frame_consumer.sv ../../hw/rtl/ws281x_controller_core.v ../../hw/rtl/axil_frame_ram.v
	$(collect_root_side_effects)

rtl-sim: regs-check
	$(PYTHON) make_helpers.py mkdir $(RTL_SIM_DIR)
	cd $(RTL_SIM_DIR) && $(XVLOG) -sv ../../hw/rtl/generated/pl_config_pkg.sv ../../hw/rtl/generated/pl_control_regs_pkg.sv ../../hw/rtl/generated/pl_control_regs.sv ../../hw/rtl/pl_frame_control.sv ../../hw/rtl/ws281x_frame_consumer.sv ../../hw/rtl/ws281x_controller_core.v ../../hw/rtl/axil_frame_ram.v ../../hw/sim/tb_ws281x_consumer.v
	cd $(RTL_SIM_DIR) && $(XELAB) tb_ws281x_consumer -s tb_ws281x_consumer_sim
	cd $(RTL_SIM_DIR) && $(XSIM) tb_ws281x_consumer_sim -runall
	$(collect_root_side_effects)

hw: $(XSA) $(BITSTREAM)

$(XSA) $(BITSTREAM): hw/rtl/generated/pl_config_pkg.sv hw/rtl/generated/pl_control_regs_pkg.sv hw/rtl/generated/pl_control_regs.sv hw/rtl/pl_frame_control.sv hw/rtl/ws281x_frame_consumer.sv hw/rtl/ws281x_controller_core.v hw/rtl/axil_frame_ram.v hw/constraints/pynq_z2.xdc hw/scripts/build.tcl hw/scripts/ps_bd.tcl | regs-check
	$(PYTHON) make_helpers.py mkdir build/vivado
	cd build/vivado && $(VIVADO) -mode batch -source ../../hw/scripts/build.tcl
	$(collect_root_side_effects)

ps: $(PS_STAMP)

ps-host-test: $(PS_HOST_E131_TEST_EXE) $(PS_HOST_FRAME_TEST_EXE)
	$(PS_HOST_E131_TEST_EXE)
	$(PS_HOST_FRAME_TEST_EXE)

$(PS_HOST_E131_TEST_EXE): ps/tests/e131_host_tests.c ps/app/e131_parser.c ps/app/e131_parser.h ps/app/e131_receiver.c ps/app/e131_receiver.h ps/app/app_config.c ps/app/app_config.h ps/app/generated/pl_config.h ps/app/frame_pipeline.h Makefile
	$(PYTHON) make_helpers.py mkdir build/ps-host-test
	$(HOST_CC) -std=c99 -Wall -Wextra -Werror -Ips/app -o $(PS_HOST_E131_TEST_EXE) ps/tests/e131_host_tests.c ps/app/e131_parser.c ps/app/e131_receiver.c ps/app/app_config.c

$(PS_HOST_FRAME_TEST_EXE): ps/tests/frame_pipeline_host_tests.c ps/app/frame_pipeline.c ps/app/frame_pipeline.h ps/app/pl_ingest.h ps/app/app_config.h ps/app/generated/pl_config.h Makefile
	$(PYTHON) make_helpers.py mkdir build/ps-host-test
	$(HOST_CC) -std=c11 -Wall -Wextra -Werror -Ips/app -o $(PS_HOST_FRAME_TEST_EXE) ps/tests/frame_pipeline_host_tests.c ps/app/frame_pipeline.c

$(PS_STAMP): $(XSA) $(BITSTREAM) $(wildcard ps/app/*.c) $(wildcard ps/app/*.h) ps/scripts/create_app_vitis.py Makefile | regs-check
	$(PYTHON) make_helpers.py mkdir build/vitis
	cd build/vitis && $(VITIS) -s ../../ps/scripts/create_app_vitis.py
	$(collect_root_side_effects)

boot: $(BOOT_BIN)

$(BOOT_BIN): $(PS_STAMP) ps/scripts/package_boot.py
	$(PYTHON) ps/scripts/package_boot.py --bootgen $(BOOTGEN)
	$(collect_root_side_effects)

run: $(PS_STAMP)
	$(PYTHON) ps/scripts/run_xsdb_checked.py ps/scripts/run_controller.tcl
	$(collect_root_side_effects)

logs:
	$(PYTHON) make_helpers.py logs --port "$(PORT)" --baud $(BAUD)

e131-send:
	$(PYTHON) ps/tools/e131_send.py --dest-ip 192.168.7.2 --port 5568

bench-e131:
	$(PYTHON) ps/tools/e131_benchmark.py

clean:
	$(PYTHON) make_helpers.py remove-paths build .Xil NA
	$(PYTHON) make_helpers.py clean-root-files
