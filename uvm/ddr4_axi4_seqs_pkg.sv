// ============================================================================
// File: uvm/ddr4_axi4_seqs_pkg.sv
// Project: KV32 RISC-V Processor
// Description: UVM sequences package — all 26 test sequences matching the
//              BFM testbench ddr4_axi4_bfm_tb.sv sequences 1-26.
//
// Each sequence class extends uvm_sequence#(ddr4_axi4_seq_item) and
// implements a body() task that constructs and sends sequence items.
// A composite ddr4_axi4_full_seq runs all 26 in order.
//
// Design notes:
//   • Write-then-read sequences issue a WRITE item followed immediately by a
//     READ item to the same address(es); the scoreboard validates the read.
//   • Sequences that require inline handshaking (DMA fork/join) use the
//     driver's built-in concurrency via back-to-back item dispatch plus
//     a dedicated ddr4_axi4_virt_seq layer for fork/join control.
//   • Parameters (SIM_DEPTH, AXI_SW, BASE) are read from config_db so each
//     sequence remains agnostic of the DUT configuration at elaboration.
// ============================================================================

/* verilator lint_off UNUSEDSIGNAL  */
/* verilator lint_off WIDTHEXPAND   */
/* verilator lint_off WIDTHTRUNC    */
/* verilator lint_off INITIALDLY    */
/* verilator lint_off PROCASSINIT   */
/* verilator lint_off BLKANDNBLK    */

`ifndef DDR4_AXI4_SEQS_PKG_SV
`define DDR4_AXI4_SEQS_PKG_SV

`include "uvm_macros.svh"

package ddr4_axi4_seqs_pkg;

    import uvm_pkg::*;
    import ddr4_axi4_pkg::*;
    import ddr4_axi4_uvm_pkg::*;

    // =========================================================================
    // Base sequence — holds common parameters
    // =========================================================================
    class ddr4_axi4_base_seq extends uvm_sequence #(ddr4_axi4_seq_item);
        `uvm_object_utils(ddr4_axi4_base_seq)

        // Parameters injected from the test via config_db
        int          n_rand        = 20;
        int          sim_depth     = 32768;
        int          axi_sw        = 4;
        int          axi_sz        = 2;
        int          axi_dw        = 32;
        int          row_stride_words = 16384;
        logic [31:0] base_addr     = 32'h8000_0000;

        function new(string name = "ddr4_axi4_base_seq");
            super.new(name);
        endfunction

        function void pre_body();
            void'(uvm_config_db#(int)::get(null, get_full_name(), "n_rand",           n_rand));
            void'(uvm_config_db#(int)::get(null, get_full_name(), "sim_depth",        sim_depth));
            void'(uvm_config_db#(int)::get(null, get_full_name(), "axi_sw",           axi_sw));
            void'(uvm_config_db#(int)::get(null, get_full_name(), "axi_dw",           axi_dw));
            void'(uvm_config_db#(int)::get(null, get_full_name(), "row_stride_words", row_stride_words));
            void'(uvm_config_db#(logic[31:0])::get(null, get_full_name(), "base_addr", base_addr));
            axi_sz = $clog2(axi_sw);
        endfunction

        // ── Address helpers ────────────────────────────────────────────────────
        function automatic logic [31:0] rand_addr(int max_word);
            int w = $urandom_range(0, max_word - 1);
            return base_addr + 32'(w * axi_sw);
        endfunction

        function automatic logic [31:0] rand_incr_addr(int max_word, int len);
            int w = $urandom_range(0, max_word - len - 2);
            return base_addr + 32'(w * axi_sw);
        endfunction

        function automatic logic [31:0] rand_wrap_addr();
            int w = $urandom_range(0, (sim_depth / 2) - 1);
            return base_addr + 32'(w * axi_sw);
        endfunction

        // ── Item factory helpers ───────────────────────────────────────────────
        function automatic ddr4_axi4_seq_item make_write(
            logic [3:0]  id,
            logic [31:0] addr,
            logic [1:0]  burst,
            logic [7:0]  len,
            logic [31:0] wdata [],   // dynamic, caller-sized
            logic [3:0]  wstrb []
        );
            ddr4_axi4_seq_item it = ddr4_axi4_seq_item::type_id::create("wr_item");
            it.is_read       = 1'b0;
            it.id            = id;
            it.addr          = addr;
            it.burst         = burst;
            it.len           = len;
            it.size          = 3'(axi_sz);
            it.apply_bp      = 1'b0;
            it.bp_hold       = 1;
            it.use_force_size= 1'b0;
            for (int b = 0; b <= int'(len); b++) begin
                it.wdata[b] = wdata[b];
                it.wstrb[b] = wstrb[b];
            end
            return it;
        endfunction

        function automatic ddr4_axi4_seq_item make_read(
            logic [3:0]  id,
            logic [31:0] addr,
            logic [1:0]  burst,
            logic [7:0]  len,
            logic        apply_bp = 1'b0
        );
            ddr4_axi4_seq_item it = ddr4_axi4_seq_item::type_id::create("rd_item");
            it.is_read       = 1'b1;
            it.id            = id;
            it.addr          = addr;
            it.burst         = burst;
            it.len           = len;
            it.size          = 3'(axi_sz);
            it.apply_bp      = apply_bp;
            it.bp_hold       = 1;
            it.use_force_size= 1'b0;
            return it;
        endfunction

        // Send item and wait for completion
        task do_item(ddr4_axi4_seq_item it);
            start_item(it);
            finish_item(it);
        endtask

    endclass : ddr4_axi4_base_seq

    // =========================================================================
    // SEQ 1: single_rw — random single read-after-write
    // =========================================================================
    class seq_single_rw extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_single_rw)
        function new(string name = "seq_single_rw"); super.new(name); endfunction

        task body();
            `uvm_info(get_name(), $sformatf("=== SEQ 1: single_rw (%0d iterations) ===", n_rand), UVM_LOW)
            for (int i = 0; i < n_rand; i++) begin
                logic [31:0] wdat_dyn []; logic [3:0] wstr_dyn [];
                logic [31:0] addr;
                wdat_dyn = new[1]; wstr_dyn = new[1];
                addr = rand_addr(sim_depth);
                wdat_dyn[0] = $urandom();
                wstr_dyn[0] = 4'hF;
                do_item(make_write(4'h1, addr, 2'b01, 8'h00, wdat_dyn, wstr_dyn));
                do_item(make_read (4'h1, addr, 2'b01, 8'h00));
            end
        endtask
    endclass : seq_single_rw

    // =========================================================================
    // SEQ 2: burst_incr — random INCR burst write/read-back
    // =========================================================================
    class seq_burst_incr extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_burst_incr)
        function new(string name = "seq_burst_incr"); super.new(name); endfunction

        task body();
            `uvm_info(get_name(), $sformatf("=== SEQ 2: burst_incr (%0d iterations) ===", n_rand), UVM_LOW)
            for (int i = 0; i < n_rand; i++) begin
                logic [7:0]  len  = 8'($urandom_range(1, 7));
                logic [31:0] addr = rand_incr_addr(sim_depth, int'(len));
                logic [31:0] wdat_dyn []; logic [3:0] wstr_dyn [];
                wdat_dyn = new[int'(len)+1]; wstr_dyn = new[int'(len)+1];
                for (int b = 0; b <= int'(len); b++) begin
                    wdat_dyn[b] = $urandom();
                    wstr_dyn[b] = 4'hF;
                end
                do_item(make_write(4'h2, addr, 2'b01, len, wdat_dyn, wstr_dyn));
                do_item(make_read (4'h2, addr, 2'b01, len));
            end
        endtask
    endclass : seq_burst_incr

    // =========================================================================
    // SEQ 3: burst_wrap — WRAP burst (len = 1,3,7,15)
    // =========================================================================
    class seq_burst_wrap extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_burst_wrap)
        function new(string name = "seq_burst_wrap"); super.new(name); endfunction

        task body();
            int lens [4] = '{1, 3, 7, 15};
            `uvm_info(get_name(), $sformatf("=== SEQ 3: burst_wrap (%0d iterations) ===", n_rand), UVM_LOW)
            for (int i = 0; i < n_rand; i++) begin
                logic [7:0]  len  = 8'(lens[$urandom_range(0, 3)]);
                logic [31:0] addr = rand_wrap_addr();
                logic [31:0] wdat_dyn []; logic [3:0] wstr_dyn [];
                wdat_dyn = new[int'(len)+1]; wstr_dyn = new[int'(len)+1];
                for (int b = 0; b <= int'(len); b++) begin
                    wdat_dyn[b] = $urandom();
                    wstr_dyn[b] = 4'hF;
                end
                do_item(make_write(4'h3, addr, 2'b10, len, wdat_dyn, wstr_dyn));
                do_item(make_read (4'h3, addr, 2'b10, len));
            end
        endtask
    endclass : seq_burst_wrap

    // =========================================================================
    // SEQ 4: burst_fixed — FIXED burst (same address, last beat wins)
    // =========================================================================
    class seq_burst_fixed extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_burst_fixed)
        function new(string name = "seq_burst_fixed"); super.new(name); endfunction

        task body();
            localparam int FIX_LEN = 3;
            `uvm_info(get_name(), $sformatf("=== SEQ 4: burst_fixed (%0d iterations) ===", n_rand), UVM_LOW)
            for (int i = 0; i < n_rand; i++) begin
                logic [31:0] addr = rand_addr(sim_depth);
                logic [31:0] wdat_dyn []; logic [3:0] wstr_dyn [];
                wdat_dyn = new[FIX_LEN+1]; wstr_dyn = new[FIX_LEN+1];
                for (int b = 0; b <= FIX_LEN; b++) begin
                    wdat_dyn[b] = $urandom();
                    wstr_dyn[b] = 4'hF;
                end
                do_item(make_write(4'h4, addr, 2'b00, 8'(FIX_LEN), wdat_dyn, wstr_dyn));
                do_item(make_read (4'h4, addr, 2'b00, 8'(FIX_LEN)));
            end
        endtask
    endclass : seq_burst_fixed

    // =========================================================================
    // SEQ 5: strobe — partial byte-strobe patterns
    // =========================================================================
    class seq_strobe extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_strobe)
        function new(string name = "seq_strobe"); super.new(name); endfunction

        task body();
            `uvm_info(get_name(), $sformatf("=== SEQ 5: strobe (%0d iterations) ===", n_rand), UVM_LOW)
            for (int i = 0; i < n_rand; i++) begin
                logic [31:0] addr = rand_addr(sim_depth);
                logic [31:0] wd1 []; logic [3:0] ws1 [];
                logic [31:0] wd2 []; logic [3:0] ws2 [];
                // First: full-write
                wd1 = new[1]; ws1 = new[1];
                wd1[0] = 32'hFFFF_FFFF; ws1[0] = 4'hF;
                do_item(make_write(4'h5, addr, 2'b01, 8'h00, wd1, ws1));
                // Then: partial strobe overwrite
                wd2 = new[1]; ws2 = new[1];
                wd2[0] = $urandom();
                ws2[0] = 4'($urandom_range(1, 14));  // partial, not zero, not full
                do_item(make_write(4'h5, addr, 2'b01, 8'h00, wd2, ws2));
                do_item(make_read (4'h5, addr, 2'b01, 8'h00));
            end
        endtask
    endclass : seq_strobe

    // =========================================================================
    // SEQ 6: backpressure — random bready/rready back-pressure
    // =========================================================================
    class seq_backpressure extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_backpressure)
        function new(string name = "seq_backpressure"); super.new(name); endfunction

        task body();
            `uvm_info(get_name(), $sformatf("=== SEQ 6: backpressure (%0d iterations) ===", n_rand), UVM_LOW)
            for (int i = 0; i < n_rand; i++) begin
                logic [7:0]  len  = 8'($urandom_range(0, 7));
                logic [31:0] addr = rand_incr_addr(sim_depth, int'(len));
                logic        bp   = logic'($urandom_range(0, 1));
                logic [31:0] wdyn []; logic [3:0] sdyn [];
                ddr4_axi4_seq_item wr;
                ddr4_axi4_seq_item rd;
                wdyn = new[int'(len)+1]; sdyn = new[int'(len)+1];
                for (int b = 0; b <= int'(len); b++) begin
                    wdyn[b] = $urandom(); sdyn[b] = 4'hF;
                end
                // Write with optional BP
                wr = make_write(4'h6, addr, 2'b01, len, wdyn, sdyn);
                wr.apply_bp = bp; wr.bp_hold = 1;
                do_item(wr);
                // Read with optional BP
                rd = make_read(4'h6, addr, 2'b01, len, bp);
                do_item(rd);
            end
        endtask
    endclass : seq_backpressure

    // =========================================================================
    // SEQ 7: page_miss — alternating row-0 / row-1 to force page misses
    // =========================================================================
    class seq_page_miss extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_page_miss)
        function new(string name = "seq_page_miss"); super.new(name); endfunction

        task body();
            localparam int N_PM = 8;
            logic [31:0] addr_r0 = base_addr;
            logic [31:0] addr_r1 = base_addr + 32'(row_stride_words * axi_sw);
            `uvm_info(get_name(), "=== SEQ 7: page_miss ===", UVM_LOW)
            for (int i = 0; i < N_PM; i++) begin
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[1]; ws = new[1];
                wd[0] = $urandom(); ws[0] = 4'hF;
                do_item(make_write(4'hA, addr_r0, 2'b01, 8'h00, wd, ws));
                wd[0] = $urandom();
                do_item(make_write(4'hA, addr_r1, 2'b01, 8'h00, wd, ws));
            end
            do_item(make_read(4'hA, addr_r0, 2'b01, 8'h00));
            do_item(make_read(4'hA, addr_r1, 2'b01, 8'h00));
        endtask
    endclass : seq_page_miss

    // =========================================================================
    // SEQ 8: oob_access — out-of-range address → expects SLVERR
    // =========================================================================
    class seq_oob_access extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_oob_access)

        // Reference to scoreboard to increment error counters correctly
        // OOB write/read should return SLVERR (2'b10); scoreboard is NOT updated
        function new(string name = "seq_oob_access"); super.new(name); endfunction

        task body();
            logic [31:0] oob_addr = base_addr + 32'(sim_depth * axi_sw);
            `uvm_info(get_name(), "=== SEQ 8: oob_access (SLVERR expected) ===", UVM_LOW)
            // Write OOB
            begin
                ddr4_axi4_seq_item wr = ddr4_axi4_seq_item::type_id::create("oob_wr");
                wr.is_read  = 1'b0;
                wr.id       = 4'h0;
                wr.addr     = oob_addr;
                wr.len      = 8'h00;
                wr.size     = 3'(axi_sz);
                wr.burst    = 2'b01;
                wr.wdata[0] = $urandom();
                wr.wstrb[0] = 4'hF;
                wr.apply_bp = 1'b0;
                wr.bp_hold  = 1;
                wr.use_force_size = 1'b0;
                start_item(wr); finish_item(wr);
                if (wr.bresp === 2'b10)
                    `uvm_info(get_name(), "OOB write SLVERR [PASS]", UVM_LOW)
                else
                    `uvm_error(get_name(), $sformatf("OOB write got bresp=%0b, expected SLVERR(10)", wr.bresp))
            end
            // Read OOB — scoreboard ignores OOB reads
            begin
                ddr4_axi4_seq_item rd = make_read(4'h0, oob_addr, 2'b01, 8'h00);
                start_item(rd); finish_item(rd);
                if (rd.rresp[0] === 2'b10)
                    `uvm_info(get_name(), "OOB read  SLVERR [PASS]", UVM_LOW)
                else
                    `uvm_error(get_name(), $sformatf("OOB read  got rresp=%0b, expected SLVERR(10)", rd.rresp[0]))
            end
        endtask
    endclass : seq_oob_access

    // =========================================================================
    // SEQ 9: wtr_stress — write Bank Group 1 then read Bank Group 0 (tWTR_L)
    // =========================================================================
    class seq_wtr_stress extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_wtr_stress)
        function new(string name = "seq_wtr_stress"); super.new(name); endfunction

        task body();
            localparam int WTR_PAIRS = 4;
            logic [31:0] addr_bg0 = base_addr;
            logic [31:0] addr_bg1 = base_addr + 32'h0000_4000;
            `uvm_info(get_name(), $sformatf("=== SEQ 9: wtr_stress (%0d pairs) ===", WTR_PAIRS), UVM_LOW)
            for (int i = 0; i < WTR_PAIRS; i++) begin
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[1]; ws = new[1];
                wd[0] = $urandom(); ws[0] = 4'hF;
                do_item(make_write(4'h0, addr_bg1, 2'b01, 8'h00, wd, ws));
                do_item(make_read (4'h0, addr_bg0, 2'b01, 8'h00));
            end
        endtask
    endclass : seq_wtr_stress

    // =========================================================================
    // SEQ 10–11: DMA sequences  (concurrent & outstanding)
    //   These sequences require fork/join semantics. They implement the same
    //   logic as the BFM tasks using back-to-back item dispatch.  The write
    //   item is always sent first; the driver completes it before the read.
    //   True concurrency is approximated: write issued → scoreboard updated →
    //   read issued (scoreboard validates).  For the AXI4 slave, the write
    //   channel completes independently of the read channel ordering.
    // =========================================================================
    class seq_dma_concurrent extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_dma_concurrent)
        function new(string name = "seq_dma_concurrent"); super.new(name); endfunction

        task body();
            localparam int DMA_N  = 8;
            localparam int WR_OFF = 16384;  // sim_depth/2 default
            `uvm_info(get_name(), $sformatf("=== SEQ 10: dma_concurrent (%0d pairs) ===", DMA_N), UVM_LOW)

            // Phase 1: pre-populate read zone
            for (int i = 0; i < DMA_N; i++) begin
                logic [31:0] addr = base_addr + 32'(i * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[1]; ws = new[1];
                wd[0] = 32'hA0A0_0000 | i; ws[0] = 4'hF;
                do_item(make_write(4'h0, addr, 2'b01, 8'h00, wd, ws));
            end

            // Phase 2: write new zone, then read previously written data
            for (int i = 0; i < DMA_N; i++) begin
                logic [31:0] wr_addr = base_addr + 32'((WR_OFF + i) * axi_sw);
                logic [31:0] rd_addr = base_addr + 32'(i * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[1]; ws = new[1];
                wd[0] = 32'hC0C0_0000 | i; ws[0] = 4'hF;
                do_item(make_write(4'h4, wr_addr, 2'b01, 8'h00, wd, ws));
                do_item(make_read (4'h5, rd_addr, 2'b01, 8'h00));
            end
        endtask
    endclass : seq_dma_concurrent

    // =========================================================================
    // SEQ 11: dma_outstanding — back-to-back writes then reads
    // =========================================================================
    class seq_dma_outstanding extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_dma_outstanding)
        function new(string name = "seq_dma_outstanding"); super.new(name); endfunction

        task body();
            localparam int OST_N  = 8;
            localparam int WR_OFF = 16400;  // sim_depth/2 + 16
            `uvm_info(get_name(), $sformatf("=== SEQ 11: dma_outstanding (%0d back-to-back) ===", OST_N), UVM_LOW)
            // Part A: back-to-back writes
            for (int i = 0; i < OST_N; i++) begin
                logic [31:0] addr = base_addr + 32'((WR_OFF + i) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[1]; ws = new[1];
                wd[0] = 32'hD0D0_0000 | i; ws[0] = 4'hF;
                do_item(make_write(4'h6, addr, 2'b01, 8'h00, wd, ws));
            end
            // Part C: back-to-back reads verifying written data
            for (int i = 0; i < OST_N; i++) begin
                logic [31:0] addr = base_addr + 32'((WR_OFF + i) * axi_sw);
                do_item(make_read(4'h9, addr, 2'b01, 8'h00));
            end
        endtask
    endclass : seq_dma_outstanding

    // =========================================================================
    // SEQ 12: true_outstanding — flood AW/AR FIFO then drain
    // =========================================================================
    class seq_true_outstanding extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_true_outstanding)
        function new(string name = "seq_true_outstanding"); super.new(name); endfunction

        task body();
            localparam int OST_N   = 16;
            localparam int WR_BASE = 16416;  // sim_depth/2 + 32
            `uvm_info(get_name(), $sformatf("=== SEQ 12: true_outstanding (%0d AWs/ARs) ===", OST_N), UVM_LOW)
            // Part A: writes
            for (int i = 0; i < OST_N; i++) begin
                logic [31:0] addr = base_addr + 32'((WR_BASE + i) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[1]; ws = new[1];
                wd[0] = 32'hF1F1_0000 | i; ws[0] = 4'hF;
                do_item(make_write(4'hA, addr, 2'b01, 8'h00, wd, ws));
            end
            // Part B: reads verifying
            for (int i = 0; i < OST_N; i++) begin
                logic [31:0] addr = base_addr + 32'((WR_BASE + i) * axi_sw);
                do_item(make_read(4'hB, addr, 2'b01, 8'h00));
            end
        endtask
    endclass : seq_true_outstanding

    // =========================================================================
    // SEQ 13: mixed_burst_outstanding — AR FIFO with INCR/WRAP/FIXED
    // =========================================================================
    class seq_mixed_burst_outstanding extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_mixed_burst_outstanding)
        function new(string name = "seq_mixed_burst_outstanding"); super.new(name); endfunction

        task body();
            localparam int OST_N   = 12;
            localparam int WR_BASE = 16448;  // sim_depth/2 + 64
            logic [1:0] burst_types [3] = '{2'b01, 2'b10, 2'b00};  // INCR, WRAP, FIXED
            `uvm_info(get_name(), $sformatf("=== SEQ 13: mixed_burst_outstanding (%0d ARs) ===", OST_N), UVM_LOW)
            // Pre-populate with all burst types
            for (int i = 0; i < OST_N; i++) begin
                logic [1:0]  btype = burst_types[i % 3];
                logic [7:0]  blen  = (btype == 2'b10) ? 8'h03 : 8'h00;
                logic [31:0] addr  = base_addr + 32'((WR_BASE + i * 2) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[int'(blen)+1]; ws = new[int'(blen)+1];
                for (int b = 0; b <= int'(blen); b++) begin wd[b] = $urandom(); ws[b] = 4'hF; end
                do_item(make_write(4'hC, addr, btype, blen, wd, ws));
            end
            // Read back with same burst types
            for (int i = 0; i < OST_N; i++) begin
                logic [1:0]  btype = burst_types[i % 3];
                logic [7:0]  blen  = (btype == 2'b10) ? 8'h03 : 8'h00;
                logic [31:0] addr  = base_addr + 32'((WR_BASE + i * 2) * axi_sw);
                do_item(make_read(4'hC, addr, btype, blen));
            end
        endtask
    endclass : seq_mixed_burst_outstanding

    // =========================================================================
    // SEQ 14: outstanding_mixed_rw — interleaved WR+RD pairs for each burst type
    // =========================================================================
    class seq_outstanding_mixed_rw extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_outstanding_mixed_rw)
        function new(string name = "seq_outstanding_mixed_rw"); super.new(name); endfunction

        task body();
            localparam int PAIRS   = 8;
            localparam int WR_BASE = 16512;  // sim_depth/2 + 128
            logic [1:0] burst_types [3] = '{2'b01, 2'b10, 2'b00};
            `uvm_info(get_name(), $sformatf("=== SEQ 14: outstanding_mixed_rw (%0d pairs) ===", PAIRS), UVM_LOW)
            for (int i = 0; i < PAIRS; i++) begin
                logic [1:0]  btype = burst_types[i % 3];
                logic [7:0]  blen  = (btype == 2'b10) ? 8'h03 : 8'h00;
                logic [31:0] addr  = base_addr + 32'((WR_BASE + i * 4) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[int'(blen)+1]; ws = new[int'(blen)+1];
                for (int b = 0; b <= int'(blen); b++) begin wd[b] = $urandom(); ws[b] = 4'hF; end
                do_item(make_write(4'hD, addr, btype, blen, wd, ws));
                do_item(make_read (4'hE, addr, btype, blen));
            end
        endtask
    endclass : seq_outstanding_mixed_rw

    // =========================================================================
    // SEQ 15: burst_outstanding_drain — AW FIFO saturation with burst writes + AR overlay reads
    // =========================================================================
    class seq_burst_outstanding_drain extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_burst_outstanding_drain)
        function new(string name = "seq_burst_outstanding_drain"); super.new(name); endfunction

        task body();
            localparam int OST_N     = 8;
            localparam int BURST_LEN = 7;    // 8-beat
            localparam int WR_BASE   = 16640;  // sim_depth/2 + 160
            `uvm_info(get_name(), $sformatf("=== SEQ 15: burst_outstanding_drain (%0d x 8-beat) ===", OST_N), UVM_LOW)
            for (int i = 0; i < OST_N; i++) begin
                logic [31:0] addr = base_addr + 32'((WR_BASE + i * (BURST_LEN + 1)) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[BURST_LEN+1]; ws = new[BURST_LEN+1];
                for (int b = 0; b <= BURST_LEN; b++) begin wd[b] = $urandom(); ws[b] = 4'hF; end
                do_item(make_write(4'hF, addr, 2'b01, 8'(BURST_LEN), wd, ws));
            end
            for (int i = 0; i < OST_N; i++) begin
                logic [31:0] addr = base_addr + 32'((WR_BASE + i * (BURST_LEN + 1)) * axi_sw);
                do_item(make_read(4'hF, addr, 2'b01, 8'(BURST_LEN)));
            end
        endtask
    endclass : seq_burst_outstanding_drain

    // =========================================================================
    // SEQ 16: burst_per_beat_strobe — per-beat partial strobe INCR burst
    // =========================================================================
    class seq_burst_per_beat_strobe extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_burst_per_beat_strobe)
        function new(string name = "seq_burst_per_beat_strobe"); super.new(name); endfunction

        task body();
            localparam int MAX_LEN  = 7;
            localparam int WR_BASE5 = 16584;  // sim_depth/2 + 200
            `uvm_info(get_name(), $sformatf("=== SEQ 16: burst_per_beat_strobe (%0d iters) ===", n_rand), UVM_LOW)
            for (int i = 0; i < n_rand; i++) begin
                logic [7:0]  len  = 8'($urandom_range(1, MAX_LEN));
                logic [31:0] addr = base_addr + 32'((WR_BASE5 + i * (MAX_LEN + 2)) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[int'(len)+1]; ws = new[int'(len)+1];
                for (int b = 0; b <= int'(len); b++) begin
                    wd[b] = $urandom();
                    ws[b] = 4'($urandom_range(1, 14));  // partial strobe per beat
                end
                do_item(make_write(4'h1, addr, 2'b01, len, wd, ws));
                do_item(make_read (4'h1, addr, 2'b01, len));
            end
        endtask
    endclass : seq_burst_per_beat_strobe

    // =========================================================================
    // SEQ 17: burst_bp_per_beat — per-beat rready back-pressure
    // =========================================================================
    class seq_burst_bp_per_beat extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_burst_bp_per_beat)
        function new(string name = "seq_burst_bp_per_beat"); super.new(name); endfunction

        task body();
            localparam int MAX_LEN  = 7;
            localparam int WR_BASE6 = 16984;  // sim_depth/2 + 600
            `uvm_info(get_name(), $sformatf("=== SEQ 17: burst_bp_per_beat (%0d iters) ===", n_rand), UVM_LOW)
            for (int i = 0; i < n_rand; i++) begin
                logic [7:0]  len  = 8'($urandom_range(1, MAX_LEN));
                logic [31:0] addr = base_addr + 32'((WR_BASE6 + i * (MAX_LEN + 2)) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                ddr4_axi4_seq_item rd;
                wd = new[int'(len)+1]; ws = new[int'(len)+1];
                for (int b = 0; b <= int'(len); b++) begin wd[b] = $urandom(); ws[b] = 4'hF; end
                do_item(make_write(4'h7, addr, 2'b01, len, wd, ws));
                // Read with per-beat back-pressure (apply_bp=1 → driver inserts hold)
                rd = make_read(4'h7, addr, 2'b01, len, 1'b1 /*bp*/);
                do_item(rd);
            end
        endtask
    endclass : seq_burst_bp_per_beat

    // =========================================================================
    // SEQ 18: narrow_size — sub-word transfers (size=0 and size=1)
    // =========================================================================
    class seq_narrow_size extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_narrow_size)
        function new(string name = "seq_narrow_size"); super.new(name); endfunction

        task body();
            localparam int N_NARROW    = 20;
            localparam int NARROW_BASE = 17384;  // sim_depth/2 + 1000
            `uvm_info(get_name(), $sformatf("=== SEQ 18: narrow_size (%0d x 1B + %0d x 2B) ===",
                                             N_NARROW, N_NARROW), UVM_LOW)
            // 1-byte (size=0)
            for (int i = 0; i < N_NARROW; i++) begin
                int              wbi       = NARROW_BASE + (i % 16);
                logic [31:0]     word_addr = base_addr + 32'(wbi * axi_sw);
                int              byte_lane = i % axi_sw;
                logic [7:0]      new_byte  = 8'($urandom());
                logic [31:0]     wr_full   = $urandom();
                // Full baseline write
                logic [31:0] wd []; logic [3:0] ws [];
                ddr4_axi4_seq_item nw;
                wd = new[1]; ws = new[1];
                wd[0] = wr_full; ws[0] = 4'hF;
                do_item(make_write(4'h2, word_addr, 2'b01, 8'h00, wd, ws));
                // Narrow 1-byte write
                nw = ddr4_axi4_seq_item::type_id::create("narrow_wr");
                nw.is_read        = 1'b0;
                nw.id             = 4'h2;
                nw.addr           = word_addr + 32'(byte_lane);
                nw.burst          = 2'b01;
                nw.len            = 8'h00;
                nw.size           = 3'b010;  // keep bus-width size for DUT
                nw.wdata[0]       = {new_byte, new_byte, new_byte, new_byte};
                nw.wstrb[0]       = 4'(1 << byte_lane);
                nw.apply_bp       = 1'b0;
                nw.bp_hold        = 1;
                nw.use_force_size = 1'b1;
                nw.force_size     = 3'b000;  // awsize = 0 (1 byte)
                do_item(nw);
                do_item(make_read(4'h2, word_addr, 2'b01, 8'h00));
            end
            // 2-byte (size=1) — only when bus is wide enough
            if (axi_sw >= 2) begin
                for (int i = 0; i < N_NARROW; i++) begin
                    int              wbi       = NARROW_BASE + 16 + (i % 16);
                    logic [31:0]     word_addr = base_addr + 32'(wbi * axi_sw);
                    int              hw_lane   = i % (axi_sw / 2);
                    logic [15:0]     new_hw    = 16'($urandom());
                    logic [31:0] wd []; logic [3:0] ws [];
                    ddr4_axi4_seq_item nw2;
                    wd = new[1]; ws = new[1];
                    wd[0] = $urandom(); ws[0] = 4'hF;
                    do_item(make_write(4'h2, word_addr, 2'b01, 8'h00, wd, ws));
                    nw2 = ddr4_axi4_seq_item::type_id::create("narrow2_wr");
                    nw2.is_read        = 1'b0;
                    nw2.id             = 4'h2;
                    nw2.addr           = word_addr + 32'(hw_lane * 2);
                    nw2.burst          = 2'b01;
                    nw2.len            = 8'h00;
                    nw2.size           = 3'b010;
                    nw2.wdata[0]       = {(32/16){new_hw}};
                    nw2.wstrb[0]       = 4'(2'b11 << (hw_lane * 2));
                    nw2.apply_bp       = 1'b0;
                    nw2.bp_hold        = 1;
                    nw2.use_force_size = 1'b1;
                    nw2.force_size     = 3'b001;  // arsize = 1 (2 bytes)
                    do_item(nw2);
                    do_item(make_read(4'h2, word_addr, 2'b01, 8'h00));
                end
            end
        endtask
    endclass : seq_narrow_size

    // =========================================================================
    // SEQ 19: burst_row_cross — INCR burst crossing DDR4 row boundary
    // =========================================================================
    class seq_burst_row_cross extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_burst_row_cross)
        function new(string name = "seq_burst_row_cross"); super.new(name); endfunction

        task body();
            localparam int CROSS_LEN = 7;
            localparam int N_CROSS   = 4;
            `uvm_info(get_name(), $sformatf("=== SEQ 19: burst_row_cross (%0d x 8-beat INCR) ===", N_CROSS), UVM_LOW)
            for (int i = 0; i < N_CROSS; i++) begin
                int          offset = (i % 2 == 0) ? 2 : 4;
                logic [31:0] addr   = base_addr + 32'((row_stride_words - offset) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[CROSS_LEN+1]; ws = new[CROSS_LEN+1];
                for (int b = 0; b <= CROSS_LEN; b++) begin
                    wd[b] = 32'hD4D4_0000 | (i << 4) | b; ws[b] = 4'hF;
                end
                do_item(make_write(4'hD, addr, 2'b01, 8'(CROSS_LEN), wd, ws));
                do_item(make_read (4'hD, addr, 2'b01, 8'(CROSS_LEN)));
            end
        endtask
    endclass : seq_burst_row_cross

    // =========================================================================
    // SEQ 20: id_stress — AXI ID passthrough for all IDs 0 to 2^IDW-1
    // =========================================================================
    class seq_id_stress extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_id_stress)
        function new(string name = "seq_id_stress"); super.new(name); endfunction

        task body();
            localparam int ID_BASE = 17484;  // sim_depth/2 + 1100
            localparam int N_IDS   = 16;     // 2^AXI_IDW
            `uvm_info(get_name(), $sformatf("=== SEQ 20: id_stress (IDs 0-%0d) ===", N_IDS - 1), UVM_LOW)
            for (int id = 0; id < N_IDS; id++) begin
                logic [31:0] addr = base_addr + 32'((ID_BASE + id) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[1]; ws = new[1];
                wd[0] = 32'hE5E5_0000 | id; ws[0] = 4'hF;
                do_item(make_write(4'(id), addr, 2'b01, 8'h00, wd, ws));
                do_item(make_read (4'(id), addr, 2'b01, 8'h00));
            end
        endtask
    endclass : seq_id_stress

    // =========================================================================
    // SEQ 21: partial_write_page_miss_rd
    // =========================================================================
    class seq_partial_write_page_miss_rd extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_partial_write_page_miss_rd)
        function new(string name = "seq_partial_write_page_miss_rd"); super.new(name); endfunction

        task body();
            localparam int N_PM2 = 6;
            `uvm_info(get_name(), $sformatf("=== SEQ 21: partial_write_page_miss_rd (%0d iters) ===", N_PM2), UVM_LOW)
            for (int i = 0; i < N_PM2; i++) begin
                logic [31:0] addr_r0 = base_addr + 32'((row_stride_words / 2 + i) * axi_sw);
                logic [31:0] addr_r1 = base_addr + 32'((row_stride_words + 8 + i) * axi_sw);
                logic [3:0]  partial_strb = 4'($urandom_range(1, 14));
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[1]; ws = new[1];
                // 1: full write
                wd[0] = $urandom(); ws[0] = 4'hF;
                do_item(make_write(4'h3, addr_r0, 2'b01, 8'h00, wd, ws));
                // 2: partial overwrite
                wd[0] = $urandom(); ws[0] = partial_strb;
                do_item(make_write(4'h3, addr_r0, 2'b01, 8'h00, wd, ws));
                // 3: page-miss write to row 1
                wd[0] = $urandom(); ws[0] = 4'hF;
                do_item(make_write(4'h3, addr_r1, 2'b01, 8'h00, wd, ws));
                // 4: read back row-0
                do_item(make_read(4'h3, addr_r0, 2'b01, 8'h00));
            end
        endtask
    endclass : seq_partial_write_page_miss_rd

    // =========================================================================
    // SEQ 22: refresh_mid_burst — 16 x 16-beat INCR bursts during refresh window
    // =========================================================================
    class seq_refresh_mid_burst extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_refresh_mid_burst)
        function new(string name = "seq_refresh_mid_burst"); super.new(name); endfunction

        task body();
            localparam int N_LONG   = 16;
            localparam int LONG_LEN = 15;
            localparam int RFR_BASE = 17584;  // sim_depth/2 + 1200
            `uvm_info(get_name(), $sformatf("=== SEQ 22: refresh_mid_burst (%0d x 16-beat) ===", N_LONG), UVM_LOW)
            for (int i = 0; i < N_LONG; i++) begin
                logic [31:0] addr = base_addr + 32'((RFR_BASE + i * (LONG_LEN + 1)) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                wd = new[LONG_LEN+1]; ws = new[LONG_LEN+1];
                for (int b = 0; b <= LONG_LEN; b++) begin
                    wd[b] = 32'hF6F6_0000 | (i << 4) | b; ws[b] = 4'hF;
                end
                do_item(make_write(4'hF, addr, 2'b01, 8'(LONG_LEN), wd, ws));
            end
            for (int i = 0; i < N_LONG; i++) begin
                logic [31:0] addr = base_addr + 32'((RFR_BASE + i * (LONG_LEN + 1)) * axi_sw);
                do_item(make_read(4'hF, addr, 2'b01, 8'(LONG_LEN)));
            end
        endtask
    endclass : seq_refresh_mid_burst

    // =========================================================================
    // SEQ 23: wstrb_zero_beat — all-zero wstrb beat is a no-op
    // =========================================================================
    class seq_wstrb_zero_beat extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_wstrb_zero_beat)
        function new(string name = "seq_wstrb_zero_beat"); super.new(name); endfunction

        task body();
            localparam int ZERO_BASE = 17984;  // varied base
            `uvm_info(get_name(), $sformatf("=== SEQ 23: wstrb_zero_beat (%0d x 4-beat) ===", n_rand), UVM_LOW)
            for (int i = 0; i < n_rand; i++) begin
                logic [31:0] addr = base_addr + 32'((ZERO_BASE + i * 6) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                // 4-beat INCR: beats 0,2 = full strobe; beats 1,3 = zero strobe
                wd = new[4]; ws = new[4];
                for (int b = 0; b < 4; b++) begin
                    wd[b] = $urandom();
                    ws[b] = (b % 2 == 0) ? 4'hF : 4'h0;
                end
                do_item(make_write(4'h8, addr, 2'b01, 8'h03, wd, ws));
                do_item(make_read (4'h8, addr, 2'b01, 8'h03));
            end
        endtask
    endclass : seq_wstrb_zero_beat

    // =========================================================================
    // SEQ 24: max_burst — 256-beat INCR burst (AXI4 max awlen = 8'hFF)
    // =========================================================================
    class seq_max_burst extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_max_burst)
        function new(string name = "seq_max_burst"); super.new(name); endfunction

        task body();
            localparam int MAX_LEN  = 255;   // 8'hFF
            localparam int MAX_BASE = 18384; // safe offset
            logic [31:0] addr = base_addr + 32'(MAX_BASE * axi_sw);
            logic [31:0] wd [];
            logic [3:0]  ws [];
            `uvm_info(get_name(), "=== SEQ 24: max_burst (256-beat INCR) ===", UVM_LOW)
            wd = new[MAX_LEN+1]; ws = new[MAX_LEN+1];
            for (int b = 0; b <= MAX_LEN; b++) begin wd[b] = $urandom(); ws[b] = 4'hF; end
            do_item(make_write(4'h9, addr, 2'b01, 8'(MAX_LEN), wd, ws));
            do_item(make_read (4'h9, addr, 2'b01, 8'(MAX_LEN)));
        endtask
    endclass : seq_max_burst

    // =========================================================================
    // SEQ 25: bready_bp — write response B-channel multi-cycle hold-off
    // =========================================================================
    class seq_bready_bp extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_bready_bp)
        function new(string name = "seq_bready_bp"); super.new(name); endfunction

        task body();
            localparam int BREADY_BP_BASE = 18640;
            `uvm_info(get_name(), $sformatf("=== SEQ 25: bready_bp (%0d iters, hold 2-8 cyc) ===", n_rand), UVM_LOW)
            for (int i = 0; i < n_rand; i++) begin
                logic [31:0] addr = base_addr + 32'((BREADY_BP_BASE + i) * axi_sw);
                logic [31:0] wd []; logic [3:0] ws [];
                ddr4_axi4_seq_item wr;
                wd = new[1]; ws = new[1];
                wd[0] = $urandom(); ws[0] = 4'hF;
                wr = make_write(4'hB, addr, 2'b01, 8'h00, wd, ws);
                wr.apply_bp = 1'b1;
                wr.bp_hold  = $urandom_range(2, 8);
                do_item(wr);
                do_item(make_read(4'hB, addr, 2'b01, 8'h00));
            end
        endtask
    endclass : seq_bready_bp

    // =========================================================================
    // SEQ 26: wrap_boundary_start — WRAP burst starting at top of wrap window
    // =========================================================================
    class seq_wrap_boundary_start extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_wrap_boundary_start)
        function new(string name = "seq_wrap_boundary_start"); super.new(name); endfunction

        task body();
            localparam int WRAP_EDGE_BASE = 18504;  // sim_depth/2 + 2120
            int wrap_lens [3] = '{1, 3, 7};
            int word_accum = 0;
            `uvm_info(get_name(), "=== SEQ 26: wrap_boundary_start (2/4/8-beat from top) ===", UVM_LOW)
            for (int k = 0; k < 3; k++) begin
                int          L          = wrap_lens[k];
                int          N_BEATS_W  = L + 1;
                int          wrap_base_word;
                logic [31:0] wrap_base_addr, top_addr;
                logic [31:0] wd_wrap [];
                logic [3:0]  ws_wrap [];

                wrap_base_word = WRAP_EDGE_BASE + word_accum;
                wrap_base_word = (wrap_base_word / N_BEATS_W) * N_BEATS_W;
                top_addr       = base_addr + 32'((wrap_base_word + L) * axi_sw);
                wrap_base_addr = base_addr + 32'(wrap_base_word * axi_sw);

                // Pre-write all N_BEATS_W words
                for (int w = 0; w < N_BEATS_W; w++) begin
                    logic [31:0] init_addr = wrap_base_addr + 32'(w * axi_sw);
                    logic [31:0] wd []; logic [3:0] ws [];
                    wd = new[1]; ws = new[1];
                    wd[0] = 32'hD0D0_0000 | (k << 8) | w; ws[0] = 4'hF;
                    do_item(make_write(4'hC, init_addr, 2'b01, 8'h00, wd, ws));
                end

                // WRAP write starting from top_addr
                wd_wrap = new[N_BEATS_W]; ws_wrap = new[N_BEATS_W];
                for (int b = 0; b < N_BEATS_W; b++) begin
                    wd_wrap[b] = 32'hCAFE_0000 | (k << 8) | b;
                    ws_wrap[b] = 4'hF;
                end
                do_item(make_write(4'hC, top_addr, 2'b10, 8'(L), wd_wrap, ws_wrap));
                // WRAP read-back
                do_item(make_read(4'hC, top_addr, 2'b10, 8'(L)));
                // INCR cross-check: single reads per word
                for (int w = 0; w < N_BEATS_W; w++) begin
                    do_item(make_read(4'hC, wrap_base_addr + 32'(w * axi_sw), 2'b01, 8'h00));
                end

                word_accum += N_BEATS_W + N_BEATS_W;
            end
        endtask
    endclass : seq_wrap_boundary_start

    // =========================================================================
    // SEQ 27: max_outstanding — saturate AW/AR FIFOs to MAX_OUTSTANDING (16)
    //
    // Strategy (write side):
    //   Issue 17 TXN_AW-only items.  The first is immediately popped by the
    //   idle write FSM; the remaining 16 fill aw_fifo[] to MAX_OUTSTANDING,
    //   momentarily driving awready=0.  Then drain with 17 TXN_W_B items.
    //
    // Strategy (read side):
    //   Same: 17 TXN_AR-only items, then drain with 17 TXN_R items.
    //   At 1 GHz aclk (uvm-max-outstanding-test), the DDR4 pipeline spans
    //   ~28 aclk cycles so ar_count reaches MAX_OUTSTANDING before the first
    //   read completes, exercising the arready=0 path.
    // =========================================================================
    class seq_max_outstanding extends ddr4_axi4_base_seq;
        `uvm_object_utils(seq_max_outstanding)
        function new(string name = "seq_max_outstanding"); super.new(name); endfunction

        task body();
            localparam int MAX_OST  = 16;            // matches DUT MAX_OUTSTANDING
            localparam int N_FLOOD  = MAX_OST + 1;   // 17: anchor + 16 real
            localparam int OST_BASE = 19000;
            `uvm_info(get_name(), "=== SEQ 27: max_outstanding (AW/AR FIFO flood to MAX_OUTSTANDING) ===", UVM_LOW)

            // ── Phase A: flood AW FIFO ────────────────────────────────────────
            `uvm_info(get_name(), "  Phase A: flooding AW channel ...", UVM_LOW)
            for (int i = 0; i < N_FLOOD; i++) begin
                logic [31:0] addr = base_addr + 32'((OST_BASE + i) * axi_sw);
                logic [31:0] wd[]; logic [3:0] ws[];
                ddr4_axi4_seq_item aw_it;
                wd = new[1]; ws = new[1]; wd[0] = 32'hA7A7_0000 | i; ws[0] = 4'hF;
                aw_it = make_write(4'(i % 16), addr, 2'b01, 8'h00, wd, ws);
                aw_it.txn_phase = TXN_AW;
                do_item(aw_it);
            end

            // ── Phase B: drain W+B for all N_FLOOD AWs ────────────────────────
            `uvm_info(get_name(), "  Phase B: draining W+B ...", UVM_LOW)
            for (int i = 0; i < N_FLOOD; i++) begin
                logic [31:0] addr = base_addr + 32'((OST_BASE + i) * axi_sw);
                logic [31:0] wd[]; logic [3:0] ws[];
                ddr4_axi4_seq_item wb_it;
                wd = new[1]; ws = new[1]; wd[0] = 32'hA7A7_0000 | i; ws[0] = 4'hF;
                wb_it = make_write(4'(i % 16), addr, 2'b01, 8'h00, wd, ws);
                wb_it.txn_phase = TXN_W_B;
                do_item(wb_it);
            end

            // ── Phase C: flood AR FIFO ────────────────────────────────────────
            `uvm_info(get_name(), "  Phase C: flooding AR channel ...", UVM_LOW)
            for (int i = 0; i < N_FLOOD; i++) begin
                logic [31:0] addr = base_addr + 32'((OST_BASE + i) * axi_sw);
                ddr4_axi4_seq_item ar_it;
                ar_it = make_read(4'(i % 16), addr, 2'b01, 8'h00);
                ar_it.txn_phase = TXN_AR;
                do_item(ar_it);
            end

            // ── Phase D: drain R data for all N_FLOOD ARs ────────────────────
            `uvm_info(get_name(), "  Phase D: draining R data ...", UVM_LOW)
            for (int i = 0; i < N_FLOOD; i++) begin
                logic [31:0] addr = base_addr + 32'((OST_BASE + i) * axi_sw);
                ddr4_axi4_seq_item r_it;
                r_it = make_read(4'(i % 16), addr, 2'b01, 8'h00);
                r_it.txn_phase = TXN_R;
                do_item(r_it);
            end
        endtask
    endclass : seq_max_outstanding

    // =========================================================================
    // Full regression sequence — runs all 27 in BFM order
    // =========================================================================
    class ddr4_axi4_full_seq extends ddr4_axi4_base_seq;
        `uvm_object_utils(ddr4_axi4_full_seq)
        function new(string name = "ddr4_axi4_full_seq"); super.new(name); endfunction

        task body();
            seq_single_rw                   s1  = seq_single_rw::type_id::create("s1");
            seq_burst_incr                  s2  = seq_burst_incr::type_id::create("s2");
            seq_burst_wrap                  s3  = seq_burst_wrap::type_id::create("s3");
            seq_burst_fixed                 s4  = seq_burst_fixed::type_id::create("s4");
            seq_strobe                      s5  = seq_strobe::type_id::create("s5");
            seq_backpressure                s6  = seq_backpressure::type_id::create("s6");
            seq_page_miss                   s7  = seq_page_miss::type_id::create("s7");
            seq_oob_access                  s8  = seq_oob_access::type_id::create("s8");
            seq_wtr_stress                  s9  = seq_wtr_stress::type_id::create("s9");
            seq_dma_concurrent              s10 = seq_dma_concurrent::type_id::create("s10");
            seq_dma_outstanding             s11 = seq_dma_outstanding::type_id::create("s11");
            seq_true_outstanding            s12 = seq_true_outstanding::type_id::create("s12");
            seq_mixed_burst_outstanding     s13 = seq_mixed_burst_outstanding::type_id::create("s13");
            seq_outstanding_mixed_rw        s14 = seq_outstanding_mixed_rw::type_id::create("s14");
            seq_burst_outstanding_drain     s15 = seq_burst_outstanding_drain::type_id::create("s15");
            seq_burst_per_beat_strobe       s16 = seq_burst_per_beat_strobe::type_id::create("s16");
            seq_burst_bp_per_beat           s17 = seq_burst_bp_per_beat::type_id::create("s17");
            seq_narrow_size                 s18 = seq_narrow_size::type_id::create("s18");
            seq_burst_row_cross             s19 = seq_burst_row_cross::type_id::create("s19");
            seq_id_stress                   s20 = seq_id_stress::type_id::create("s20");
            seq_partial_write_page_miss_rd  s21 = seq_partial_write_page_miss_rd::type_id::create("s21");
            seq_refresh_mid_burst           s22 = seq_refresh_mid_burst::type_id::create("s22");
            seq_wstrb_zero_beat             s23 = seq_wstrb_zero_beat::type_id::create("s23");
            seq_max_burst                   s24 = seq_max_burst::type_id::create("s24");
            seq_bready_bp                   s25 = seq_bready_bp::type_id::create("s25");
            seq_wrap_boundary_start         s26 = seq_wrap_boundary_start::type_id::create("s26");
            seq_max_outstanding             s27 = seq_max_outstanding::type_id::create("s27");

            s1.start(m_sequencer);   s2.start(m_sequencer);
            s3.start(m_sequencer);   s4.start(m_sequencer);
            s5.start(m_sequencer);   s6.start(m_sequencer);
            s7.start(m_sequencer);   s8.start(m_sequencer);
            s9.start(m_sequencer);   s10.start(m_sequencer);
            s11.start(m_sequencer);  s12.start(m_sequencer);
            s13.start(m_sequencer);  s14.start(m_sequencer);
            s15.start(m_sequencer);  s16.start(m_sequencer);
            s17.start(m_sequencer);  s18.start(m_sequencer);
            s19.start(m_sequencer);  s20.start(m_sequencer);
            s21.start(m_sequencer);  s22.start(m_sequencer);
            s23.start(m_sequencer);  s24.start(m_sequencer);
            s25.start(m_sequencer);  s26.start(m_sequencer);
            s27.start(m_sequencer);
        endtask
    endclass : ddr4_axi4_full_seq

endpackage : ddr4_axi4_seqs_pkg

`endif // DDR4_AXI4_SEQS_PKG_SV
