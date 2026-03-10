# =============================================================================
# Makefile — DDR4 AXI4 Slave UVM Testbench
# =============================================================================
#
# Simulator selection (export SIM=questa | vcs | xcelium | verilator):
#   make uvm-sim SIM=questa
#   make uvm-sim SIM=vcs
#   make uvm-sim SIM=xcelium
#   make uvm-sim SIM=verilator   # requires Verilator ≥5.020 + UVM source
#
# Verilator UVM source (Accellera UVM 1.2 or UVM 2.0):
#   export VERILATOR_UVM_HOME=/path/to/uvm-1.2   (default: ../uvm-1.2)
#
# Default test (override with TEST=<uvm_testname>):
#   make uvm-sim TEST=ddr4_axi4_smoke_test
#
# All targets mirror the BFM Makefile structure.
# =============================================================================

SIM        ?= verilator
TEST       ?= ddr4_axi4_full_test
WORK_DIR   ?= work
LOG_DIR    ?= logs

# Source files (order matters: pkg → if → dut → tb)
UVM_SRCS   := ../ddr4_axi4_pkg.sv \
              ddr4_axi4_if.sv \
              ../ddr4_axi4_slave.sv \
              ddr4_axi4_uvm_pkg.sv \
              ddr4_axi4_seqs_pkg.sv \
              ddr4_axi4_tests.sv \
              ddr4_axi4_uvm_tb.sv

# DDR4 parameter sweep axes (same as BFM Makefile)
SPEED_GRADES    := 1600 1866 2133 2400 2666 2933 3200
AXI_WIDTHS      := 32 64
TIMING_MODELS   := 0 1
RANDOM_DELAYS   := 0 1
AXI_CLK_PERIODS := 1 2 10 20

# ── Simulator-specific flags ─────────────────────────────────────────────────
ifeq ($(SIM),questa)
    VCOM    := vcom -sv -2012
    VLOG    := vlog -sv -2012 -mfcu -suppress 2583 -suppress 2181
    VSIM    := vsim -batch -do "run -all; quit -f"
    ELAB    := # vlog already elaborates
    COV_RUN := $(VSIM) -coverage
    COV_RPT := vcover report -details -html -output

    define compile_srcs
	mkdir -p $(WORK_DIR)
	vlib $(WORK_DIR)/work_lib 2>/dev/null || true
	vmap work $(WORK_DIR)/work_lib
	$(VLOG) -work work +incdir+$(WORK_DIR) \
	    +define+UVM_NO_DEPRECATED \
	    -uvmhome $(QUESTA_HOME)/verilog_src/uvm-1.2 \
	    $(EXTRA_FLAGS) $(UVM_SRCS)
    endef

    define run_test
	$(VSIM) \
	    +UVM_TESTNAME=$(TEST) \
	    +UVM_VERBOSITY=UVM_MEDIUM \
	    $(EXTRA_SIM_FLAGS) \
	    -do "coverage save -assert -cvg $(LOG_DIR)/uvm_cov.ucdb; run -all; quit -f" \
	    work.ddr4_axi4_uvm_tb 2>&1 | tee $(LOG_DIR)/uvm_run.log
    endef

    define merge_cov
	vcover merge $(LOG_DIR)/uvm_merged.ucdb $(LOG_DIR)/uvm_cov*.ucdb
    endef

    define report_cov
	vcover report -details -html -output $(LOG_DIR)/uvm_cov_html/ \
	    $(LOG_DIR)/uvm_merged.ucdb
    endef

else ifeq ($(SIM),vcs)
    VLOGAN  := vlogan -full64 -sverilog -timescale=1ns/1ps
    VCSFLAGS:= -full64 -sverilog -timescale=1ns/1ps \
               +define+UVM_NO_DEPRECATED \
               -ntb_opts uvm-1.2 \
               -cm line+tgl+branch+assert \
               -cm_dir $(LOG_DIR)/vcs_cov.vdb
    SIMFLAGS:= -cm line+tgl+branch+assert \
               -cm_dir $(LOG_DIR)/vcs_cov.vdb \
               +UVM_VERBOSITY=UVM_MEDIUM

    define compile_srcs
	mkdir -p $(LOG_DIR)
	cd $(WORK_DIR) || (mkdir -p $(WORK_DIR) && cd $(WORK_DIR)); \
	vcs $(VCSFLAGS) $(EXTRA_FLAGS) \
	    +incdir+. \
	    $(addprefix ../,$(UVM_SRCS)) \
	    -o simv_uvm \
	    2>&1 | tee $(abspath $(LOG_DIR))/vcs_compile.log
    endef

    define run_test
	$(WORK_DIR)/simv_uvm \
	    +UVM_TESTNAME=$(TEST) \
	    $(SIMFLAGS) $(EXTRA_SIM_FLAGS) \
	    2>&1 | tee $(LOG_DIR)/uvm_run.log
    endef

    define merge_cov
	urg -dir $(LOG_DIR)/vcs_cov.vdb -dbname $(LOG_DIR)/vcs_merged.vdb
    endef

    define report_cov
	urg -dir $(LOG_DIR)/vcs_merged.vdb -report $(LOG_DIR)/vcs_cov_rpt -format both
    endef

else ifeq ($(SIM),xcelium)
    XMFLAGS := -sv -uvm -uvmhome CDNS-1.2 \
               -timescale 1ns/1ps \
               +define+UVM_NO_DEPRECATED \
               -coverage all -covwork $(LOG_DIR)/xm_cov

    define compile_srcs
	mkdir -p $(LOG_DIR)
	xrun $(XMFLAGS) $(EXTRA_FLAGS) \
	    +incdir+. \
	    $(UVM_SRCS) \
	    -elaborate \
	    2>&1 | tee $(LOG_DIR)/xm_compile.log
    endef

    define run_test
	xrun $(XMFLAGS) $(EXTRA_SIM_FLAGS) \
	    +UVM_TESTNAME=$(TEST) \
	    +UVM_VERBOSITY=UVM_MEDIUM \
	    $(UVM_SRCS) \
	    2>&1 | tee $(LOG_DIR)/uvm_run.log
    endef

    define merge_cov
	imc -execcmd "load -run $(LOG_DIR)/xm_cov; merge -out $(LOG_DIR)/xm_merged"
    endef

    define report_cov
	imc -execcmd "load -run $(LOG_DIR)/xm_merged; report -detail -html -out $(LOG_DIR)/xm_cov_html"
    endef

else ifeq ($(SIM),verilator)
    # ── Verilator ≥5.020 + Accellera UVM source ─────────────────────────────
    # Set VERILATOR_UVM_HOME to the directory that contains uvm_pkg.sv and
    # uvm_macros.svh (typically the src/ sub-directory of the UVM release).
    VERILATOR          ?= verilator
    VERILATOR_UVM_HOME ?= ../uvm-1.2
    VLT_OBJ_DIR        := obj_dir_uvm
    VLT_BIN            := $(VLT_OBJ_DIR)/Vddr4_axi4_uvm_tb

    VLT_FLAGS := --sv --timing --binary --coverage \
                 --build-jobs 0 \
                 -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
                 -Wno-INITIALDLY   -Wno-PROCASSINIT -Wno-MODDUP \
                 -Wno-TIMESCALEMOD -Wno-UNPACKED \
                 -Wno-BLKANDNBLK   -Wno-LITENDIAN   -Wno-REALCVT \
                 -Wno-COVERIGN \
                 -Wno-UNSIGNED \
                 +define+UVM_NO_DPI \
                 --top-module ddr4_axi4_uvm_tb \
                 --Mdir $(VLT_OBJ_DIR) \
                 -o Vddr4_axi4_uvm_tb

    # verilator_coverage uses .dat files written by the binary at runtime
    VLT_COV_DAT := coverage.dat

    define compile_srcs
	mkdir -p $(LOG_DIR)
	$(VERILATOR) $(VLT_FLAGS) $(EXTRA_FLAGS) \
	    +incdir+$(VERILATOR_UVM_HOME)/src \
	    +incdir+. \
	    +incdir+.. \
	    $(VERILATOR_UVM_HOME)/src/uvm_pkg.sv \
	    $(UVM_SRCS) \
	    2>&1 | tee $(LOG_DIR)/vlt_compile.log
    endef

    define run_test
	$(VLT_BIN) \
	    +UVM_TESTNAME=$(TEST) \
	    +UVM_VERBOSITY=UVM_MEDIUM \
	    $(EXTRA_SIM_FLAGS) \
	    2>&1 | tee $(LOG_DIR)/uvm_run.log
	cp $(VLT_COV_DAT) $(LOG_DIR)/vlt_cov_$(TEST).dat 2>/dev/null || true
    endef

    define merge_cov
	verilator_coverage \
	    -write $(LOG_DIR)/vlt_merged.dat \
	    $(wildcard $(LOG_DIR)/vlt_cov_*.dat)
    endef

    define report_cov
	mkdir -p $(LOG_DIR)/vlt_cov_html
	verilator_coverage --annotate $(LOG_DIR)/vlt_cov_html/ \
	    $(LOG_DIR)/vlt_merged.dat
	@echo "Coverage annotation written to $(LOG_DIR)/vlt_cov_html/"
    endef

else
    $(error "Unknown simulator: SIM=$(SIM).  Use SIM=questa|vcs|xcelium|verilator")
endif

# ── Common phony targets ─────────────────────────────────────────────────────
.PHONY: all clean uvm-sim uvm-compile uvm-test-all \
        uvm-cov uvm-cov-full \
        uvm-sim-1g uvm-sim-no-timing uvm-sim-rand uvm-sim-verbose \
        uvm-dma-test uvm-smoke-test \
        help

all: uvm-sim

## uvm-sim         – compile and run ddr4_axi4_full_test (DDR4-2400, AXI32, timing=1)
uvm-sim:
	mkdir -p $(LOG_DIR)
	$(call compile_srcs)
	$(call run_test)

## uvm-compile     – compile only, do not run
uvm-compile:
	mkdir -p $(LOG_DIR)
	$(call compile_srcs)

## uvm-smoke-test  – single_rw + burst_incr only (fast sanity check)
uvm-smoke-test:
	$(MAKE) uvm-sim TEST=ddr4_axi4_smoke_test

## uvm-dma-test    – DMA concurrent + outstanding + true outstanding sequences
uvm-dma-test:
	$(MAKE) uvm-sim TEST=ddr4_axi4_dma_test

## uvm-sim-1g      – AXI clock at 1 GHz (wtr_stress, refresh contention)
uvm-sim-1g:
	$(MAKE) uvm-sim \
	    EXTRA_FLAGS="-GDDR4_SPEED=2400 -GAXI_DW=32 -GENABLE_TIMING=1 -GCLK_PERIOD_NS=1" \
	    TEST=ddr4_axi4_full_test

## uvm-sim-no-timing – ENABLE_TIMING=0 (covers no-timing path in slave)
uvm-sim-no-timing:
	$(MAKE) uvm-sim \
	    EXTRA_FLAGS="-GDDR4_SPEED=2400 -GAXI_DW=32 -GENABLE_TIMING=0" \
	    TEST=ddr4_axi4_full_test

## uvm-sim-rand    – RANDOM_DELAY_EN=1 (covers random-delay path)
uvm-sim-rand:
	$(MAKE) uvm-sim \
	    EXTRA_FLAGS="-GDDR4_SPEED=2400 -GAXI_DW=32 -GENABLE_TIMING=1 -GRANDOM_DELAY_EN=1" \
	    TEST=ddr4_axi4_full_test

## uvm-sim-verbose – VERBOSE_MODE=1 (covers $display branches in slave)
uvm-sim-verbose:
	$(MAKE) uvm-sim \
	    EXTRA_FLAGS="-GDDR4_SPEED=2400 -GAXI_DW=32 -GENABLE_TIMING=1 -GVERBOSE_MODE=1" \
	    TEST=ddr4_axi4_full_test

## uvm-cov         – report coverage from last uvm-sim run
uvm-cov:
	@[ -d $(LOG_DIR) ] || { echo "Run 'make uvm-sim' first"; exit 1; }
	$(call report_cov)
	@echo "Coverage report written to $(LOG_DIR)/"

## uvm-cov-full    – run all variants, merge coverage, report
uvm-cov-full:
	@echo "Running all UVM coverage variants..."
	$(MAKE) uvm-sim
	$(MAKE) uvm-sim-1g       EXTRA_SIM_FLAGS="+UVM_TESTNAME=ddr4_axi4_full_test"
	$(MAKE) uvm-sim-no-timing EXTRA_SIM_FLAGS="+UVM_TESTNAME=ddr4_axi4_full_test"
	$(MAKE) uvm-sim-rand     EXTRA_SIM_FLAGS="+UVM_TESTNAME=ddr4_axi4_full_test"
	$(MAKE) uvm-sim-verbose  EXTRA_SIM_FLAGS="+UVM_TESTNAME=ddr4_axi4_full_test"
	@echo "Merging coverage data..."
	$(call merge_cov)
	$(call report_cov)
	@echo "Full coverage merged report written to $(LOG_DIR)/"

# ── Full parameter sweep (mirrors BFM test-all) ───────────────────────────────
#
# Iterates over SPEED_GRADES × AXI_WIDTHS × TIMING_MODELS × RANDOM_DELAYS × AXI_CLK_PERIODS
# Reports PASS/FAIL per configuration.

## uvm-test-all    – run ddr4_axi4_full_test across all parameter combinations
uvm-test-all: $(UVM_SRCS)
	@mkdir -p $(LOG_DIR); \
	pass=0; fail=0; total=0; \
	for spd in $(SPEED_GRADES); do \
	  for dw in $(AXI_WIDTHS); do \
	    for tm in $(TIMING_MODELS); do \
	      for rd in $(RANDOM_DELAYS); do \
	        for clk in $(AXI_CLK_PERIODS); do \
	          mhz=$$((1000/clk)); \
	          total=$$((total+1)); \
	          tag="DDR4-$$spd  AXI$$dw  timing=$$tm  rand=$$rd  aclk=$${mhz}MHz TEST=$$TEST"; \
	          printf "\n=== %-70s ===\n" "$$tag"; \
	          logf=$(LOG_DIR)/uvm_$${spd}_$${dw}_$${tm}_$${rd}_$${clk}.log; \
	          $(MAKE) --no-print-directory uvm-sim \
	              TEST=$(TEST) \
	              EXTRA_FLAGS="-GDDR4_SPEED=$$spd -GAXI_DW=$$dw -GENABLE_TIMING=$$tm \
	                           -GRANDOM_DELAY_EN=$$rd -GCLK_PERIOD_NS=$$clk" \
	              > $$logf 2>&1; \
	          rc=$$?; \
	          if [ $$rc -ne 0 ] || grep -qE '\bUVM_FATAL\b|\bUVM_ERROR\b|\[MISMATCH\]|\[FAIL\]' $$logf; then \
	            printf "[RESULT] %-70s  FAIL\n" "$$tag"; fail=$$((fail+1)); \
	          else \
	            printf "[RESULT] %-70s  PASS\n" "$$tag"; pass=$$((pass+1)); \
	          fi; \
	        done; \
	      done; \
	    done; \
	  done; \
	done; \
	echo ""; \
	echo "================================================"; \
	printf "  uvm-test-all complete: %d/%d passed, %d failed\n" $$pass $$total $$fail; \
	echo "================================================"; \
	[ $$fail -eq 0 ]

## clean           – remove work libraries and log artefacts
clean:
	rm -rf $(WORK_DIR) $(LOG_DIR) obj_dir_uvm simv_uvm xcelium.d *.shm *.trn *.dsn \
	       csrc AN.DB DVEfiles ucli.key .simvision coverage.dat

## help            – show this message
help:
	@grep -E '^##' Makefile | sed 's/## /  /'
