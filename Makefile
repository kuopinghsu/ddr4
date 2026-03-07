# =============================================================================
# Makefile — DDR4 AXI4 Slave Verilator simulation
# =============================================================================
VERILATOR  ?= verilator
SIM_TOP    := sim_ddr4
OBJ_DIR    := obj_dir
SIM_BIN    := $(OBJ_DIR)/$(SIM_TOP)

SRCS       := ddr4_axi4_pkg.sv ddr4_axi4_slave.sv ddr4_axi4_tb.sv
BFM_SRCS   := ddr4_axi4_pkg.sv ddr4_axi4_slave.sv ddr4_axi4_bfm_tb.sv

VFLAGS     := --sv --timing \
              -Wno-INITIALDLY -Wno-PROCASSINIT \
              -Wno-UNUSEDPARAM -Wno-TIMESCALEMOD -Wno-MODDUP

# DDR4 parameter sweep axes
SPEED_GRADES  := 1600 1866 2133 2400 2666 2933 3200
AXI_WIDTHS    := 32 64
TIMING_MODELS := 0 1
RANDOM_DELAYS := 0 1
# aclk periods in ns: 1=1GHz, 2=500MHz, 10=100MHz, 20=50MHz
AXI_CLK_PERIODS := 1 2 10 20

# -------------------------------------------------------------------------
.PHONY: all lint sim build clean test-all bfm-lint bfm-sim bfm-cov latency-report help


all: sim

## lint      – run Verilator lint-only check
lint:
	$(VERILATOR) --lint-only -Wall $(VFLAGS) $(SRCS)

## sim       – build and run simulation with default parameters (DDR4-2400, 32-bit, timing=1)
sim: $(SIM_BIN)
	$(SIM_BIN)

## build     – compile simulation binary without running
build: $(SIM_BIN)

$(SIM_BIN): $(SRCS)
	$(VERILATOR) --binary $(VFLAGS) -o $(SIM_TOP) $(SRCS)

## test-all  – build and run BFM testbench for every combination of DDR4_SPEED x AXI_WIDTH x TIMING x RANDOM_DELAY x AXI_CLK
test-all: $(BFM_SRCS)
	@pass=0; fail=0; total=0; \
	for spd in $(SPEED_GRADES); do \
	  for dw in $(AXI_WIDTHS); do \
	    for tm in $(TIMING_MODELS); do \
	      for rd in $(RANDOM_DELAYS); do \
	        for clk in $(AXI_CLK_PERIODS); do \
	          mhz=$$((1000/clk)); \
	          total=$$((total+1)); \
	          tag="DDR4-$$spd  AXI$$dw  timing=$$tm  rand=$$rd  aclk=$${mhz}MHz"; \
	          bin=$(OBJ_DIR)/bfm_$${spd}_$${dw}_$${tm}_$${rd}_$${clk}; \
	          printf "\n=== %-60s ===\n" "$$tag"; \
	          rm -rf $(OBJ_DIR); \
	          $(VERILATOR) --binary --coverage $(VFLAGS) \
	            -GDDR4_SPEED=$$spd \
	            -GAXI_DW=$$dw \
	            -GENABLE_TIMING=$$tm \
	            -GRANDOM_DELAY_EN=$$rd \
	            -GCLK_PERIOD_NS=$$clk \
	            -GN_RAND=50 \
	            -o bfm_$${spd}_$${dw}_$${tm}_$${rd}_$${clk} \
	            $(BFM_SRCS) >/tmp/ddr4_build.log 2>&1; \
	          if [ $$? -ne 0 ]; then \
	            grep '%Error' /tmp/ddr4_build.log | head -5; \
	            printf "[RESULT] %-60s  FAIL (build error)\n" "$$tag"; fail=$$((fail+1)); \
	          elif $$bin 2>&1 | tee /tmp/ddr4_run.log | grep -q '\[FAIL\]\|\[MISMATCH\]'; then \
	            printf "[RESULT] %-60s  FAIL\n" "$$tag"; fail=$$((fail+1)); \
	          else \
	            printf "[RESULT] %-60s  PASS\n" "$$tag"; pass=$$((pass+1)); \
	          fi; \
	        done; \
	      done; \
	    done; \
	  done; \
	done; \
	echo ""; \
	echo "================================================"; \
	printf "  test-all complete: %d/%d passed, %d failed\n" $$pass $$total $$fail; \
	echo "================================================"; \
	[ $$fail -eq 0 ]

## clean     – remove Verilator build artefacts
clean:
	rm -rf $(OBJ_DIR)

## bfm-lint  – lint-only check of BFM testbench
bfm-lint: $(BFM_SRCS)
	$(VERILATOR) --lint-only -Wall $(VFLAGS) $(BFM_SRCS)

## bfm-sim   – build and run BFM testbench (DDR4-2400, AXI32, timing=1, N=50)
bfm-sim: $(BFM_SRCS)
	$(VERILATOR) --binary --coverage $(VFLAGS) \
	  -GDDR4_SPEED=2400 -GAXI_DW=32 -GENABLE_TIMING=1 \
	  -GRANDOM_DELAY_EN=0 -GN_RAND=50 \
	  -o bfm_sim $(BFM_SRCS)
	mkdir -p logs
	$(OBJ_DIR)/bfm_sim | tee logs/bfm_run.log
	cp coverage.dat logs/ 2>/dev/null || true

## bfm-cov   – annotate coverage from last bfm-sim run
bfm-cov:
	@[ -f logs/coverage.dat ] || { echo "Run 'make bfm-sim' first"; exit 1; }
	mkdir -p annotated_cov
	verilator_coverage logs/coverage.dat --annotate annotated_cov/
	@echo "Coverage annotation written to annotated_cov/"

## latency-report  – build BFM for all speed x width x aclk combos (timing=1, rand=0) and print latency table
latency-report: $(BFM_SRCS)
	@mkdir -p logs; \
	report=logs/latency_report.txt; \
	csv=logs/latency_report.csv; \
	{ printf "DDR4 AXI4 Slave -- Latency Report\n"; \
	  printf "Config: ENABLE_TIMING=1  RANDOM_DELAY=0  N_RAND=20\n"; \
	  printf "Generated: %s\n\n" "$$(date)"; \
	  printf "%-8s  %-9s  %-9s  %12s  %12s  %12s  %12s  %12s  %12s\n" \
	         "DDR4-Spd" "AXI-bits" "aclk-MHz" \
	         "AvgRd(ns)" "MinRd(ns)" "MaxRd(ns)" \
	         "AvgWr(ns)" "MinWr(ns)" "MaxWr(ns)"; \
	  printf "%s\n" "------------------------------------------------------------------------------------------------------------"; \
	} > $$report; \
	printf "DDR4_Speed,AXI_Width_bits,aclk_MHz,AvgRd_ns,MinRd_ns,MaxRd_ns,AvgWr_ns,MinWr_ns,MaxWr_ns\n" > $$csv; \
	total=0; built=0; \
	for spd in $(SPEED_GRADES); do \
	  for dw in $(AXI_WIDTHS); do \
	    for clk in $(AXI_CLK_PERIODS); do \
	      total=$$((total+1)); \
	    done; \
	  done; \
	done; \
	idx=0; \
	prev_dw=0; \
	for spd in $(SPEED_GRADES); do \
	  for dw in $(AXI_WIDTHS); do \
	    for clk in $(AXI_CLK_PERIODS); do \
	      mhz=$$((1000/clk)); \
	      idx=$$((idx+1)); \
	      printf "  [%2d/%d] Building DDR4-%s  AXI%s  aclk=%sMHz ...\n" $$idx $$total $$spd $$dw $$mhz >&2; \
	      rm -rf $(OBJ_DIR); \
	      $(VERILATOR) --binary $(VFLAGS) \
	        -GDDR4_SPEED=$$spd \
	        -GAXI_DW=$$dw \
	        -GENABLE_TIMING=1 \
	        -GRANDOM_DELAY_EN=0 \
	        -GCLK_PERIOD_NS=$$clk \
	        -GN_RAND=20 \
	        -o lat_$${spd}_$${dw}_$${clk} \
	        $(BFM_SRCS) >/tmp/ddr4_lat_build.log 2>&1; \
	      if [ $$? -ne 0 ]; then \
	        grep '%Error' /tmp/ddr4_lat_build.log | head -3 >&2; \
	        printf "%-8s  %-9s  %-9s  %12s  %12s  %12s  %12s  %12s  %12s\n" \
	               $$spd $$dw $$mhz "BUILD_ERR" "" "" "" "" "" >> $$report; \
	        printf "%s,%s,%s,BUILD_ERR,,,,,\n" $$spd $$dw $$mhz >> $$csv; \
	      else \
	        $(OBJ_DIR)/lat_$${spd}_$${dw}_$${clk} > /tmp/ddr4_lat_run.log 2>&1 || true; \
	        avg_rd=$$(awk '/Average Read Latency/{print $$(NF-2); exit}'  /tmp/ddr4_lat_run.log); \
	        min_rd=$$(awk '/Min Read Latency/{print $$(NF-2); exit}'      /tmp/ddr4_lat_run.log); \
	        max_rd=$$(awk '/Max Read Latency/{print $$(NF-2); exit}'      /tmp/ddr4_lat_run.log); \
	        avg_wr=$$(awk '/Average Write Latency/{print $$(NF-2); exit}' /tmp/ddr4_lat_run.log); \
	        min_wr=$$(awk '/Min Write Latency/{print $$(NF-2); exit}'     /tmp/ddr4_lat_run.log); \
	        max_wr=$$(awk '/Max Write Latency/{print $$(NF-2); exit}'     /tmp/ddr4_lat_run.log); \
	        printf "%-8s  %-9s  %-9s  %12s  %12s  %12s  %12s  %12s  %12s\n" \
	               $$spd $$dw $$mhz \
	               "$${avg_rd:-N/A}" "$${min_rd:-N/A}" "$${max_rd:-N/A}" \
	               "$${avg_wr:-N/A}" "$${min_wr:-N/A}" "$${max_wr:-N/A}" >> $$report; \
	        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
	               $$spd $$dw $$mhz \
	               "$${avg_rd:-N/A}" "$${min_rd:-N/A}" "$${max_rd:-N/A}" \
	               "$${avg_wr:-N/A}" "$${min_wr:-N/A}" "$${max_wr:-N/A}" >> $$csv; \
	        printf "         OK: AvgRd=%sns  AvgWr=%sns\n" "$${avg_rd:-?}" "$${avg_wr:-?}" >&2; \
	      fi; \
	    done; \
	    printf "%s\n" "------------------------------------------------------------------------------------------------------------" >> $$report; \
	  done; \
	done; \
	echo "" >> $$report; \
	echo ""; \
	cat $$report; \
	echo ""; \
	printf "Report  : $$report\nCSV     : $$csv\n"

## help      – show this message
help:
	@grep -E '^##' Makefile | sed 's/## /  /'
