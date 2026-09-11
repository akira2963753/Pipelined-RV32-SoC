#======================================================
# Design Flow MakeFile (Author: Marco)
#======================================================
.PHONY: vcs_rtl compile run clean

#======================================================
# Project Configuration
#======================================================
top_design=TESTBED
source_file=file.f
TIMESCALE=-timescale=1ns/1ps
SEED?=1

TB_DIR:=$(abspath $(dir $(lastword $(MAKEFILE_LIST))))
RTL_DIR:=$(abspath $(TB_DIR)/../01_RTL)
BUILD_DIR:=$(TB_DIR)/build
SIMV:=$(BUILD_DIR)/simv

#======================================================
# VCS Compile and Simulation
#======================================================
VCS_FLAGS=$(TIMESCALE) \
	-full64 \
	-sverilog \
	-kdb \
	-debug_access+all \
	-assert svaext \
	+define+SVA \
	+define+FSDB \
	+notimingchecks

vcs_rtl: compile run

compile:
	mkdir -p $(BUILD_DIR)
	cd $(RTL_DIR) && vcs $(VCS_FLAGS) \
		-top $(top_design) \
		-f $(source_file) \
		-Mdir=$(BUILD_DIR)/csrc \
		-o $(SIMV) \
		-l $(BUILD_DIR)/compile.log

run:
	cd $(TB_DIR) && $(SIMV) \
		+ntb_random_seed=$(SEED) \
		-l $(BUILD_DIR)/simulation.log

clean:
	rm -rf $(BUILD_DIR) $(TB_DIR)/TESTBED.fsdb
