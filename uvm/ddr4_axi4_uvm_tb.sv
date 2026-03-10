// ============================================================================
// File: uvm/ddr4_axi4_uvm_tb.sv
// Project: KV32 RISC-V Processor
// Description: Top-level UVM testbench for ddr4_axi4_slave.sv
//
// Hierarchy:
//   ddr4_axi4_uvm_tb  (this module)
//     ├─ ddr4_axi4_if    (AXI4 virtual interface)
//     ├─ ddr4_axi4_slave (DUT)
//     └─ run_test()      (UVM entry point)
//
// Parameters (override via +define+ or simulator -g/-G flags):
//   DDR4_SPEED       — DDR4 speed grade (1600/1866/2133/2400/2666/2933/3200)
//   AXI_DW           — AXI data width in bits (32 or 64)
//   ENABLE_TIMING    — 1=enable DDR4 timing model, 0=disable
//   RANDOM_DELAY_EN  — 1=inject random ready delays on slave
//   MAX_RANDOM_DELAY — maximum random delay cycles
//   SIM_DEPTH        — simulated memory depth in AXI words
//   VERBOSE_MODE     — 1=slave verbose logging
//   MEMORY_INIT_FILE — optional memory initialisation hex file
//   CLK_PERIOD_NS    — AXI clock period in nanoseconds (1/2/10/20)
//
// UVM test selection: +UVM_TESTNAME=<test_name>
//   ddr4_axi4_full_test     (default – all 26 sequences)
//   ddr4_axi4_smoke_test
//   ddr4_axi4_timing_test
//   ddr4_axi4_dma_test
//   ddr4_axi4_coverage_test
// ============================================================================

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off WIDTHEXPAND  */
/* verilator lint_off WIDTHTRUNC   */
/* verilator lint_off TIMESCALEMOD */
/* verilator lint_off INITIALDLY   */

`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "ddr4_axi4_pkg.sv"
`include "ddr4_axi4_if.sv"
`include "ddr4_axi4_uvm_pkg.sv"
`include "ddr4_axi4_seqs_pkg.sv"
`include "ddr4_axi4_tests.sv"

// Pull in the DUT itself.  Adjust path if compiling from a different directory.
`ifndef DDR4_AXI4_SLAVE_INCLUDED
`include "../ddr4_axi4_slave.sv"
`define DDR4_AXI4_SLAVE_INCLUDED
`endif

module ddr4_axi4_uvm_tb;

    import uvm_pkg::*;
    import ddr4_axi4_pkg::*;
    import ddr4_axi4_uvm_pkg::*;
    import ddr4_axi4_tests_pkg::*;

    // =========================================================================
    // Parameters (mirrors ddr4_axi4_bfm_tb.sv)
    // =========================================================================
    parameter int  DDR4_SPEED       = 2400;
    parameter int  AXI_DW           = 32;
    parameter int  ENABLE_TIMING    = 1;
    parameter int  RANDOM_DELAY_EN  = 0;
    parameter int  MAX_RANDOM_DELAY = 8;
    parameter int  SIM_DEPTH        = 32768;
    parameter int  VERBOSE_MODE     = 0;
    parameter      MEMORY_INIT_FILE = "";
    parameter int  CLK_PERIOD_NS    = 10;    // 100 MHz AXI clock default

    localparam int  AXI_SW         = AXI_DW / 8;
    localparam int  AXI_IDW        = 4;
    localparam int  AXI_AW         = 32;
    localparam real MCLK_PERIOD_NS = 1000.0 * 2.0 / DDR4_SPEED;
    localparam [31:0] BASE         = 32'h8000_0000;

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic aclk    = 1'b0;
    logic aresetn = 1'b0;
    logic mclk    = 1'b0;
    logic mresetn = 1'b0;

    always #(CLK_PERIOD_NS / 2.0)   aclk  = ~aclk;
    always #(MCLK_PERIOD_NS / 2.0)  mclk  = ~mclk;

    // De-assert reset after 20 AXI clocks (same as BFM TB)
    initial begin
        aresetn = 1'b0;
        mresetn = 1'b0;
        repeat (20) @(posedge aclk);
        @(posedge mclk);
        mresetn = 1'b1;
        @(posedge aclk);
        aresetn = 1'b1;
    end

    // =========================================================================
    // AXI4 Interface
    // =========================================================================
    ddr4_axi4_if #(
        .AXI_DW  (AXI_DW),
        .AXI_IDW (AXI_IDW),
        .AXI_AW  (AXI_AW)
    ) axi_if (
        .aclk    (aclk),
        .aresetn (aresetn)
    );

    // =========================================================================
    // DUT
    // =========================================================================
    ddr4_axi4_slave #(
        .AXI_ID_WIDTH        (AXI_IDW),
        .AXI_ADDR_WIDTH      (AXI_AW),
        .AXI_DATA_WIDTH      (AXI_DW),
        .DDR4_DENSITY_GB     (1),
        .DDR4_DQ_WIDTH       (64),
        .DDR4_BANKS          (16),
        .DDR4_ROWS           (65536),
        .DDR4_COLS           (1024),
        .DDR4_SPEED_GRADE    (DDR4_SPEED),
        .AXI_CLK_PERIOD_NS   (CLK_PERIOD_NS),
        .SIM_MEM_DEPTH       (SIM_DEPTH),
        .ENABLE_TIMING_MODEL (ENABLE_TIMING),
        .ENABLE_TIMING_CHECK (1),
        .RANDOM_DELAY_EN     (RANDOM_DELAY_EN),
        .MAX_RANDOM_DELAY    (MAX_RANDOM_DELAY),
        .VERBOSE_MODE        (VERBOSE_MODE),
        .MEMORY_INIT_FILE    (MEMORY_INIT_FILE),
        .BASE_ADDR           (BASE)
    ) dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .mclk           (mclk),
        .mresetn        (mresetn),
        // Write address channel
        .s_axi_awid     (axi_if.awid),
        .s_axi_awaddr   (axi_if.awaddr),
        .s_axi_awlen    (axi_if.awlen),
        .s_axi_awsize   (axi_if.awsize),
        .s_axi_awburst  (axi_if.awburst),
        .s_axi_awlock   (axi_if.awlock),
        .s_axi_awcache  (axi_if.awcache),
        .s_axi_awprot   (axi_if.awprot),
        .s_axi_awqos    (axi_if.awqos),
        .s_axi_awvalid  (axi_if.awvalid),
        .s_axi_awready  (axi_if.awready),
        // Write data channel
        .s_axi_wdata    (axi_if.wdata),
        .s_axi_wstrb    (axi_if.wstrb),
        .s_axi_wlast    (axi_if.wlast),
        .s_axi_wvalid   (axi_if.wvalid),
        .s_axi_wready   (axi_if.wready),
        // Write response channel
        .s_axi_bid      (axi_if.bid),
        .s_axi_bresp    (axi_if.bresp),
        .s_axi_bvalid   (axi_if.bvalid),
        .s_axi_bready   (axi_if.bready),
        // Read address channel
        .s_axi_arid     (axi_if.arid),
        .s_axi_araddr   (axi_if.araddr),
        .s_axi_arlen    (axi_if.arlen),
        .s_axi_arsize   (axi_if.arsize),
        .s_axi_arburst  (axi_if.arburst),
        .s_axi_arlock   (axi_if.arlock),
        .s_axi_arcache  (axi_if.arcache),
        .s_axi_arprot   (axi_if.arprot),
        .s_axi_arqos    (axi_if.arqos),
        .s_axi_arvalid  (axi_if.arvalid),
        .s_axi_arready  (axi_if.arready),
        // Read data channel
        .s_axi_rid      (axi_if.rid),
        .s_axi_rdata    (axi_if.rdata),
        .s_axi_rresp    (axi_if.rresp),
        .s_axi_rlast    (axi_if.rlast),
        .s_axi_rvalid   (axi_if.rvalid),
        .s_axi_rready   (axi_if.rready)
    );

    // =========================================================================
    // UVM Startup
    // =========================================================================
    initial begin
        // Push AXI data width & base address into config_db so components
        // can size their shadow memory correctly.
        uvm_config_db#(int)::set(null, "uvm_test_top*", "axi_dw",    AXI_DW);
        uvm_config_db#(int)::set(null, "uvm_test_top*", "axi_sw",    AXI_SW);
        uvm_config_db#(int)::set(null, "uvm_test_top*", "sim_depth", SIM_DEPTH);
        uvm_config_db#(logic [31:0])::set(null, "uvm_test_top*", "base_addr", BASE);

        // Push the virtual interface handle.  The agent retrieves it in
        // build_phase via uvm_config_db#(virtual ddr4_axi4_if)::get().
        uvm_config_db#(virtual ddr4_axi4_if #(AXI_DW, AXI_IDW, AXI_AW))
            ::set(null, "uvm_test_top*", "vif", axi_if);

        // Launch the test specified by +UVM_TESTNAME (default: ddr4_axi4_full_test)
        run_test("ddr4_axi4_full_test");
    end

    // =========================================================================
    // Global timeout / watchdog (mirrors BFM WATCHDOG_CYCLES = 4000 aclk)
    // The UVM objection mechanism is the primary termination path; this
    // timeout is a safety net for hung simulations.
    // =========================================================================
    initial begin
        // Allow generous wall-time; UVM drain-time handles the normal exit.
        // 26 sequences × ~4 ms each ≈ 100 ms; 1000 ms gives 10× margin.
        #(1_000_000_000ns);
        `uvm_fatal("TIMEOUT", "Global simulation timeout reached — hung test?")
    end

    // =========================================================================
    // DUT statistics dump (mirrors check_timing_assertions in BFM TB)
    // Printed after run_phase completes via a report_phase.
    // =========================================================================
    final begin
        $display("------------------------------------------------------------");
        $display(" DUT Statistics Summary");
        $display("------------------------------------------------------------");
        $display("  page_hit_count       = %0d", dut.stats.page_hit_count);
        $display("  page_miss_count      = %0d", dut.stats.page_miss_count);
        $display("  refresh_stall_count  = %0d", dut.stats.refresh_stall_count);
        $display("  address_errors       = %0d", dut.stats.address_errors);
        $display("  max_outstanding_wr   = %0d", dut.stats.max_outstanding_writes);
        $display("  max_outstanding_rd   = %0d", dut.stats.max_outstanding_reads);
        $display("  MAX_OUTSTANDING      = %0d", dut.MAX_OUTSTANDING);
        $display("------------------------------------------------------------");
    end

endmodule : ddr4_axi4_uvm_tb
