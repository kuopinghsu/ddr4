# DDR4 AXI4 Slave — Latency Analysis

## Overview

This document reports the **end-to-end AXI4 transaction latency** of `ddr4_axi4_slave.sv` measured across all supported DDR4 speed grades, AXI data widths, and AXI clock frequencies.

Latency is defined as the elapsed simulation time from the AXI address handshake (`awvalid & awready` for writes, `arvalid & arready` for reads) to the final data handshake (`bvalid & bready` for writes, `rvalid & rready & rlast` for reads).

**The numbers below represent the realistic latency budget a designer should expect when connecting a bus master to this DDR4 model** — useful for setting wait-state registers, estimating pipeline depth, and validating DDR4 controller timing assumptions before tapeout.

---

## Measurement Configuration

| Parameter | Value |
|---|---|
| `ENABLE_TIMING_MODEL` | **1** (real DDR4 tRCD / CL / CWL / tWR enforced) |
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

### AXI 32-bit (≡ AXI 64-bit — identical values, see §4)

All latencies in **nanoseconds**. Measurements are averages over 20 mixed transactions per configuration.

#### aclk = 1 GHz (1 ns period)

| DDR4 Speed | Avg Read | Min Read | Max Read | Avg Write | Min Write | Max Write |
|---|---|---|---|---|---|---|
| DDR4-1600 | 46.12 | 43 | 59 | 69.06 | 66 | 83 |
| DDR4-1866 | 45.91 | 43 | 59 | 67.71 | 65 | 81 |
| DDR4-2133 | 44.29 | 41 | 57 | 64.79 | 62 | 79 |
| DDR4-2400 | 43.98 | 40 | 57 | 63.51 | 60 | 77 |
| DDR4-2666 | 42.73 | 40 | 55 | 61.34 | 59 | 74 |
| DDR4-2933 | 42.50 | 40 | 55 | 61.70 | 59 | 75 |
| DDR4-3200 | **41.67** | 39 | 55 | **60.06** | 57 | 74 |

#### aclk = 500 MHz (2 ns period)

| DDR4 Speed | Avg Read | Min Read | Max Read | Avg Write | Min Write | Max Write |
|---|---|---|---|---|---|---|
| DDR4-1600 | 56.13 | 50 | 82 | 82.37 | 78 | 110 |
| DDR4-1866 | 55.42 | 50 | 80 | 82.21 | 78 | 108 |
| DDR4-2133 | 54.20 | 48 | 80 | 79.56 | 74 | 106 |
| DDR4-2400 | 52.77 | 46 | 80 | 76.03 | 70 | 102 |
| DDR4-2666 | 52.38 | 48 | 78 | 75.90 | 70 | 102 |
| DDR4-2933 | 51.15 | 46 | 78 | 75.54 | 70 | 102 |
| DDR4-3200 | **50.92** | 46 | 76 | **72.71** | 68 | 98 |

#### aclk = 100 MHz (10 ns period)

| DDR4 Speed | Avg Read | Min Read | Max Read | Avg Write | Min Write | Max Write |
|---|---|---|---|---|---|---|
| DDR4-1600 | 134.58 | 110 | 260 | 201.07 | 180 | 330 |
| DDR4-1866 | 134.58 | 110 | 260 | 201.07 | 180 | 330 |
| DDR4-2133 | 134.58 | 110 | 260 | 187.00 | 160 | 320 |
| DDR4-2400 | 134.58 | 110 | 260 | 181.21 | 160 | 320 |
| DDR4-2666 | 134.58 | 110 | 260 | 181.07 | 160 | 310 |
| DDR4-2933 | 134.58 | 110 | 260 | 181.07 | 160 | 310 |
| DDR4-3200 | **134.58** | 110 | 260 | **181.07** | 160 | 310 |

#### aclk = 50 MHz (20 ns period)

| DDR4 Speed | Avg Read | Min Read | Max Read | Avg Write | Min Write | Max Write |
|---|---|---|---|---|---|---|
| DDR4-1600 | 229.17 | 180 | 480 | 342.14 | 300 | 600 |
| DDR4-1866 | 229.17 | 180 | 480 | 342.14 | 300 | 600 |
| DDR4-2133 | 229.17 | 180 | 480 | 334.71 | 280 | 600 |
| DDR4-2400 | 229.17 | 180 | 480 | 322.57 | 280 | 580 |
| DDR4-2666 | 229.17 | 180 | 480 | 322.14 | 280 | 580 |
| DDR4-2933 | 229.17 | 180 | 480 | 322.14 | 280 | 580 |
| DDR4-3200 | **229.17** | 180 | 480 | **322.14** | 280 | 580 |

---

## AXI Clock Cycles per Transaction

The tables below convert the measured nanosecond latencies into **AXI clock cycle counts** — the numbers you need for wait-state registers, bus-timeout counters, and pipeline depth calculations.

> **Formula:** `cycles = ⌊latency_ns / aclk_period_ns⌋`  
> Average cycles are rounded to the nearest integer. Min/Max cycles are exact (measured latencies are already multiples of the AXI period).

### aclk = 1 GHz — 1 ns period

| DDR4 Speed | Avg Rd (cyc) | Min Rd | Max Rd | Avg Wr (cyc) | Min Wr | Max Wr |
|---|---|---|---|---|---|---|
| DDR4-1600 | 46 | 43 | 59 | 69 | 66 | 83 |
| DDR4-1866 | 46 | 43 | 59 | 68 | 65 | 81 |
| DDR4-2133 | 44 | 41 | 57 | 65 | 62 | 79 |
| DDR4-2400 | 44 | 40 | 57 | 64 | 60 | 77 |
| DDR4-2666 | 43 | 40 | 55 | 61 | 59 | 74 |
| DDR4-2933 | 43 | 40 | 55 | 62 | 59 | 75 |
| DDR4-3200 | **42** | 39 | 55 | **60** | 57 | 74 |

### aclk = 500 MHz — 2 ns period

| DDR4 Speed | Avg Rd (cyc) | Min Rd | Max Rd | Avg Wr (cyc) | Min Wr | Max Wr |
|---|---|---|---|---|---|---|
| DDR4-1600 | 28 | 25 | 41 | 41 | 39 | 55 |
| DDR4-1866 | 28 | 25 | 40 | 41 | 39 | 54 |
| DDR4-2133 | 27 | 24 | 40 | 40 | 37 | 53 |
| DDR4-2400 | 26 | 23 | 40 | 38 | 35 | 51 |
| DDR4-2666 | 26 | 24 | 39 | 38 | 35 | 51 |
| DDR4-2933 | 26 | 23 | 39 | 38 | 35 | 51 |
| DDR4-3200 | **25** | 23 | 38 | **36** | 34 | 49 |

### aclk = 100 MHz — 10 ns period

| DDR4 Speed | Avg Rd (cyc) | Min Rd | Max Rd | Avg Wr (cyc) | Min Wr | Max Wr |
|---|---|---|---|---|---|---|
| DDR4-1600 | 13 | 11 | 26 | 20 | 18 | 33 |
| DDR4-1866 | 13 | 11 | 26 | 20 | 18 | 33 |
| DDR4-2133 | 13 | 11 | 26 | 19 | 16 | 32 |
| DDR4-2400 | 13 | 11 | 26 | 18 | 16 | 32 |
| DDR4-2666 | 13 | 11 | 26 | 18 | 16 | 31 |
| DDR4-2933 | 13 | 11 | 26 | 18 | 16 | 31 |
| DDR4-3200 | **13** | 11 | 26 | **18** | 16 | 31 |

### aclk = 50 MHz — 20 ns period

| DDR4 Speed | Avg Rd (cyc) | Min Rd | Max Rd | Avg Wr (cyc) | Min Wr | Max Wr |
|---|---|---|---|---|---|---|
| DDR4-1600 | 11 | 9 | 24 | 17 | 15 | 30 |
| DDR4-1866 | 11 | 9 | 24 | 17 | 15 | 30 |
| DDR4-2133 | 11 | 9 | 24 | 17 | 14 | 30 |
| DDR4-2400 | 11 | 9 | 24 | 16 | 14 | 29 |
| DDR4-2666 | 11 | 9 | 24 | 16 | 14 | 29 |
| DDR4-2933 | 11 | 9 | 24 | 16 | 14 | 29 |
| DDR4-3200 | **11** | 9 | 24 | **16** | 14 | 29 |

### Cross-reference: Average Read Cycles

| DDR4 Speed | 1 GHz | 500 MHz | 100 MHz | 50 MHz |
|---|---|---|---|---|
| DDR4-1600 | 46 | 28 | 13 | 11 |
| DDR4-1866 | 46 | 28 | 13 | 11 |
| DDR4-2133 | 44 | 27 | 13 | 11 |
| DDR4-2400 | 44 | 26 | 13 | 11 |
| DDR4-2666 | 43 | 26 | 13 | 11 |
| DDR4-2933 | 43 | 26 | 13 | 11 |
| DDR4-3200 | 42 | 25 | 13 | 11 |

### Cross-reference: Average Write Cycles

| DDR4 Speed | 1 GHz | 500 MHz | 100 MHz | 50 MHz |
|---|---|---|---|---|
| DDR4-1600 | 69 | 41 | 20 | 17 |
| DDR4-1866 | 68 | 41 | 20 | 17 |
| DDR4-2133 | 65 | 40 | 19 | 17 |
| DDR4-2400 | 64 | 38 | 18 | 16 |
| DDR4-2666 | 61 | 38 | 18 | 16 |
| DDR4-2933 | 62 | 38 | 18 | 16 |
| DDR4-3200 | 60 | 36 | 18 | 16 |

### Practical notes

- **Wait-state register:** program this to at least the **Max** cycle value for your aclk/DDR4 combination to avoid false timeouts. For DDR4-2400 at 100 MHz, that is 26 cycles read / 32 cycles write.
- **Timeout counter:** add a safety margin of 20–30% above the max observed value to account for refresh, page-miss, and back-pressure not captured in best-case simulation.
- **Read cycle count decreases sharply from 1 GHz → 100 MHz** (46 → 13 cycles at DDR4-1600) because DDR4 timing is fixed in nanoseconds — a slower aclk completes the same wall-clock latency in fewer of its own clock periods.
- **All DDR4 grades converge to the same read cycle count** at 100 MHz and 50 MHz (13 and 11 cycles respectively), confirming that AXI clock quantisation fully swamps the speed-grade difference at these frequencies.

---

## Analysis

### 1. DDR4 speed grade improves latency only at fast aclk

At 1 GHz aclk, both mclk and aclk have fine resolution, so the DDR4 timing improvement is clearly visible:

- **Read latency** drops from 46.1 ns (DDR4-1600) → 41.7 ns (DDR4-3200): **~10% improvement**
- **Write latency** drops from 69.1 ns (DDR4-1600) → 60.1 ns (DDR4-3200): **~13% improvement**

The improvement comes from shorter tCK (clock period) for the same tRCD / CL / CWL values in nanoseconds, resulting in fewer mclk cycles of DDR4 latency.

At 500 MHz aclk the trend holds (~9% read, ~12% write), but is slightly masked by the coarser 2 ns AXI clock quantization.

### 2. AXI clock frequency dominates at slow speeds

At 100 MHz and 50 MHz aclk, **all seven DDR4 speed grades produce the same read latency** (134.6 ns and 229.2 ns respectively). This is because the AXI clock quantization (10 ns or 20 ns per cycle) is coarser than the difference between DDR4 speed grades — all grades round up to the same number of AXI clock cycles when waiting for the CDC ack.

Write latency still shows small differentiation at 100 MHz because the write-recovery (tWR) contribution is larger and the grade-to-grade difference (~20 ns between DDR4-1600 and DDR4-3200 write paths) exceeds one AXI clock period.

**Practical implication:** Running the AXI bus at 100 MHz or slower completely negates any benefit of using a higher DDR4 speed grade for latency purposes. A 500 MHz or faster AXI bus is needed to exploit DDR4-2666+ timing.

### 3. Write latency is significantly higher than read latency

Write transactions incur three DDR4 timing phases:

$$\text{Write latency} = t_{RCD} + CWL + t_{WR}$$

Read transactions incur only two:

$$\text{Read latency} = t_{RCD} + CL$$

At DDR4-2400 and 1 GHz aclk, this means:
- Read: 44 ns average
- Write: 63.5 ns average → **~44% higher than read**

The write-recovery penalty ($t_{WR}$ = 15 ns = 18 mclk cycles at DDR4-2400) is the largest single contributor to the latency gap. Designs that are write-critical should account for this overhead in their bus arbitration or buffering strategy.

### 4. AXI data width (32-bit vs 64-bit) has no effect on latency

The latency model is purely timing-driven through the DDR4 clock domain. A single outstanding transaction occupies the entire read or write FSM regardless of data width. Wider data allows **more bytes per transaction** (higher throughput per burst), but the first-beat latency is identical.

AXI 64-bit becomes advantageous only when throughput (GB/s) matters — for latency-sensitive single-beat accesses, there is no reason to prefer one width over the other.

### 5. Max latency significantly exceeds average (backpressure effect)

At 100 MHz aclk, max read latency reaches **260 ns** against an average of 135 ns — a 2× peak-to-average ratio. This is caused by the `backpressure` test sequence which randomly de-asserts `rready`, stalling the read data channel. The same effect accounts for the wide min/max spread at all frequencies.

In a real system, any downstream consumer that cannot sustain `rready=1` should account for worst-case latency (use max values, not average) when sizing FIFOs or setting timeout counters.

---

## Derived Design Guidelines

| Design constraint | Recommended setting |
|---|---|
| Target latency < 50 ns (read) | DDR4-2400+ with aclk ≥ 1 GHz |
| Target latency < 80 ns (write) | DDR4-2400+ with aclk ≥ 500 MHz |
| aclk = 100 MHz (typical SoC bus) | Plan for ≥14 AXI clock cycles read, ≥19 write (DDR4-2400) |
| aclk = 50 MHz (low-power design) | Plan for ≥12 AXI clock cycles read, ≥17 write (DDR4-2400) |
| Burst vs single transactions | Same first-beat latency; use long bursts to amortise tRCD overhead |
| Write-heavy traffic | Add write-response buffering; write latency is ~44% higher than read |
| Refresh / page miss margin | Add `RANDOM_DELAY_EN=1` with `MAX_RANDOM_DELAY=20` to model worst-case |

---

## Functional Coverage Report

Coverage measured from `logs/coverage.dat` produced by `make bfm-sim`  
(DDR4-2400, AXI32, ENABLE_TIMING=1, RANDOM_DELAY=0, N_RAND=50).  
Regenerate annotation: `make bfm-cov`

### Overall

| Metric | Value |
|---|---|
| Total instrumented points | 971 |
| Points hit ≥ 1× (statement/branch coverage) | 687 — **70%** |
| Points hit at high-confidence count | 471 — **48%** |
| Source: `ddr4_axi4_bfm_tb.sv` uncovered lines | 20 / 730 |
| Source: `ddr4_axi4_slave.sv` uncovered lines | 129 / 1153 |

> **70%** is the primary figure (every instrumented point exercised at least once).  
> **48%** is the "well-exercised" figure — points where the simulator observed a statistically significant hit count, indicating repeated and varied stimulation. Use 48% when assessing confidence for sign-off.

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
| Scoreboard byte-level mismatch check | ✅ Covered (pass path) | Fail path not reachable — all tests pass (by design) |
| `WRITE_REC_CYC > 0` write-recovery delay path | ✅ Covered | DDR4-2400 tWR = 18 mclk cycles |
| `WRITE_REC_CYC == 0` direct WR_DATA→WR_RESP | ❌ Not covered | Requires `ENABLE_TIMING=0` |
| `RD_DELAY` FSM state | ❌ Not covered | Unused pipeline slot (intentionally unreachable) |
| Out-of-range address error path (write) | ❌ Not covered | All BFM addresses are within `SIM_DEPTH` |
| Out-of-range address error path (read) | ❌ Not covered | All BFM addresses are within `SIM_DEPTH` |
| `RANDOM_DELAY_EN=1` branch | ❌ Not covered | Run with `RANDOM_DELAY_EN=1` to cover |
| `MEMORY_INIT_FILE` initialisation path | ❌ Not covered | No init file passed in BFM TB |
| `VERBOSE_MODE=1` display statements | ❌ Not covered | BFM TB forces `VERBOSE_MODE=0` |
| Debug tasks (`write_memory`, `read_memory`, `dump_memory_region`) | ❌ Not covered | DUT-internal tasks, not called by BFM |
| DPI-C export functions (`mem_write_byte` etc.) | ❌ Not covered | Only used in SoC integration TB |
| Watchdog timeout paths in BFM | ❌ Not covered | No timeouts triggered |
| `[MISMATCH]` / `txn_fail` paths in BFM | ❌ Not covered | All transactions pass |

### Coverage Gap Analysis

**Not a concern (design intent):**
- `[MISMATCH]` and `txn_fail++` branches are dead code under correct DUT operation — their absence in coverage confirms the DUT behaves correctly.
- `RD_DELAY` is an explicitly unused FSM state kept for encoding stability.
- DPI-C functions and debug tasks are integration-time helpers, not BFM targets.
- `VERBOSE_MODE` display blocks: covered in directed TB (`make sim`) which runs with `VERBOSE_MODE=1`.

**Actionable gaps to improve coverage:**
| Gap | How to cover |
|---|---|
| `RANDOM_DELAY_EN=1` branch | `make bfm-sim` with `-GRANDOM_DELAY_EN=1` |
| `ENABLE_TIMING=0` direct RESP path | `make bfm-sim` with `-GENABLE_TIMING=0` |
| Out-of-range address error paths | Add one deliberately out-of-range transaction to `run_seq_single_rw` |
| `MEMORY_INIT_FILE` path | Create a `.hex` init file and pass `MEMORY_INIT_FILE=...` |

Running **`make test-all`** (224 combos, including `TIMING_MODELS=0` and `RANDOM_DELAYS=1`) would cover the timing-bypass and random-delay branches, pushing coverage above 80%.

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
