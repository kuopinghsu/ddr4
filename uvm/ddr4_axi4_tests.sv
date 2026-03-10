// ============================================================================
// File: uvm/ddr4_axi4_tests.sv
// Project: KV32 RISC-V Processor
// Description: UVM test classes for ddr4_axi4_slave.sv
//
// Available tests:
//   ddr4_axi4_full_test             — runs all 27 sequences (default regression)
//   ddr4_axi4_smoke_test            — single-rw + burst_incr only (quick smoke)
//   ddr4_axi4_timing_test           — page_miss + wtr_stress + refresh_mid_burst
//   ddr4_axi4_dma_test              — DMA concurrent + outstanding
//   ddr4_axi4_coverage_test         — full sequences with N_RAND=50 for coverage
//   ddr4_axi4_max_outstanding_test  — saturate AW/AR to MAX_OUTSTANDING=16 (SEQ 27)
//
// Select via +UVM_TESTNAME=<test_name> on simulator command line.
// ============================================================================

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off WIDTHEXPAND  */
/* verilator lint_off WIDTHTRUNC   */
/* verilator lint_off INITIALDLY   */

`ifndef DDR4_AXI4_TESTS_SV
`define DDR4_AXI4_TESTS_SV

`include "uvm_macros.svh"

package ddr4_axi4_tests_pkg;

    import uvm_pkg::*;
    import ddr4_axi4_pkg::*;
    import ddr4_axi4_uvm_pkg::*;
    import ddr4_axi4_seqs_pkg::*;

    // =========================================================================
    // Full regression test — all 26 sequences
    // =========================================================================
    class ddr4_axi4_full_test extends ddr4_axi4_base_test;
        `uvm_component_utils(ddr4_axi4_full_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual task run_sequences(uvm_phase phase);
            ddr4_axi4_full_seq full_seq;
            full_seq = ddr4_axi4_full_seq::type_id::create("full_seq");
            full_seq.start(env.agent.sequencer);
        endtask

    endclass : ddr4_axi4_full_test

    // =========================================================================
    // Smoke test — single-rw + burst_incr only
    // =========================================================================
    class ddr4_axi4_smoke_test extends ddr4_axi4_base_test;
        `uvm_component_utils(ddr4_axi4_smoke_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual task run_sequences(uvm_phase phase);
            seq_single_rw s1 = seq_single_rw::type_id::create("s1");
            seq_burst_incr s2 = seq_burst_incr::type_id::create("s2");
            s1.start(env.agent.sequencer);
            s2.start(env.agent.sequencer);
        endtask

    endclass : ddr4_axi4_smoke_test

    // =========================================================================
    // Timing test — page_miss + wtr_stress + refresh_mid_burst
    // =========================================================================
    class ddr4_axi4_timing_test extends ddr4_axi4_base_test;
        `uvm_component_utils(ddr4_axi4_timing_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual task run_sequences(uvm_phase phase);
            seq_page_miss             s7  = seq_page_miss::type_id::create("s7");
            seq_wtr_stress            s9  = seq_wtr_stress::type_id::create("s9");
            seq_burst_row_cross       s19 = seq_burst_row_cross::type_id::create("s19");
            seq_partial_write_page_miss_rd s21 = seq_partial_write_page_miss_rd::type_id::create("s21");
            seq_refresh_mid_burst     s22 = seq_refresh_mid_burst::type_id::create("s22");
            s7.start(env.agent.sequencer);
            s9.start(env.agent.sequencer);
            s19.start(env.agent.sequencer);
            s21.start(env.agent.sequencer);
            s22.start(env.agent.sequencer);
        endtask

    endclass : ddr4_axi4_timing_test

    // =========================================================================
    // DMA test — concurrent + outstanding + true outstanding
    // =========================================================================
    class ddr4_axi4_dma_test extends ddr4_axi4_base_test;
        `uvm_component_utils(ddr4_axi4_dma_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual task run_sequences(uvm_phase phase);
            seq_dma_concurrent     s10 = seq_dma_concurrent::type_id::create("s10");
            seq_dma_outstanding    s11 = seq_dma_outstanding::type_id::create("s11");
            seq_true_outstanding   s12 = seq_true_outstanding::type_id::create("s12");
            seq_mixed_burst_outstanding s13 = seq_mixed_burst_outstanding::type_id::create("s13");
            seq_burst_outstanding_drain s15 = seq_burst_outstanding_drain::type_id::create("s15");
            s10.start(env.agent.sequencer);
            s11.start(env.agent.sequencer);
            s12.start(env.agent.sequencer);
            s13.start(env.agent.sequencer);
            s15.start(env.agent.sequencer);
        endtask

    endclass : ddr4_axi4_dma_test

    // =========================================================================
    // Coverage test — all sequences with N_RAND=50
    // =========================================================================
    class ddr4_axi4_coverage_test extends ddr4_axi4_base_test;
        `uvm_component_utils(ddr4_axi4_coverage_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            // Override N_RAND for higher coverage
            uvm_config_db#(int)::set(this, "*", "n_rand", 50);
        endfunction

        virtual task run_sequences(uvm_phase phase);
            ddr4_axi4_full_seq full_seq;
            full_seq = ddr4_axi4_full_seq::type_id::create("full_seq");
            full_seq.start(env.agent.sequencer);
        endtask

    endclass : ddr4_axi4_coverage_test

    // =========================================================================
    // Max outstanding test — saturate AW/AR FIFOs to MAX_OUTSTANDING (16)
    // =========================================================================
    class ddr4_axi4_max_outstanding_test extends ddr4_axi4_base_test;
        `uvm_component_utils(ddr4_axi4_max_outstanding_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual task run_sequences(uvm_phase phase);
            seq_max_outstanding s27 = seq_max_outstanding::type_id::create("s27");
            s27.start(env.agent.sequencer);
        endtask

    endclass : ddr4_axi4_max_outstanding_test

endpackage : ddr4_axi4_tests_pkg

`endif // DDR4_AXI4_TESTS_SV
