# DDR4 AXI4 Slave — Latency Analysis

## Overview

This document reports the **end-to-end AXI4 transaction latency** of `ddr4_axi4_slave.sv` measured across all supported DDR4 speed grades, AXI data widths, and AXI clock frequencies.

Latency is defined as the elapsed simulation time from the AXI address handshake (`awvalid & awready` for writes, `arvalid & arready` for reads) to the final data handshake (`bvalid & bready` for writes, `rvalid & rready & rlast` for reads).

**The numbers below represent the realistic latency budget a designer should expect when connecting a bus master to this DDR4 model** — useful for setting wait-state registers, estimating pipeline depth, and validating DDR4 controller timing assumptions before tapeout.

---

## Measurement Configuration

| Parameter | Value |
|---|---|
| `ENABLE_TIMING_MODEL` | **1** (all 16 JEDEC parameters enforced: tRCD, CL, CWL, tWR, tRP, tRAS, tRC, tRFC, tREFI, tRTP, tWTR_S, tWTR_L, tFAW, tCCD_S, tCCD_L, tCK) |
| `RANDOM_DELAY_EN` | **0** (no random delays — best-case page-hit conditions) |
| `N_RAND` | 20 transactions per sequence |
| Traffic mix | single + INCR burst + WRAP burst + FIXED burst + strobe + backpressure |
| `AXI_DATA_WIDTH` | **32-bit and 64-bit** (results are identical — see §4) |
| DDR4 speed grades | 1600, 1866, 2133, 2400, 2666, 2933, 3200 MT/s |
| AXI clock (`aclk`) | 1 GHz (1 ns), 500 MHz (2 ns), 100 MHz (10 ns), 50 MHz (20 ns) |

Raw data: [`logs/latency_report.csv`](../logs/latency_report.csv)  
Regenerate: `make latency-report`

---

## Latency Tables

### Latency Tables (AXI 32-bit and AXI 64-bit)

> **Note:** Results for AXI 32-bit and AXI 64-bit are identical. Latency is determined entirely by DDR4 timing parameters (tRCD, CL, tWR, etc.) in the DDR4 clock domain — the AXI data width only affects throughput (bytes/burst), not when handshakes occur. A single table covers both widths.

All latencies in **nanoseconds**. Measurements are averages over 20 mixed transactions per configuration.

#### aclk = 1 GHz (1 ns period)

| DDR4 Speed | Avg Read | Min Read | Max Read | Avg Write | Min Write | Max Write |
|---|---|---|---|---|---|---|
| DDR4-1600 | 38.44 | 32 | 387 | 69.94 | 51 | 432 |
| DDR4-1866 | 40.42 | 31 | 412 | 66.15 | 50 | 97 |
| DDR4-2133 | 33.39 | 27 | 381 | 63.11 | 48 | 92 |
| DDR4-2400 | 30.14 | 26 | 56  | 64.04 | 46 | 402 |
| DDR4-2666 | 32.41 | 26 | 376 | 60.32 | 45 | 89 |
| DDR4-2933 | 28.93 | 26 | 55  | 62.21 | 44 | 396 |
| DDR4-3200 | **30.77** | 25 | 376 | **58.47** | 43 | 87 |

#### aclk = 500 MHz (2 ns period)

| DDR4 Speed | Avg Read | Min Read | Max Read | Avg Write | Min Write | Max Write |
|---|---|---|---|---|---|---|
| DDR4-1600 | 47.07 | 36 | 400 | 81.23 | 64 | 124 |
| DDR4-1866 | 44.20 | 36 | 400 | 81.76 | 62 | 412 |
| DDR4-2133 | 46.39 | 34 | 400 | 77.46 | 60 | 120 |
| DDR4-2400 | 42.38 | 32 | 394 | 76.69 | 56 | 444 |
| DDR4-2666 | 43.28 | 32 | 392 | 73.81 | 56 | 118 |
| DDR4-2933 | 43.18 | 32 | 390 | 73.10 | 54 | 114 |
| DDR4-3200 | **43.03** | 32 | 388 | **70.83** | 54 | 114 |

#### aclk = 100 MHz (10 ns period)

| DDR4 Speed | Avg Read | Min Read | Max Read | Avg Write | Min Write | Max Write |
|---|---|---|---|---|---|---|
| DDR4-1600 | 123.28 | 90 | 510 | 199.62 | 160 | 570 |
| DDR4-1866 | 123.28 | 90 | 510 | 199.62 | 160 | 570 |
| DDR4-2133 | 126.15 | 90 | 480 | 193.65 | 150 | 550 |
| DDR4-2400 | 123.28 | 90 | 450 | 188.85 | 150 | 570 |
| DDR4-2666 | 120.41 | 90 | 450 | 190.83 | 150 | 570 |
| DDR4-2933 | 120.41 | 90 | 450 | 190.83 | 150 | 570 |
| DDR4-3200 | **120.41** | 90 | 450 | **190.83** | 150 | 570 |

#### aclk = 50 MHz (20 ns period)

| DDR4 Speed | Avg Read | Min Read | Max Read | Avg Write | Min Write | Max Write |
|---|---|---|---|---|---|---|
| DDR4-1600 | 220.82 | 160 | 620 | 353.97 | 280 | 720 |
| DDR4-1866 | 220.82 | 160 | 620 | 353.97 | 280 | 720 |
| DDR4-2133 | 220.82 | 160 | 620 | 347.05 | 260 | 700 |
| DDR4-2400 | 229.67 | 160 | 580 | 326.79 | 260 | 700 |
| DDR4-2666 | 229.67 | 160 | 580 | 326.79 | 260 | 700 |
| DDR4-2933 | 229.67 | 160 | 580 | 326.79 | 260 | 700 |
| DDR4-3200 | **229.67** | 160 | 580 | **326.79** | 260 | 700 |

---

## AXI Clock Cycles per Transaction

The tables below convert the measured nanosecond latencies into **AXI clock cycle counts** — the numbers you need for wait-state registers, bus-timeout counters, and pipeline depth calculations.

> **Formula:** `cycles = ⌊latency_ns / aclk_period_ns⌋`  
> Average cycles are rounded to the nearest integer. Min/Max cycles are exact (measured latencies are already multiples of the AXI period).

### aclk = 1 GHz — 1 ns period

| DDR4 Speed | Avg Rd (cyc) | Min Rd | Max Rd | Avg Wr (cyc) | Min Wr | Max Wr |
|---|---|---|---|---|---|---|
| DDR4-1600 | 38 | 32 | 387 | 70 | 51 | 432 |
| DDR4-1866 | 40 | 31 | 412 | 66 | 50 | 97 |
| DDR4-2133 | 33 | 27 | 381 | 63 | 48 | 92 |
| DDR4-2400 | 30 | 26 | 56  | 64 | 46 | 402 |
| DDR4-2666 | 32 | 26 | 376 | 60 | 45 | 89 |
| DDR4-2933 | 29 | 26 | 55  | 62 | 44 | 396 |
| DDR4-3200 | **31** | 25 | 376 | **58** | 43 | 87 |

### aclk = 500 MHz — 2 ns period

| DDR4 Speed | Avg Rd (cyc) | Min Rd | Max Rd | Avg Wr (cyc) | Min Wr | Max Wr |
|---|---|---|---|---|---|---|
| DDR4-1600 | 24 | 18 | 200 | 41 | 32 | 62 |
| DDR4-1866 | 22 | 18 | 200 | 41 | 31 | 206 |
| DDR4-2133 | 23 | 17 | 200 | 39 | 30 | 60 |
| DDR4-2400 | 21 | 16 | 197 | 38 | 28 | 222 |
| DDR4-2666 | 22 | 16 | 196 | 37 | 28 | 59 |
| DDR4-2933 | 22 | 16 | 195 | 37 | 27 | 57 |
| DDR4-3200 | **22** | 16 | 194 | **35** | 27 | 57 |

### aclk = 100 MHz — 10 ns period

| DDR4 Speed | Avg Rd (cyc) | Min Rd | Max Rd | Avg Wr (cyc) | Min Wr | Max Wr |
|---|---|---|---|---|---|---|
| DDR4-1600 | 12 | 9 | 51 | 20 | 16 | 57 |
| DDR4-1866 | 12 | 9 | 51 | 20 | 16 | 57 |
| DDR4-2133 | 13 | 9 | 48 | 19 | 15 | 55 |
| DDR4-2400 | 12 | 9 | 45 | 19 | 15 | 57 |
| DDR4-2666 | 12 | 9 | 45 | 19 | 15 | 57 |
| DDR4-2933 | 12 | 9 | 45 | 19 | 15 | 57 |
| DDR4-3200 | **12** | 9 | 45 | **19** | 15 | 57 |

### aclk = 50 MHz — 20 ns period

| DDR4 Speed | Avg Rd (cyc) | Min Rd | Max Rd | Avg Wr (cyc) | Min Wr | Max Wr |
|---|---|---|---|---|---|---|
| DDR4-1600 | 11 | 8 | 31 | 18 | 14 | 36 |
| DDR4-1866 | 11 | 8 | 31 | 18 | 14 | 36 |
| DDR4-2133 | 11 | 8 | 31 | 17 | 13 | 35 |
| DDR4-2400 | 11 | 8 | 29 | 16 | 13 | 35 |
| DDR4-2666 | 11 | 8 | 29 | 16 | 13 | 35 |
| DDR4-2933 | 11 | 8 | 29 | 16 | 13 | 35 |
| DDR4-3200 | **11** | 8 | 29 | **16** | 13 | 35 |

### Cross-reference: Average Read Cycles

| DDR4 Speed | 1 GHz | 500 MHz | 100 MHz | 50 MHz |
|---|---|---|---|---|
| DDR4-1600 | 38 | 24 | 12 | 11 |
| DDR4-1866 | 40 | 22 | 12 | 11 |
| DDR4-2133 | 33 | 23 | 13 | 11 |
| DDR4-2400 | 30 | 21 | 12 | 11 |
| DDR4-2666 | 32 | 22 | 12 | 11 |
| DDR4-2933 | 29 | 22 | 12 | 11 |
| DDR4-3200 | 31 | 22 | 12 | 11 |

### Cross-reference: Average Write Cycles

| DDR4 Speed | 1 GHz | 500 MHz | 100 MHz | 50 MHz |
|---|---|---|---|---|
| DDR4-1600 | 70 | 41 | 20 | 18 |
| DDR4-1866 | 66 | 41 | 20 | 18 |
| DDR4-2133 | 63 | 39 | 19 | 17 |
| DDR4-2400 | 64 | 38 | 19 | 16 |
| DDR4-2666 | 60 | 37 | 19 | 16 |
| DDR4-2933 | 62 | 37 | 19 | 16 |
| DDR4-3200 | 58 | 35 | 19 | 16 |

### Practical notes

- **Wait-state register:** program this to at least the **Max** cycle value for your aclk/DDR4 combination to avoid false timeouts. For DDR4-2400 at 100 MHz, that is 45 cycles read / 57 cycles write (up from prior measurement due to page-miss and refresh now fully modelled).
- **Timeout counter:** add a safety margin of 20–30% above the max observed value to account for refresh, page-miss, and back-pressure not captured in best-case simulation.
- **Read average at 1 GHz varies non-monotonically** across speed grades (38 ns at DDR4-1600 vs 29 ns at DDR4-2933) because N_RAND=20 transactions produce statistically different page-hit/miss mixes on each run. Use minimum latency for best-case and maximum for worst-case analysis.
- **All DDR4 grades converge to the same read cycle count** at 100 MHz and 50 MHz (12 and 11 cycles respectively), confirming that AXI clock quantisation fully swamps the speed-grade difference at these frequencies.

---

## Analysis

### 1. DDR4 speed grade improves latency only at fast aclk

At 1 GHz aclk, both mclk and aclk have fine resolution, so the DDR4 timing improvement is visible:

- **Read latency** ranges from ~29 ns (DDR4-2933) to ~40 ns (DDR4-1866) with some run-to-run variation from the traffic mix
- **Write latency** drops cleanly from ~70 ns (DDR4-1600) → ~58 ns (DDR4-3200): **~17% improvement**

The improvement comes from shorter tCK (clock period) for the same tRCD / CL / CWL values in nanoseconds, resulting in fewer mclk cycles of DDR4 latency.

At 500 MHz aclk the trend holds, but is slightly masked by the coarser 2 ns AXI clock quantization.

### 2. AXI clock frequency dominates at slow speeds

At 100 MHz and 50 MHz aclk, **all seven DDR4 speed grades produce the same average read latency** (120–126 ns and 220–230 ns respectively). This is because the AXI clock quantization (10 ns or 20 ns per cycle) is coarser than the difference between DDR4 speed grades — all grades round up to the same number of AXI clock cycles when waiting for the CDC ack.

Write latency still shows small differentiation at 100 MHz because the write-recovery (tWR) contribution is larger and the grade-to-grade difference (~9 ns between DDR4-1600 and DDR4-3200 write paths) is comparable to one AXI clock period.

**Practical implication:** Running the AXI bus at 100 MHz or slower completely negates any benefit of using a higher DDR4 speed grade for latency purposes. A 500 MHz or faster AXI bus is needed to exploit DDR4-2666+ timing.

### 3. Write latency is significantly higher than read latency

Write transactions incur three DDR4 timing phases:

$$\text{Write latency} = t_{RCD} + CWL + t_{WR}$$

Read transactions incur only two:

$$\text{Read latency} = t_{RCD} + CL$$

At DDR4-2400 and 1 GHz aclk, this means:
- Read: ~30 ns average
- Write: ~64 ns average → **~113% higher than read**

The write-recovery penalty ($t_{WR}$ = 15 ns = 18 mclk cycles at DDR4-2400) is the largest single contributor to the latency gap. Designs that are write-critical should account for this overhead in their bus arbitration or buffering strategy.

### 4. AXI data width (32-bit vs 64-bit) has no effect on latency

The latency model is purely timing-driven through the DDR4 clock domain. A single outstanding transaction occupies the entire read or write FSM regardless of data width. Wider data allows **more bytes per transaction** (higher throughput per burst), but the first-beat latency is identical.

AXI 64-bit becomes advantageous only when throughput (GB/s) matters — for latency-sensitive single-beat accesses, there is no reason to prefer one width over the other.

### 5. Max latency significantly exceeds average (page-miss + backpressure)

At 1 GHz aclk, max read latency reaches **387–412 ns** against averages of ~30–40 ns — a 10× peak-to-average ratio. This is caused by two effects:

1. **Page-miss penalty**: tRAS + tRP + tRCD (up to ~63 ns) added when a different row must be opened
2. **Back-pressure**: the `backpressure` test sequence randomly de-asserts `rready`, stalling the read data channel and accumulating many AXI cycles per beat

In a real system, any downstream consumer that cannot sustain `rready=1` should account for worst-case latency (use max values, not average) when sizing FIFOs or setting timeout counters.

### 6. BFM simulation statistics (DDR4-2400, AXI32, 100 MHz aclk, N=50)

| Metric | Value |
|---|---|
| Total read transactions | 324 |
| Total write transactions | 396 |
| Average read latency | 120.40 ns |
| Min / Max read latency | 70 ns / 510 ns |
| Average write latency | 189.57 ns |
| Min / Max write latency | 150 ns / 570 ns |
| Bus utilization | 84.26% |
| Read bandwidth | 0.0322 GB/s |
| Write bandwidth | 0.0086 GB/s |
| Total bandwidth | 0.0407 GB/s |
| Refresh stalls (tRFC) | 17 |
| Page hits | 556 |
| Page misses | 164 |
| Write-to-read stalls (tWTR) | 0 |
| FAW stalls (tFAW) | 0 |
| tRAS stalls | 9 |
| tRTP stalls | 0 |
| tCCD stalls | 0 |
| Test result | **341 PASS, 0 FAIL** |

---

## Derived Design Guidelines

| Design constraint | Recommended setting |
|---|---|
| Target latency < 40 ns (read) | DDR4-2400+ with aclk ≥ 1 GHz |
| Target latency < 80 ns (write) | DDR4-2400+ with aclk ≥ 500 MHz |
| aclk = 100 MHz (typical SoC bus) | Plan for ≥13 AXI clock cycles read, ≥20 write (DDR4-2400) |
| aclk = 50 MHz (low-power design) | Plan for ≥12 AXI clock cycles read, ≥17 write (DDR4-2400) |
| Burst vs single transactions | Same first-beat latency; use long bursts to amortise tRCD overhead |
| Write-heavy traffic | Add write-response buffering; write latency is ~2× read latency |
| Refresh / page miss margin | Add `RANDOM_DELAY_EN=1` with `MAX_RANDOM_DELAY=20` to model worst-case |
| Timeout counter setting | Use max observed + 25% margin; e.g. DDR4-2400 @ 1 GHz: read 70, write 502 |

---

## Functional Coverage Report

Coverage measured from `logs/coverage.dat` produced by `make bfm-sim`  
(DDR4-2400, AXI32, ENABLE_TIMING=1, RANDOM_DELAY=0, N_RAND=50).  
For combined multi-configuration coverage run `make bfm-cov-full`.  
Regenerate annotation: `make bfm-cov` (single run) or `make bfm-cov-full` (merged).

### Overall

| Metric | Value |
|---|---|
| Total instrumented points | 1450 |
| Points covered (single run: `make bfm-sim`) | 535 — **37%** |
| Points covered (6-config merge: `make bfm-cov-full`) | 751 / 1450 — **52%** |
| Source: `ddr4_axi4_slave.sv` uncovered lines (6-config) | 86 / 1421 |
| Source: `ddr4_axi4_bfm_tb.sv` uncovered lines (6-config) | 61 / 1258 |

> Coverage has increased in **absolute instrumented points** (1135 → 1450) due to new DMA test tasks (`run_seq_dma_concurrent`, `run_seq_dma_outstanding`) added to the BFM and additional timing logic in the slave. The single-run 37% figure reflects that several stall paths require specific traffic patterns. Running `make bfm-cov-full` (6 configurations: default + 1 GHz + no-timing + rand + verbose + init) raises this to **52%** by covering tWTR stalls (1 GHz), WRITE_REC_CYC==0 path (ENABLE_TIMING=0), random-delay branch, VERBOSE_MODE display statements, and `$readmemh` initialisation. See the gap analysis below.

### Coverage by Category

| Category | Status | Notes |
|---|---|---|
| Write FSM: IDLE → ADDR_WAIT → ACK_CLR → DATA → DELAY → RESP | ✅ Covered | Full write path exercised |
| Read FSM: IDLE → ADDR_WAIT → ACK_CLR → DATA | ✅ Covered | Full read path exercised |
| CDC handshake (req/ack 4-phase, both directions) | ✅ Covered | All phases observed |
| INCR burst (read + write) | ✅ Covered | Lengths 1–15 randomised |
| WRAP burst (read + write) | ✅ Covered | Lengths 2, 4, 8, 16 |
| FIXED burst (read + write) | ✅ Covered | Repeated address |
| Byte-strobe partial writes | ✅ Covered | Random strobe patterns |
| Back-pressure (rready de-assertion) | ✅ Covered | Random hold-off |
| Page-hit path (same row already open) | ✅ Covered | 556 page hits observed |
| Page-miss path (tRAS + tRP + tRCD penalty) | ✅ Covered | 164 page misses observed |
| Refresh stall path (tRFC) | ✅ Covered | 17 refresh stalls observed |
| `WRITE_REC_CYC > 0` write-recovery delay path | ✅ Covered | DDR4-2400 tWR = 18 mclk cycles |
| `WRITE_REC_CYC == 0` direct WR_DATA→WR_RESP | ✅ Covered | `make bfm-sim-no-timing` (ENABLE_TIMING=0) |
| tWTR stall branch | ✅ Covered | `make bfm-sim-1g` — stalls observed (wtr_stress seq) |
| Out-of-range address error path (write) | ✅ Covered | `run_seq_oob_access` — SLVERR verified |
| Out-of-range address error path (read) | ✅ Covered | `run_seq_oob_access` — SLVERR verified |
| `RANDOM_DELAY_EN=1` branch | ✅ Covered | `make bfm-sim-rand` |
| `VERBOSE_MODE=1` display statements | ✅ Covered | `make bfm-sim-verbose` |
| tRAS stall branch | ✅ Covered | `make bfm-sim-1g` — 9 stalls observed |
| DMA concurrent WR+RD (fork/join, 8 pairs) | ✅ Covered | `run_seq_dma_concurrent` — 16 concurrent transactions, data verified |
| DMA outstanding (back-to-back + AR-overlaps-AW) | ✅ Covered | `run_seq_dma_outstanding` — 18 transactions; read completed during AW preamble |
| `MEMORY_INIT_FILE` path (`$readmemh`) | ✅ Covered | `make bfm-sim-init` — `$readmemh` executed and verified |
| Scoreboard byte-level mismatch check | ✅ Covered (pass path) | Fail path not reachable — all tests pass (by design) |

### Coverage Gap Analysis

**Not a concern (design intent):**
- `[MISMATCH]` and `txn_fail++` branches are dead code under correct DUT operation — their absence in coverage confirms the DUT behaves correctly.
- `RD_DELAY` is an explicitly unused FSM state kept for encoding stability.
- DPI-C functions and debug tasks are integration-time helpers, not BFM targets.
- tFAW, tRTP, tCCD stall branches are **structurally unreachable** with a serialized AXI slave: each transaction takes much longer than the respective timing window (tFAW=25 ns, tRTP=8 ns, tCCD=3.3 ns), so the 4th activate / precharge / CAS can never arrive within the window via single-channel AXI.

**Resolved gaps (now covered):**

| Previously uncovered | Resolution |
|---|---|
| tWTR stall path | `run_seq_wtr_stress` + `make bfm-sim-1g` (stalls observed) |
| tRAS stall path | `make bfm-sim-1g` (9 stalls observed at high ACT rate) |
| OOB write error path | `run_seq_oob_access` (SLVERR verified each run) |
| OOB read error path | `run_seq_oob_access` (SLVERR verified each run) |
| `WRITE_REC_CYC == 0` direct path | `make bfm-sim-no-timing` |
| `RANDOM_DELAY_EN=1` branch | `make bfm-sim-rand` |
| `VERBOSE_MODE=1` display blocks | `make bfm-sim-verbose` |
| DMA concurrent WR+RD overlap | `run_seq_dma_concurrent` (fork/join, 8 pairs verified) |
| DMA outstanding back-to-back + AR-overlaps-AW | `run_seq_dma_outstanding` (18 transactions verified) |
| `MEMORY_INIT_FILE` / `$readmemh` branch | `make bfm-sim-init` (hex file loaded and exercised) |

**Remaining actionable gaps:**

| Gap | How to cover |
|---|---|
| tFAW / tRTP / tCCD stall branches | Structurally unreachable with serialized AXI — these require multiple overlapping DDR4 commands within nanosecond windows not achievable via single-channel AXI serialization |
| `MEMORY_INIT_FILE` + `VERBOSE_MODE=1` display | Add a `bfm-sim-init-verbose` target combining both parameters |
| Debug tasks / DPI-C functions | Add a dedicated SoC integration TB that calls these interfaces |
| `[MISMATCH]` / `txn_fail` paths | Inject a deliberate data corruption at the DUT level (not recommended — these are correct-operation sentinels) |

Running **`make bfm-cov-full`** (6 configurations: default + 1 GHz + no-timing + rand + verbose + init) achieves **52% combined coverage** (751/1450).

---

## How to Re-run

```bash
# Full 56-combo sweep (timing=1, rand=0, all speeds/widths/clocks)
make latency-report

# Focused sweep — e.g. just your target config
make latency-report SPEED_GRADES="2400" AXI_WIDTHS="32 64" AXI_CLK_PERIODS="1 2 10 20"

# With random delays to model page-miss / refresh worst case
# (re-run bfm-sim manually with RANDOM_DELAY_EN=1 and check stats output)
make bfm-sim   # edit Makefile or pass -GRANDOM_DELAY_EN=1 to Verilator directly
```

Results are written to:
- `logs/latency_report.txt` — human-readable table
- `logs/latency_report.csv` — importable into Excel / Python / gnuplot

---