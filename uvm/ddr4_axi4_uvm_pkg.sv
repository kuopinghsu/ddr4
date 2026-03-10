// ============================================================================
// File: uvm/ddr4_axi4_uvm_pkg.sv
// Project: KV32 RISC-V Processor
// Description: UVM 2017-1.0 package for the DDR4 AXI4 slave testbench
//
// Hierarchy (bottom-up):
//   ddr4_axi4_seq_item        — sequence item (transaction)
//   ddr4_axi4_driver          — drives AXI4 interface
//   ddr4_axi4_monitor         — samples completed transactions
//   ddr4_axi4_scoreboard      — byte-accurate shadow memory checker
//   ddr4_axi4_coverage        — functional covergroups
//   ddr4_axi4_agent           — driver + monitor + sequencer
//   ddr4_axi4_env             — agent + scoreboard + coverage
//   ddr4_axi4_base_test       — base test (env bring-up, reset, drain)
//
// Sequences (defined in ddr4_axi4_seqs_pkg.sv):
//   seq_single_rw, seq_burst_incr, seq_burst_wrap, seq_burst_fixed,
//   seq_strobe, seq_backpressure, seq_page_miss, seq_oob_access,
//   seq_wtr_stress, seq_dma_concurrent, seq_dma_outstanding,
//   seq_true_outstanding, seq_mixed_burst_outstanding,
//   seq_outstanding_mixed_rw, seq_burst_outstanding_drain,
//   seq_burst_per_beat_strobe, seq_burst_bp_per_beat, seq_narrow_size,
//   seq_burst_row_cross, seq_id_stress, seq_partial_write_page_miss_rd,
//   seq_refresh_mid_burst, seq_wstrb_zero_beat, seq_max_burst,
//   seq_bready_bp, seq_wrap_boundary_start
// ============================================================================

/* verilator lint_off UNUSEDSIGNAL  */
/* verilator lint_off WIDTHEXPAND   */
/* verilator lint_off WIDTHTRUNC    */
/* verilator lint_off INITIALDLY    */
/* verilator lint_off PROCASSINIT   */
/* verilator lint_off BLKANDNBLK    */
/* verilator lint_off MODDUP        */

`ifndef DDR4_AXI4_UVM_PKG_SV
`define DDR4_AXI4_UVM_PKG_SV

`include "uvm_macros.svh"

package ddr4_axi4_uvm_pkg;

    import uvm_pkg::*;
    import ddr4_axi4_pkg::*;

    // =========================================================================
    // Parameters visible inside the package
    // =========================================================================
    // These match the top-level TB parameters; the agent reads them via
    // uvm_config_db or via the virtual interface handle.
    localparam int PKG_AXI_DW  = 32;   // overridden at elaboration
    localparam int PKG_AXI_IDW = 4;
    localparam int PKG_AXI_AW  = 32;

    // Split-phase transaction modes (txn_phase in ddr4_axi4_seq_item)
    localparam int TXN_FULL = 0;  // complete transaction (default)
    localparam int TXN_AW   = 1;  // write: AW channel only
    localparam int TXN_W_B  = 2;  // write: W beats + B (AW already issued)
    localparam int TXN_B    = 3;  // write: B response only
    localparam int TXN_AR   = 4;  // read: AR channel only
    localparam int TXN_R    = 5;  // read: R data only (AR already issued)

    // =========================================================================
    // Sequence item
    // =========================================================================
    class ddr4_axi4_seq_item extends uvm_sequence_item;
        `uvm_object_utils_begin(ddr4_axi4_seq_item)
            `uvm_field_int(id,         UVM_ALL_ON)
            `uvm_field_int(addr,       UVM_ALL_ON)
            `uvm_field_int(len,        UVM_ALL_ON)
            `uvm_field_int(size,       UVM_ALL_ON)
            `uvm_field_int(burst,      UVM_ALL_ON)
            `uvm_field_int(is_read,    UVM_ALL_ON)
            `uvm_field_int(txn_phase,  UVM_ALL_ON)
        `uvm_object_utils_end

        // AXI control
        rand logic [3:0]  id;
        rand logic [31:0] addr;
        rand logic [7:0]  len;     // AXI len (beats - 1)
        rand logic [2:0]  size;    // AXI size
        rand logic [1:0]  burst;   // FIXED/INCR/WRAP
        rand logic        is_read;

        // Write data & strobes (max 256 beats)
        rand logic [31:0] wdata [0:255];
        rand logic [3:0]  wstrb [0:255];

        // Back-pressure control
        rand logic  apply_bp;
        rand int unsigned bp_hold;  // bready hold cycles (2–8 for bready_bp test)

        // Narrow transfer override
        rand logic [2:0]  force_size;  // 0=disabled, else override awsize/arsize
        rand logic        use_force_size;

        // Split-phase mode for outstanding-transaction tests (see TXN_* constants)
        int txn_phase = TXN_FULL;

        // Captured response (filled in by driver)
        logic [1:0]  bresp;
        logic [31:0] rdata [0:255];
        logic [1:0]  rresp [0:255];

        // Latency measurement (filled in by monitor)
        longint unsigned start_time_ns;
        longint unsigned end_time_ns;

        function new(string name = "ddr4_axi4_seq_item");
            super.new(name);
        endfunction

        // Constraints
        constraint c_addr_aligned { (addr % (1 << size)) == 0; }
        constraint c_len_incr     { burst == 2'b01 -> len inside {[0:15]}; }
        constraint c_len_wrap     {
            burst == 2'b10 -> len inside {1, 3, 7, 15};
        }
        constraint c_size_default { size == 3'b010; } // 4-byte default
        constraint c_bp_hold_range{ bp_hold inside {[2:8]}; }

        function string convert2string();
            return $sformatf("id=%0h addr=0x%08h len=%0d burst=%0b is_read=%0b",
                             id, addr, len, burst, is_read);
        endfunction
    endclass : ddr4_axi4_seq_item

    // =========================================================================
    // Scoreboard — byte-accurate shadow memory
    // =========================================================================
    class ddr4_axi4_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(ddr4_axi4_scoreboard)

        // analysis FIFO from monitor
        uvm_analysis_imp #(ddr4_axi4_seq_item, ddr4_axi4_scoreboard) analysis_export;

        // Parameters (set via config_db before build_phase)
        int sim_depth    = 32768;
        int axi_sw       = 4;
        int axi_dw       = 32;
        logic [31:0] base_addr = 32'h8000_0000;

        // Shadow memory
        logic [7:0]  shadow     [0:65535][0:7];  // over-provisioned; indexed by word
        logic        byte_valid [0:65535][0:7];

        // Stats
        int txn_pass = 0;
        int txn_fail = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            analysis_export = new("analysis_export", this);
            void'(uvm_config_db#(int)::get(this, "", "sim_depth", sim_depth));
            void'(uvm_config_db#(int)::get(this, "", "axi_sw",    axi_sw));
            void'(uvm_config_db#(int)::get(this, "", "axi_dw",    axi_dw));
            void'(uvm_config_db#(logic [31:0])::get(this, "", "base_addr", base_addr));
            // Initialise valid flags
            foreach (byte_valid[w, b]) byte_valid[w][b] = 1'b0;
        endfunction

        // Compute DUT word index for burst beat b
        function automatic int beat_mem_index(
            logic [31:0] start_addr,
            logic [1:0]  burst,
            int          b,
            int          len
        );
            int beats     = len + 1;
            int wrap_bytes= beats * axi_sw;
            int wrap_base = ((int'(start_addr - base_addr)) / wrap_bytes) * wrap_bytes;
            int offset;
            case (burst)
                2'b00: offset = int'(start_addr - base_addr);
                2'b10: begin
                    int raw = (int'(start_addr - base_addr) - wrap_base + b * axi_sw) % wrap_bytes;
                    offset  = wrap_base + raw;
                end
                default: offset = int'(start_addr - base_addr) + b * axi_sw;
            endcase
            return offset / axi_sw;
        endfunction

        // Called by monitor for each completed transaction
        function void write(ddr4_axi4_seq_item item);
            if (!item.is_read) begin
                // Update shadow memory
                for (int b = 0; b <= int'(item.len); b++) begin
                    int idx = beat_mem_index(item.addr, item.burst, b, int'(item.len));
                    if (idx >= 0 && idx < sim_depth) begin
                        for (int by = 0; by < axi_sw; by++) begin
                            if (item.wstrb[b][by]) begin
                                shadow[idx][by]     = item.wdata[b][by*8 +: 8];
                                byte_valid[idx][by] = 1'b1;
                            end
                        end
                    end
                end
            end else begin
                // Check read data
                logic ok;
                ok = 1'b1;
                for (int b = 0; b <= int'(item.len); b++) begin
                    int idx = beat_mem_index(item.addr, item.burst, b, int'(item.len));
                    if (idx >= 0 && idx < sim_depth) begin
                        logic [31:0] expected;
                        expected = '0;
                        for (int by = 0; by < axi_sw; by++) begin
                            if (byte_valid[idx][by])
                                expected[by*8 +: 8] = shadow[idx][by];
                            else
                                expected[by*8 +: 8] = item.rdata[b][by*8 +: 8];
                        end
                        if (item.rdata[b] !== expected) begin
                            `uvm_error("SCB",
                                $sformatf("[MISMATCH] addr=0x%08h beat%0d got=0x%08h want=0x%08h",
                                    base_addr + 32'(idx * axi_sw), b, item.rdata[b], expected))
                            ok = 1'b0;
                        end
                    end
                end
                if (ok) txn_pass++;
                else    txn_fail++;
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SCB", $sformatf("Scoreboard: PASS=%0d  FAIL=%0d",
                                        txn_pass, txn_fail), UVM_LOW)
            if (txn_fail != 0)
                `uvm_fatal("SCB", $sformatf("%0d transaction(s) FAILED", txn_fail))
        endfunction
    endclass : ddr4_axi4_scoreboard

    // =========================================================================
    // Functional coverage
    // =========================================================================
    class ddr4_axi4_coverage extends uvm_subscriber #(ddr4_axi4_seq_item);
        `uvm_component_utils(ddr4_axi4_coverage)

        // Coverage signals updated before each sample()
        logic [1:0] cg_burst;
        logic [3:0] cg_len_bucket;
        logic [1:0] cg_strb_type;
        logic       cg_bp;
        logic       cg_is_read;

        covergroup axi_txn_cg;
            cp_burst  : coverpoint cg_burst  { bins fixed = {2'b00}; bins incr = {2'b01}; bins wrap = {2'b10}; }
            cp_len    : coverpoint cg_len_bucket;
            cp_strb   : coverpoint cg_strb_type;
            cp_bp     : coverpoint cg_bp;
            cp_dir    : coverpoint cg_is_read;
            cp_bxdir  : cross cp_burst, cp_dir;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            axi_txn_cg = new();
        endfunction

        function void write(ddr4_axi4_seq_item t);
            cg_burst      = t.burst;
            cg_len_bucket = (t.len == 0)    ? 4'd0 :
                            (t.len <= 3)    ? 4'd1 :
                            (t.len <= 7)    ? 4'd2 : 4'd3;
            cg_strb_type  = (t.wstrb[0] == '1) ? 2'd0 : 2'd1;
            cg_bp         = t.apply_bp;
            cg_is_read    = t.is_read;
            axi_txn_cg.sample();
        endfunction
    endclass : ddr4_axi4_coverage

    // =========================================================================
    // Driver
    // =========================================================================
    typedef virtual ddr4_axi4_if #(.AXI_DW(32), .AXI_IDW(4), .AXI_AW(32)) vif_t;

    class ddr4_axi4_driver extends uvm_driver #(ddr4_axi4_seq_item);
        `uvm_component_utils(ddr4_axi4_driver)

        vif_t vif;

        // Parameters (read from config_db)
        int axi_sw       = 4;
        int axi_sz       = 2;
        int watchdog_cyc = 4000;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(vif_t)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "No virtual interface found in config_db")
            void'(uvm_config_db#(int)::get(this, "", "axi_sw",       axi_sw));
            void'(uvm_config_db#(int)::get(this, "", "watchdog_cyc", watchdog_cyc));
            axi_sz = $clog2(axi_sw);
        endfunction

        task run_phase(uvm_phase phase);
            reset_outputs();
            // TB deasserts aresetn after 20 aclk cycles; wait 30 for margin.
            // Using a fixed repeat avoids unreliable vif port reads in Verilator.
            repeat(30) @(posedge vif.aclk);

            forever begin
                ddr4_axi4_seq_item item;
                seq_item_port.get_next_item(item);
                drive_item(item);
                seq_item_port.item_done();
            end
        endtask

        // ── Internal helpers ──────────────────────────────────────────────────

        task reset_outputs();
            vif.awid    = '0;
            vif.awaddr  = '0;
            vif.awlen   = '0;
            vif.awsize  = 3'(axi_sz);
            vif.awburst = 2'b01;
            vif.awlock  = '0;
            vif.awcache = '0;
            vif.awprot  = '0;
            vif.awqos   = '0;
            vif.awvalid = 1'b0;
            vif.wdata   = '0;
            vif.wstrb   = '0;
            vif.wlast   = 1'b0;
            vif.wvalid  = 1'b0;
            vif.bready  = 1'b0;
            vif.arid    = '0;
            vif.araddr  = '0;
            vif.arlen   = '0;
            vif.arsize  = 3'(axi_sz);
            vif.arburst = 2'b01;
            vif.arlock  = '0;
            vif.arcache = '0;
            vif.arprot  = '0;
            vif.arqos   = '0;
            vif.arvalid = 1'b0;
            vif.rready  = 1'b0;
        endtask

        // Dispatch based on txn_phase (TXN_FULL=complete, TXN_AW/W_B/B/AR/R=split)
        task drive_item(ddr4_axi4_seq_item item);
            case (item.txn_phase)
                TXN_FULL: if (!item.is_read) begin
                              phase_aw(item); phase_w(item); phase_b(item);
                          end else begin
                              phase_ar(item); phase_r(item);
                          end
                TXN_AW:  phase_aw(item);
                TXN_W_B: begin phase_w(item); phase_b(item); end
                TXN_B:   phase_b(item);
                TXN_AR:  phase_ar(item);
                TXN_R:   phase_r(item);
                default: `uvm_warning("DRV", $sformatf("Unknown txn_phase=%0d", item.txn_phase))
            endcase
        endtask

        // ── AW channel phase ──────────────────────────────────────────────────
        task phase_aw(ddr4_axi4_seq_item item);
            int t;
            logic [2:0] eff_size;
            eff_size = item.use_force_size ? item.force_size : 3'(axi_sz);
            t = watchdog_cyc;
            @(posedge vif.aclk);
            while (!vif.awready) begin
                if (t == 0) begin `uvm_warning("DRV", "WD on awready"); break; end
                t--; @(posedge vif.aclk);
            end
            vif.awid    <= item.id;
            vif.awaddr  <= item.addr;
            vif.awlen   <= item.len;
            vif.awsize  <= eff_size;
            vif.awburst <= item.burst;
            vif.awlock  <= 1'b0;
            vif.awcache <= 4'b0;
            vif.awprot  <= 3'b0;
            vif.awqos   <= 4'b0;
            vif.awvalid <= 1'b1;
            @(posedge vif.aclk);
            vif.awvalid <= 1'b0;
        endtask

        // ── W beats phase ─────────────────────────────────────────────────────
        task phase_w(ddr4_axi4_seq_item item);
            int t;
            for (int b = 0; b <= int'(item.len); b++) begin
                t = watchdog_cyc;
                @(posedge vif.aclk);
                while (!vif.wready) begin
                    if (t == 0) begin `uvm_warning("DRV", $sformatf("WD wready b%0d", b)); break; end
                    t--; @(posedge vif.aclk);
                end
                vif.wdata  <= item.wdata[b];
                vif.wstrb  <= item.wstrb[b];
                vif.wlast  <= (b == int'(item.len));
                vif.wvalid <= 1'b1;
                @(posedge vif.aclk);
                vif.wvalid <= 1'b0;
                vif.wlast  <= 1'b0;
            end
        endtask

        // ── B response phase ──────────────────────────────────────────────────
        task phase_b(ddr4_axi4_seq_item item);
            int t;
            if (item.apply_bp)
                repeat (int'(item.bp_hold)) @(posedge vif.aclk);
            t = watchdog_cyc;
            @(posedge vif.aclk);
            while (!vif.bvalid) begin
                if (t == 0) begin `uvm_warning("DRV", "WD on bvalid"); break; end
                t--; @(posedge vif.aclk);
            end
            item.bresp =  vif.bresp;
            vif.bready <= 1'b1;
            @(posedge vif.aclk);
            vif.bready <= 1'b0;
            @(posedge vif.aclk);
        endtask

        // ── AR channel phase ──────────────────────────────────────────────────
        task phase_ar(ddr4_axi4_seq_item item);
            int t;
            logic [2:0] eff_size;
            eff_size = item.use_force_size ? item.force_size : 3'(axi_sz);
            t = watchdog_cyc;
            @(posedge vif.aclk);
            while (!vif.arready) begin
                if (t == 0) begin `uvm_warning("DRV", "WD on arready"); break; end
                t--; @(posedge vif.aclk);
            end
            vif.arid    <= item.id;
            vif.araddr  <= item.addr;
            vif.arlen   <= item.len;
            vif.arsize  <= eff_size;
            vif.arburst <= item.burst;
            vif.arlock  <= 1'b0;
            vif.arcache <= 4'b0;
            vif.arprot  <= 3'b0;
            vif.arqos   <= 4'b0;
            vif.arvalid <= 1'b1;
            @(posedge vif.aclk);
            vif.arvalid <= 1'b0;
        endtask

        // ── R data phase ──────────────────────────────────────────────────────
        task phase_r(ddr4_axi4_seq_item item);
            int t;
            if (item.apply_bp) @(posedge vif.aclk);
            for (int b = 0; b <= int'(item.len); b++) begin
                t = watchdog_cyc;
                @(posedge vif.aclk);
                while (!vif.rvalid) begin
                    if (t == 0) begin `uvm_warning("DRV", $sformatf("WD rvalid b%0d", b)); break; end
                    t--; @(posedge vif.aclk);
                end
                item.rdata[b] = vif.rdata;
                item.rresp[b] = vif.rresp;
                vif.rready <= 1'b1;
                @(posedge vif.aclk);
                vif.rready <= 1'b0;
            end
            @(posedge vif.aclk);
        endtask

    endclass : ddr4_axi4_driver

    // =========================================================================
    // Monitor — observes completed transactions and broadcasts to subscribers
    // =========================================================================
    class ddr4_axi4_monitor extends uvm_monitor;
        `uvm_component_utils(ddr4_axi4_monitor)

        vif_t vif;
        uvm_analysis_port #(ddr4_axi4_seq_item) ap;

        int axi_sw = 4;

        // Pipelines for split-phase AXI4 tracking (supports pipelined/outstanding txns)
        ddr4_axi4_seq_item aw_pipeline[$];
        ddr4_axi4_seq_item ar_pipeline[$];
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db#(vif_t)::get(this, "", "vif", vif))
                `uvm_fatal("MON", "No virtual interface found in config_db")
            void'(uvm_config_db#(int)::get(this, "", "axi_sw", axi_sw));
        endfunction

        task run_phase(uvm_phase phase);
            fork
                monitor_aw_channel();
                monitor_wb_channel();
                monitor_ar_channel();
                monitor_r_channel();
            join_none
        endtask

        // AW channel: capture AW handshakes and queue for W+B collection
        task monitor_aw_channel();
            forever begin
                ddr4_axi4_seq_item item;
                do @(posedge vif.aclk); while (!(vif.awvalid && vif.awready));
                item              = ddr4_axi4_seq_item::type_id::create("mon_aw");
                item.is_read      = 1'b0;
                item.id           = vif.awid;
                item.addr         = vif.awaddr;
                item.len          = vif.awlen;
                item.size         = vif.awsize;
                item.burst        = vif.awburst;
                item.start_time_ns= $realtime;
                aw_pipeline.push_back(item);
            end
        endtask

        // W+B channel: for each queued AW collect W beats + B, then report
        task monitor_wb_channel();
            forever begin
                ddr4_axi4_seq_item item;
                while (aw_pipeline.size() == 0) @(posedge vif.aclk);
                item = aw_pipeline.pop_front();
                for (int b = 0; b <= int'(item.len); b++) begin
                    do @(posedge vif.aclk); while (!(vif.wvalid && vif.wready));
                    item.wdata[b] = vif.wdata;
                    item.wstrb[b] = vif.wstrb;
                end
                do @(posedge vif.aclk); while (!(vif.bvalid && vif.bready));
                item.bresp       = vif.bresp;
                item.end_time_ns = $realtime;
                ap.write(item);
            end
        endtask

        // AR channel: capture AR handshakes and queue for R collection
        task monitor_ar_channel();
            forever begin
                ddr4_axi4_seq_item item;
                do @(posedge vif.aclk); while (!(vif.arvalid && vif.arready));
                item              = ddr4_axi4_seq_item::type_id::create("mon_ar");
                item.is_read      = 1'b1;
                item.id           = vif.arid;
                item.addr         = vif.araddr;
                item.len          = vif.arlen;
                item.size         = vif.arsize;
                item.burst        = vif.arburst;
                item.start_time_ns= $realtime;
                ar_pipeline.push_back(item);
            end
        endtask

        // R channel: for each queued AR collect R beats, then report
        task monitor_r_channel();
            forever begin
                ddr4_axi4_seq_item item;
                while (ar_pipeline.size() == 0) @(posedge vif.aclk);
                item = ar_pipeline.pop_front();
                for (int b = 0; b <= int'(item.len); b++) begin
                    do @(posedge vif.aclk); while (!(vif.rvalid && vif.rready));
                    item.rdata[b] = vif.rdata;
                    item.rresp[b] = vif.rresp;
                end
                item.end_time_ns = $realtime;
                ap.write(item);
            end
        endtask

    endclass : ddr4_axi4_monitor

    // =========================================================================
    // Agent
    // =========================================================================
    class ddr4_axi4_agent extends uvm_agent;
        `uvm_component_utils(ddr4_axi4_agent)

        uvm_sequencer #(ddr4_axi4_seq_item) sequencer;
        ddr4_axi4_driver                    driver;
        ddr4_axi4_monitor                   monitor;

        uvm_analysis_port #(ddr4_axi4_seq_item) ap;  // promoted from monitor

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sequencer = uvm_sequencer #(ddr4_axi4_seq_item)::type_id::create("sequencer", this);
            driver    = ddr4_axi4_driver::type_id::create("driver",    this);
            monitor   = ddr4_axi4_monitor::type_id::create("monitor",  this);
            ap        = new("ap", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
            monitor.ap.connect(ap);
        endfunction

    endclass : ddr4_axi4_agent

    // =========================================================================
    // Environment
    // =========================================================================
    class ddr4_axi4_env extends uvm_env;
        `uvm_component_utils(ddr4_axi4_env)

        ddr4_axi4_agent       agent;
        ddr4_axi4_scoreboard  scoreboard;
        ddr4_axi4_coverage    coverage;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent      = ddr4_axi4_agent::type_id::create("agent",      this);
            scoreboard = ddr4_axi4_scoreboard::type_id::create("scoreboard", this);
            coverage   = ddr4_axi4_coverage::type_id::create("coverage", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.ap.connect(scoreboard.analysis_export);
            agent.ap.connect(coverage.analysis_export);
        endfunction

    endclass : ddr4_axi4_env

    // =========================================================================
    // Base test
    // =========================================================================
    class ddr4_axi4_base_test extends uvm_test;
        `uvm_component_utils(ddr4_axi4_base_test)

        ddr4_axi4_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = ddr4_axi4_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            // Subclasses override this to run specific sequences
            phase.raise_objection(this);
            run_sequences(phase);
            phase.drop_objection(this);
        endtask

        virtual task run_sequences(uvm_phase phase);
            // Base: no sequences — override in derived tests
        endtask

    endclass : ddr4_axi4_base_test

endpackage : ddr4_axi4_uvm_pkg

`endif // DDR4_AXI4_UVM_PKG_SV
