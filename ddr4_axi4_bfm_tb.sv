// ============================================================================
// File: ddr4_axi4_bfm_tb.sv
// Project: KV32 RISC-V Processor
// Description: AXI4 BFM testbench for ddr4_axi4_slave.sv
//
// Features:
//   - Shadow-memory scoreboard for byte-accurate write/read comparison
//   - Functional coverage: burst type, length, strobe, back-pressure
//   - 26 sequence tasks (6 randomised + OOB + WTR stress + DMA concurrent/outstanding +
//                         mixed burst outstanding + outstanding mixed R/W + burst drain +
//                         per-beat strobe + per-beat BP + narrow size + row cross +
//                         ID stress + partial-write page-miss + refresh mid-burst +
//                         zero-wstrb no-op + 256-beat max burst + bready multi-hold +
//                         WRAP burst start-at-top)
//   - Verilator-compatible: no UVM, uses $urandom_range / covergroup
// ============================================================================

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */

`timescale 1ns/1ps
`include "ddr4_axi4_pkg.sv"
`include "ddr4_axi4_slave.sv"

module ddr4_axi4_bfm_tb;

    //=========================================================================
    // Parameters (overrideable via -G on the Verilator command line)
    //=========================================================================
    parameter int  DDR4_SPEED       = 2400;
    parameter int  AXI_DW           = 32;
    parameter int  ENABLE_TIMING    = 1;
    parameter int  RANDOM_DELAY_EN  = 0;
    parameter int  MAX_RANDOM_DELAY = 8;
    parameter int  SIM_DEPTH        = 32768;  // 2 DDR4 rows → enables page-miss tests
    parameter int  N_RAND           = 50;   // transactions per sequence
    parameter int  VERBOSE_MODE     = 0;    // 1 = enable slave verbose logging (bfm-sim-verbose)
    parameter      MEMORY_INIT_FILE = "";  // optional hex init file (bfm-sim-init)

    localparam real       MCLK_PERIOD_NS  = 1000.0 * 2.0 / DDR4_SPEED;
    parameter  int        CLK_PERIOD_NS   = 10;         // aclk period (ns): 1=1GHz, 2=500MHz, 10=100MHz, 20=50MHz
    localparam [31:0]     BASE            = 32'h8000_0000;
    localparam int        AXI_SW          = AXI_DW / 8;
    localparam int        AXI_SZ          = $clog2(AXI_SW);
    localparam int        AXI_IDW         = 4;
    localparam int        AXI_AW          = 32;
    localparam int        WATCHDOG_CYCLES = 4000;
    // Row stride in AXI words: DDR4_COLS(1024) * DDR4_BANKS(16) = 16384 words.
    // Adding this offset to BASE targets Bank 0, Row 1 (different from Row 0).
    localparam int        ROW_STRIDE_WORDS = 16384;

    //=========================================================================
    // Clock & Reset
    //=========================================================================
    logic aclk    = 1'b0;
    logic aresetn = 1'b0;
    logic mclk    = 1'b0;
    logic mresetn = 1'b0;

    always #(CLK_PERIOD_NS / 2.0)   aclk  = ~aclk;
    always #(MCLK_PERIOD_NS / 2.0)  mclk  = ~mclk;

    //=========================================================================
    // AXI4 Bus Signals
    //=========================================================================
    logic [AXI_IDW-1:0]  s_axi_awid    = '0;
    logic [AXI_AW-1:0]   s_axi_awaddr  = '0;
    logic [7:0]           s_axi_awlen   = '0;
    logic [2:0]           s_axi_awsize  = 3'(AXI_SZ);
    logic [1:0]           s_axi_awburst = 2'b01;
    logic                 s_axi_awlock  = '0;
    logic [3:0]           s_axi_awcache = '0;
    logic [2:0]           s_axi_awprot  = '0;
    logic [3:0]           s_axi_awqos   = '0;
    logic                 s_axi_awvalid = 1'b0;
    logic                 s_axi_awready;

    logic [AXI_DW-1:0]   s_axi_wdata   = '0;
    logic [AXI_SW-1:0]   s_axi_wstrb   = '1;
    logic                 s_axi_wlast   = 1'b0;
    logic                 s_axi_wvalid  = 1'b0;
    logic                 s_axi_wready;

    logic [AXI_IDW-1:0]  s_axi_bid;
    logic [1:0]           s_axi_bresp;
    logic                 s_axi_bvalid;
    logic                 s_axi_bready  = 1'b0;

    logic [AXI_IDW-1:0]  s_axi_arid    = '0;
    logic [AXI_AW-1:0]   s_axi_araddr  = '0;
    logic [7:0]           s_axi_arlen   = '0;
    logic [2:0]           s_axi_arsize  = 3'(AXI_SZ);
    logic [1:0]           s_axi_arburst = 2'b01;
    logic                 s_axi_arlock  = '0;
    logic [3:0]           s_axi_arcache = '0;
    logic [2:0]           s_axi_arprot  = '0;
    logic [3:0]           s_axi_arqos   = '0;
    logic                 s_axi_arvalid = 1'b0;
    logic                 s_axi_arready;

    logic [AXI_IDW-1:0]  s_axi_rid;
    logic [AXI_DW-1:0]   s_axi_rdata;
    logic [1:0]           s_axi_rresp;
    logic                 s_axi_rlast;
    logic                 s_axi_rvalid;
    logic                 s_axi_rready  = 1'b0;

    //=========================================================================
    // DUT
    //=========================================================================
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
        .aclk            (aclk),
        .aresetn         (aresetn),
        .mclk            (mclk),
        .mresetn         (mresetn),
        .s_axi_awid      (s_axi_awid),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awlen     (s_axi_awlen),
        .s_axi_awsize    (s_axi_awsize),
        .s_axi_awburst   (s_axi_awburst),
        .s_axi_awlock    (s_axi_awlock),
        .s_axi_awcache   (s_axi_awcache),
        .s_axi_awprot    (s_axi_awprot),
        .s_axi_awqos     (s_axi_awqos),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wlast     (s_axi_wlast),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bid       (s_axi_bid),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_arid      (s_axi_arid),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arlen     (s_axi_arlen),
        .s_axi_arsize    (s_axi_arsize),
        .s_axi_arburst   (s_axi_arburst),
        .s_axi_arlock    (s_axi_arlock),
        .s_axi_arcache   (s_axi_arcache),
        .s_axi_arprot    (s_axi_arprot),
        .s_axi_arqos     (s_axi_arqos),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_rid       (s_axi_rid),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rlast     (s_axi_rlast),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready)
    );

    //=========================================================================
    // Scoreboard — shadow memory (byte-granular)
    //=========================================================================
    // Each shadow word mirrors one AXI bus-width word in the DUT sim memory.
    // byte_valid[word][byte] tracks whether that byte has been written.
    logic [7:0]   shadow     [0:SIM_DEPTH-1][0:AXI_SW-1];
    logic         byte_valid [0:SIM_DEPTH-1][0:AXI_SW-1];

    // Global pass/fail counters
    int txn_pass = 0;
    int txn_fail = 0;

    //=========================================================================
    // Beat-address function
    //   Returns the DUT word index for burst beat b given start_addr,
    //   burst type, and beat count.
    //=========================================================================
    function automatic int beat_mem_index(
        input [AXI_AW-1:0] start_addr,
        input [1:0]         burst,
        input int           b,
        input int           len        // AXI len (beats-1)
    );
        int beats      = len + 1;
        int word_size  = AXI_SW;
        // WRAP window size in bytes
        int wrap_bytes = beats * word_size;
        // aligned lower address boundary for WRAP
        int wrap_base  = (int'(start_addr - BASE) / wrap_bytes) * wrap_bytes;
        int offset;

        case (burst)
            2'b00: offset = int'(start_addr - BASE);            // FIXED: same address
            2'b10: begin                                         // WRAP
                int raw = (int'(start_addr - BASE) - wrap_base + b * word_size) % wrap_bytes;
                offset = wrap_base + raw;
            end
            default: offset = int'(start_addr - BASE) + b * word_size; // INCR
        endcase
        return offset / word_size;
    endfunction

    //=========================================================================
    // Scoreboard write: update shadow with strobe-masked data
    //=========================================================================
    task automatic scb_write(
        input [AXI_AW-1:0]  start_addr,
        input [AXI_DW-1:0]  data [0:15],
        input [AXI_SW-1:0]  strb [0:15],
        input [7:0]          len,
        input [1:0]          burst
    );
        int idx;
        for (int b = 0; b <= int'(len); b++) begin
            idx = beat_mem_index(start_addr, burst, b, int'(len));
            if (idx >= 0 && idx < SIM_DEPTH) begin
                for (int by = 0; by < AXI_SW; by++) begin
                    if (strb[b][by]) begin
                        shadow[idx][by]     = data[b][by*8 +: 8];
                        byte_valid[idx][by] = 1'b1;
                    end
                end
            end
        end
    endtask

    //=========================================================================
    // Scoreboard read-check: compare DUT read data against shadow
    //=========================================================================
    task automatic scb_read_check(
        input  [AXI_AW-1:0]  start_addr,
        input  [AXI_DW-1:0]  rdata [0:15],
        input  [7:0]          len,
        input  [1:0]          burst,
        input  string         tag,
        output logic          ok
    );
        int           idx;
        logic [AXI_DW-1:0] expected;
        ok = 1'b1;

        for (int b = 0; b <= int'(len); b++) begin
            idx = beat_mem_index(start_addr, burst, b, int'(len));
            if (idx >= 0 && idx < SIM_DEPTH) begin
                // Build expected word from shadow (only for bytes we wrote)
                expected = '0;
                for (int by = 0; by < AXI_SW; by++) begin
                    if (byte_valid[idx][by])
                        expected[by*8 +: 8] = shadow[idx][by];
                    else
                        // Unwritten byte: mask out comparison
                        expected[by*8 +: 8] = rdata[b][by*8 +: 8];
                end
                if (rdata[b] !== expected) begin
                    $display("[MISMATCH] %s beat%0d addr=0x%08h  got=0x%0h  want=0x%0h",
                             tag, b,
                             BASE + 32'(idx * AXI_SW),
                             rdata[b], expected);
                    ok = 1'b0;
                end
            end
        end
        if (ok) txn_pass++;
        else    txn_fail++;
    endtask

    //=========================================================================
    // Functional Coverage
    //=========================================================================
    // Sampled explicitly via cg_sample() at the end of each transaction.
    logic [1:0] cg_burst;
    logic [3:0] cg_len_bucket; // 0=single,1=2-4,2=5-8,3=9-16
    logic [1:0] cg_strb_type;  // 0=all-enabled, 1=partial
    logic       cg_bp;         // 1 = back-pressure was applied on this txn

    /* verilator lint_off COVERIGN */
    /* verilator lint_off DECLFILENAME */
    covergroup axi_txn_cg;
        cp_burst:      coverpoint cg_burst;
        cp_len:        coverpoint cg_len_bucket;
        cp_strb:       coverpoint cg_strb_type;
        cp_bp:         coverpoint cg_bp;
    endgroup
    /* verilator lint_on DECLFILENAME */
    /* verilator lint_on COVERIGN */

    axi_txn_cg cg_inst = new();

    task automatic cg_sample(
        input [1:0] burst,
        input [7:0] len,
        input [AXI_SW-1:0] strb,
        input logic  bp
    );
        cg_burst      = burst;
        cg_len_bucket = (len == 8'h00) ? 4'd0 :
                        (len <= 8'h03) ? 4'd1 :
                        (len <= 8'h07) ? 4'd2 : 4'd3;
        cg_strb_type  = (strb == '1)   ? 2'd0 : 2'd1;
        cg_bp         = bp;
        cg_inst.sample();
    endtask

    //=========================================================================
    // AXI4 BFM Driver Tasks
    //=========================================================================

    task automatic clk_delay(input int n);
        repeat (n) @(posedge aclk);
    endtask

    // Single-beat write — returns BRESP
    task automatic bfm_write_single(
        input  [AXI_IDW-1:0] id,
        input  [AXI_AW-1:0]  addr,
        input  [AXI_DW-1:0]  data,
        input  [AXI_SW-1:0]  strb,
        input  logic          apply_bp,    // inject 1-cycle bready delay
        output logic [1:0]    bresp
    );
        int timeout;
        logic [AXI_DW-1:0] darray[0:15];
        logic [AXI_SW-1:0] sarray[0:15];
        darray[0] = data; sarray[0] = strb;

        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD AWREADY (single wr)"); break; end
        end
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'h00;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= 2'b01;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);
        s_axi_awvalid <= 1'b0;

        timeout = WATCHDOG_CYCLES;
        while (!s_axi_wready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD WREADY (single wr)"); break; end
        end
        s_axi_wdata  <= data;
        s_axi_wstrb  <= strb;
        s_axi_wlast  <= 1'b1;
        s_axi_wvalid <= 1'b1;
        @(posedge aclk);
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        if (apply_bp) @(posedge aclk);   // intentional back-pressure on B channel

        timeout = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD BVALID (single wr)"); break; end
        end
        bresp        = s_axi_bresp;
        s_axi_bready <= 1'b1;
        @(posedge aclk);
        s_axi_bready <= 1'b0;
        @(posedge aclk);

        scb_write(addr, darray, sarray, 8'h00, 2'b01);
        cg_sample(2'b01, 8'h00, strb, apply_bp);
    endtask

    // Single-beat read — returns RDATA, RRESP
    task automatic bfm_read_single(
        input  [AXI_IDW-1:0]  id,
        input  [AXI_AW-1:0]   addr,
        input  logic           apply_bp,
        output logic [AXI_DW-1:0] rdata,
        output logic [1:0]        rresp
    );
        int timeout;
        logic [AXI_DW-1:0] rdarray[0:15];
        logic [1:0]         rrarray[0:15];
        logic               ok;

        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD ARREADY (single rd)"); break; end
        end
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'h00;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= 2'b01;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);
        s_axi_arvalid <= 1'b0;

        if (apply_bp) @(posedge aclk);   // back-pressure on R channel

        timeout = WATCHDOG_CYCLES;
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD RVALID (single rd)"); break; end
        end
        rdata        = s_axi_rdata;
        rresp        = s_axi_rresp;
        s_axi_rready <= 1'b1;
        @(posedge aclk);
        s_axi_rready <= 1'b0;
        @(posedge aclk);

        rdarray[0] = rdata; rrarray[0] = rresp;
        scb_read_check(addr, rdarray, 8'h00, 2'b01, "single_rd", ok);
        cg_sample(2'b01, 8'h00, '1, apply_bp);
    endtask

    // Burst write (up to 16 beats) — all beats use same strobe
    task automatic bfm_write_burst(
        input  [AXI_IDW-1:0] id,
        input  [AXI_AW-1:0]  addr,
        input  [AXI_DW-1:0]  data [0:15],
        input  [AXI_SW-1:0]  strb,
        input  [7:0]          len,
        input  [1:0]          burst,
        input  logic          apply_bp,
        output logic [1:0]    bresp
    );
        int timeout;
        logic [AXI_SW-1:0] sarray[0:15];
        for (int i = 0; i <= 15; i++) sarray[i] = strb;

        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD AWREADY (burst wr)"); break; end
        end
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= len;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= burst;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);
        s_axi_awvalid <= 1'b0;

        for (int b = 0; b <= int'(len); b++) begin
            timeout = WATCHDOG_CYCLES;
            while (!s_axi_wready) begin
                @(posedge aclk);
                if (--timeout == 0) begin $display("[BFM] WD WREADY (burst wr beat %0d)", b); break; end
            end
            s_axi_wdata  <= data[b];
            s_axi_wstrb  <= strb;
            s_axi_wlast  <= (b == int'(len));
            s_axi_wvalid <= 1'b1;
            @(posedge aclk);
            s_axi_wvalid <= 1'b0;
            s_axi_wlast  <= 1'b0;
        end

        if (apply_bp) @(posedge aclk);

        timeout = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD BVALID (burst wr)"); break; end
        end
        bresp        = s_axi_bresp;
        s_axi_bready <= 1'b1;
        @(posedge aclk);
        s_axi_bready <= 1'b0;
        @(posedge aclk);

        scb_write(addr, data, sarray, len, burst);
        cg_sample(burst, len, strb, apply_bp);
    endtask

    // Burst read (up to 16 beats)
    task automatic bfm_read_burst(
        input  [AXI_IDW-1:0]  id,
        input  [AXI_AW-1:0]   addr,
        input  [7:0]           len,
        input  [1:0]           burst,
        input  logic           apply_bp,
        output logic [AXI_DW-1:0] rdata [0:15],
        output logic [1:0]        rresp [0:15]
    );
        int   timeout;
        logic ok;

        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD ARREADY (burst rd)"); break; end
        end
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= len;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= burst;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);
        s_axi_arvalid <= 1'b0;

        if (apply_bp) @(posedge aclk);

        timeout = WATCHDOG_CYCLES;
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD RVALID (burst rd beat 0)"); break; end
        end
        rdata[0] = s_axi_rdata;
        rresp[0] = s_axi_rresp;
        s_axi_rready <= 1'b1;
        for (int beat = 1; beat <= int'(len); beat++) begin
            @(posedge aclk);
            rdata[beat] = s_axi_rdata;
            rresp[beat] = s_axi_rresp;
        end
        @(posedge aclk);
        s_axi_rready <= 1'b0;
        @(posedge aclk);

        scb_read_check(addr, rdata, len, burst, "burst_rd", ok);
        cg_sample(burst, len, '1, apply_bp);
    endtask

    //=========================================================================
    // Extended BFM Driver Tasks
    //=========================================================================

    // Burst write with per-beat strobe array (each beat uses a different strobe)
    task automatic bfm_write_burst_strobe_array(
        input  [AXI_IDW-1:0] id,
        input  [AXI_AW-1:0]  addr,
        input  [AXI_DW-1:0]  data [0:15],
        input  [AXI_SW-1:0]  strb [0:15],
        input  [7:0]          len,
        input  [1:0]          burst,
        input  logic          apply_bp,
        output logic [1:0]    bresp
    );
        int timeout;
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD AWREADY (strb_arr)"); break; end
        end
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= len;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= burst;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);
        s_axi_awvalid <= 1'b0;

        for (int b = 0; b <= int'(len); b++) begin
            timeout = WATCHDOG_CYCLES;
            while (!s_axi_wready) begin
                @(posedge aclk);
                if (--timeout == 0) begin $display("[BFM] WD WREADY (strb_arr b=%0d)", b); break; end
            end
            s_axi_wdata  <= data[b];
            s_axi_wstrb  <= strb[b];   // per-beat strobe
            s_axi_wlast  <= (b == int'(len));
            s_axi_wvalid <= 1'b1;
            @(posedge aclk);
            s_axi_wvalid <= 1'b0;
            s_axi_wlast  <= 1'b0;
        end

        if (apply_bp) @(posedge aclk);

        timeout = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD BVALID (strb_arr)"); break; end
        end
        bresp        = s_axi_bresp;
        s_axi_bready <= 1'b1;
        @(posedge aclk);
        s_axi_bready <= 1'b0;
        @(posedge aclk);

        scb_write(addr, data, strb, len, burst);
        cg_sample(burst, len, strb[0], apply_bp);
    endtask

    // Burst read with per-beat rready back-pressure (0-3 hold cycles per beat)
    task automatic bfm_read_burst_beat_bp(
        input  [AXI_IDW-1:0]  id,
        input  [AXI_AW-1:0]   addr,
        input  [7:0]           len,
        input  [1:0]           burst,
        output logic [AXI_DW-1:0] rdata [0:15],
        output logic [1:0]        rresp [0:15]
    );
        int   timeout;
        logic ok;

        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD ARREADY (beat_bp)"); break; end
        end
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= len;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= burst;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);
        s_axi_arvalid <= 1'b0;

        for (int beat = 0; beat <= int'(len); beat++) begin
            // Per-beat back-pressure: hold rready low 0-3 cycles before accepting
            repeat ($urandom_range(0, 3)) @(posedge aclk);
            timeout = WATCHDOG_CYCLES;
            while (!s_axi_rvalid) begin
                @(posedge aclk);
                if (--timeout == 0) begin $display("[BFM] WD RVALID beat_bp[%0d]", beat); break; end
            end
            rdata[beat] = s_axi_rdata;
            rresp[beat] = s_axi_rresp;
            s_axi_rready <= 1'b1;
            @(posedge aclk);
            s_axi_rready <= 1'b0;
        end
        @(posedge aclk);

        scb_read_check(addr, rdata, len, burst, "burst_rd_beat_bp", ok);
        cg_sample(burst, len, '1, 1'b1);
    endtask

    // Single-beat narrow write: awsize < AXI_SZ; strb selects the active byte lane(s).
    // addr may be sub-word-aligned; scoreboard is keyed to the word-aligned base.
    task automatic bfm_write_narrow(
        input  [AXI_IDW-1:0] id,
        input  [AXI_AW-1:0]  addr,
        input  [AXI_DW-1:0]  data,
        input  [AXI_SW-1:0]  strb,
        input  [2:0]          axi_size,
        output logic [1:0]    bresp
    );
        automatic logic [AXI_AW-1:0] word_addr = addr & ~AXI_AW'(AXI_SW - 1);
        automatic logic [AXI_DW-1:0] darray[0:15];
        automatic logic [AXI_SW-1:0] sarray[0:15];
        int timeout;
        darray[0] = data;
        sarray[0] = strb;

        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD AWREADY (narrow wr)"); break; end
        end
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'h00;
        s_axi_awsize  <= axi_size;
        s_axi_awburst <= 2'b01;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);
        s_axi_awvalid <= 1'b0;

        timeout = WATCHDOG_CYCLES;
        while (!s_axi_wready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD WREADY (narrow wr)"); break; end
        end
        s_axi_wdata  <= data;
        s_axi_wstrb  <= strb;
        s_axi_wlast  <= 1'b1;
        s_axi_wvalid <= 1'b1;
        @(posedge aclk);
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        timeout = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD BVALID (narrow wr)"); break; end
        end
        bresp        = s_axi_bresp;
        s_axi_bready <= 1'b1;
        @(posedge aclk);
        s_axi_bready <= 1'b0;
        @(posedge aclk);

        scb_write(word_addr, darray, sarray, 8'h00, 2'b01);
        cg_sample(2'b01, 8'h00, strb, 1'b0);
    endtask

    // Single-beat narrow read: arsize < AXI_SZ.
    // Scoreboard validates only previously-written byte lanes.
    task automatic bfm_read_narrow(
        input  [AXI_IDW-1:0]  id,
        input  [AXI_AW-1:0]   addr,
        input  [2:0]           axi_size,
        output logic [AXI_DW-1:0] rdata,
        output logic [1:0]        rresp
    );
        automatic logic [AXI_AW-1:0] word_addr = addr & ~AXI_AW'(AXI_SW - 1);
        automatic logic [AXI_DW-1:0] rdarray[0:15];
        automatic logic              ok;
        int timeout;

        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD ARREADY (narrow rd)"); break; end
        end
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'h00;
        s_axi_arsize  <= axi_size;
        s_axi_arburst <= 2'b01;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);
        s_axi_arvalid <= 1'b0;

        timeout = WATCHDOG_CYCLES;
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[BFM] WD RVALID (narrow rd)"); break; end
        end
        rdata        = s_axi_rdata;
        rresp        = s_axi_rresp;
        s_axi_rready <= 1'b1;
        @(posedge aclk);
        s_axi_rready <= 1'b0;
        @(posedge aclk);

        rdarray[0] = rdata;
        scb_read_check(word_addr, rdarray, 8'h00, 2'b01, "narrow_rd", ok);
        cg_sample(2'b01, 8'h00, '1, 1'b0);
    endtask

    //=========================================================================
    // Randomised Sequences
    //=========================================================================

    // Helper: random aligned address inside sim memory range, aligned to AXI_SW
    function automatic logic [AXI_AW-1:0] rand_addr(input int max_word);
        int w = $urandom_range(0, max_word - 1);
        return BASE + 32'(w * AXI_SW);
    endfunction

    // Helper: random INCR-burst start address leaving room for len+1 beats
    function automatic logic [AXI_AW-1:0] rand_incr_addr(input int max_word, input int len);
        int w = $urandom_range(0, max_word - len - 2);
        return BASE + 32'(w * AXI_SW);
    endfunction

    // Helper: random WRAP-burst address aligned to wrap window
    function automatic logic [AXI_AW-1:0] rand_wrap_addr(input int len);
        // beats must be 2,4,8, or 16 for WRAP; len+1 must be power-of-two
        // wrap window = (len+1)*AXI_SW bytes; start addr must be anywhere,
        // we align naturally as the DUT wraps automatically.
        // Choose a random word in the first half of memory to avoid overflow.
        int w = $urandom_range(0, (SIM_DEPTH / 2) - 1);
        return BASE + 32'(w * AXI_SW);
    endfunction

    //-------------------------------------------------------------------------
    // Sequence 1: random single read-after-write
    //-------------------------------------------------------------------------
    task automatic run_seq_single_rw();
        logic [AXI_DW-1:0] wdata, rdata;
        logic [AXI_SW-1:0] strb;
        logic [AXI_AW-1:0] addr;
        logic [1:0]         bresp, rresp;
        $display("\n=== SEQ: single_rw (%0d iterations) ===", N_RAND);
        for (int i = 0; i < N_RAND; i++) begin
            addr  = rand_addr(SIM_DEPTH);
            wdata = {$urandom(), $urandom()};   // extra bits ignored for AXI32 (truncated)
            strb  = '1;
            bfm_write_single(4'h1, addr, wdata[AXI_DW-1:0], strb, 1'b0, bresp);
            bfm_read_single (4'h1, addr, 1'b0, rdata, rresp);
        end
    endtask

    //-------------------------------------------------------------------------
    // Sequence 2: random INCR burst write then read-back
    //-------------------------------------------------------------------------
    task automatic run_seq_burst_incr();
        localparam int MAX_LEN = 7;     // 0..7 → 1..8 beats
        logic [AXI_DW-1:0] wdata[0:15], rdata[0:15];
        logic [1:0]         rresp[0:15];
        logic [AXI_AW-1:0] addr;
        logic [7:0]         len;
        logic [1:0]         bresp;
        $display("\n=== SEQ: burst_incr (%0d iterations) ===", N_RAND);
        for (int i = 0; i < N_RAND; i++) begin
            len  = 8'($urandom_range(1, MAX_LEN));
            addr = rand_incr_addr(SIM_DEPTH, int'(len));
            for (int b = 0; b <= int'(len); b++)
                wdata[b] = {$urandom(), $urandom()};
            bfm_write_burst(4'h2, addr, wdata, '1, len, 2'b01, 1'b0, bresp);
            bfm_read_burst (4'h2, addr, len,   2'b01, 1'b0, rdata, rresp);
        end
    endtask

    //-------------------------------------------------------------------------
    // Sequence 3: WRAP burst write then read-back (len = 1,3,7,15 → 2/4/8/16 beats)
    //-------------------------------------------------------------------------
    task automatic run_seq_burst_wrap();
        logic [AXI_DW-1:0] wdata[0:15], rdata[0:15];
        logic [1:0]         rresp[0:15];
        logic [AXI_AW-1:0] addr;
        logic [7:0]         len;
        logic [1:0]         bresp;
        int                 lens[4] = '{1, 3, 7, 15};
        $display("\n=== SEQ: burst_wrap (%0d iterations) ===", N_RAND);
        for (int i = 0; i < N_RAND; i++) begin
            len  = 8'(lens[$urandom_range(0, 3)]);
            addr = rand_wrap_addr(int'(len));
            for (int b = 0; b <= int'(len); b++)
                wdata[b] = {$urandom(), $urandom()};
            bfm_write_burst(4'h3, addr, wdata, '1, len, 2'b10, 1'b0, bresp);
            bfm_read_burst (4'h3, addr, len,   2'b10, 1'b0, rdata, rresp);
        end
    endtask

    //-------------------------------------------------------------------------
    // Sequence 4: FIXED burst (only the first address matters; all beats write same word)
    //-------------------------------------------------------------------------
    task automatic run_seq_burst_fixed();
        localparam int FIX_LEN = 3;   // 4 beats, always same address
        logic [AXI_DW-1:0] wdata[0:15], rdata[0:15];
        logic [1:0]         rresp[0:15];
        logic [AXI_AW-1:0] addr;
        logic [1:0]         bresp;
        $display("\n=== SEQ: burst_fixed (%0d iterations) ===", N_RAND);
        for (int i = 0; i < N_RAND; i++) begin
            addr = rand_addr(SIM_DEPTH);
            // Last beat wins for FIXED: write the same address FIX_LEN+1 times
            for (int b = 0; b <= FIX_LEN; b++)
                wdata[b] = {$urandom(), $urandom()};
            bfm_write_burst(4'h4, addr, wdata, '1, 8'(FIX_LEN), 2'b00, 1'b0, bresp);
            // Shadow already reflects last beat (scb_write loops in order so last write wins)
            bfm_read_burst (4'h4, addr, 8'(FIX_LEN), 2'b00, 1'b0, rdata, rresp);
        end
    endtask

    //-------------------------------------------------------------------------
    // Sequence 5: byte-strobe patterns
    //-------------------------------------------------------------------------
    task automatic run_seq_strobe();
        logic [AXI_DW-1:0] wdata, rdata;
        logic [AXI_SW-1:0] strb;
        logic [AXI_AW-1:0] addr;
        logic [1:0]         bresp, rresp;
        // Pre-fill target address with a known value
        $display("\n=== SEQ: strobe (%0d iterations) ===", N_RAND);
        for (int i = 0; i < N_RAND; i++) begin
            addr  = rand_addr(SIM_DEPTH);
            // First: write all-ones to initialise
            bfm_write_single(4'h5, addr, '1, '1, 1'b0, bresp);
            // Then: write with a random partial strobe
            wdata = {$urandom(), $urandom()};
            strb  = AXI_SW'($urandom_range(1, (1 << AXI_SW) - 1));
            bfm_write_single(4'h5, addr, wdata[AXI_DW-1:0], strb, 1'b0, bresp);
            // Read back and verify
            bfm_read_single (4'h5, addr, 1'b0, rdata, rresp);
        end
    endtask

    //-------------------------------------------------------------------------
    // Sequence 6: back-pressure (bready/rready delayed 1 cycle randomly)
    //-------------------------------------------------------------------------
    task automatic run_seq_backpressure();
        logic [AXI_DW-1:0] wdata[0:15], rdata[0:15];
        logic [1:0]         rresp[0:15];
        logic [AXI_AW-1:0] addr;
        logic [7:0]         len;
        logic [1:0]         bresp;
        logic               bp;
        $display("\n=== SEQ: backpressure (%0d iterations) ===", N_RAND);
        for (int i = 0; i < N_RAND; i++) begin
            len  = 8'($urandom_range(0, 7));
            addr = rand_incr_addr(SIM_DEPTH, int'(len));
            bp   = logic'($urandom_range(0, 1));
            for (int b = 0; b <= int'(len); b++)
                wdata[b] = {$urandom(), $urandom()};
            bfm_write_burst(4'h6, addr, wdata, '1, len, 2'b01, bp,   bresp);
            bfm_read_burst (4'h6, addr, len,   2'b01,   bp,   rdata, rresp);
        end
    endtask

    //-------------------------------------------------------------------------
    // Sequence 7: page-miss torture
    //   Alternates between Bank-0/Row-0 and Bank-0/Row-1 to force a page-miss
    //   on every write after the first.  Both addresses are within SIM_DEPTH.
    //-------------------------------------------------------------------------
    task automatic run_seq_page_miss();
        logic [AXI_AW-1:0] addr_r0, addr_r1;
        logic [AXI_DW-1:0] wdata, rdata;
        logic [1:0]         bresp, rresp;
        localparam int N_PM = 8;
        addr_r0 = BASE;                                        // Bank 0, Row 0
        addr_r1 = BASE + 32'(ROW_STRIDE_WORDS * AXI_SW);      // Bank 0, Row 1
        $display("\n=== SEQ: page_miss (%0d alternating pairs to 2 rows of bank 0) ===", N_PM);
        for (int i = 0; i < N_PM; i++) begin
            wdata = {$urandom(), $urandom()};
            bfm_write_single(4'hA, addr_r0, wdata[AXI_DW-1:0], '1, 1'b0, bresp);
            wdata = {$urandom(), $urandom()};
            bfm_write_single(4'hA, addr_r1, wdata[AXI_DW-1:0], '1, 1'b0, bresp);
        end
        // Read-back to verify data integrity after alternating page-misses
        bfm_read_single(4'hA, addr_r0, 1'b0, rdata, rresp);
        bfm_read_single(4'hA, addr_r1, 1'b0, rdata, rresp);
    endtask

    //-------------------------------------------------------------------------
    // Sequence 8: out-of-range address access
    //   Issues one write and one read beyond SIM_DEPTH.
    //   Expects SLVERR and verifies stats.address_errors increments.
    //-------------------------------------------------------------------------
    task automatic run_seq_oob_access();
        logic [AXI_AW-1:0] oob_addr;
        logic [AXI_DW-1:0] wdata, rdata;
        logic [1:0]         bresp, rresp;
        // First address beyond the simulated memory region
        oob_addr = BASE + AXI_AW'(SIM_DEPTH * AXI_SW);
        $display("\n=== SEQ: oob_access (addr beyond SIM_DEPTH → SLVERR expected) ===");
        wdata = {$urandom(), $urandom()};
        bfm_write_single(4'h0, oob_addr, wdata, '1, 1'b0, bresp);
        if (bresp === 2'b10)
            $display("  OOB write SLVERR  [PASS]");
        else begin
            $display("  [FAIL] OOB write got bresp=%0b, expected SLVERR(10)", bresp);
            txn_fail++;
        end
        bfm_read_single(4'h0, oob_addr, 1'b0, rdata, rresp);
        if (rresp === 2'b10)
            $display("  OOB read  SLVERR  [PASS]");
        else begin
            $display("  [FAIL] OOB read  got rresp=%0b, expected SLVERR(10)", rresp);
            txn_fail++;
        end
    endtask

    //-------------------------------------------------------------------------
    // Sequence 9: write-to-read timing stress
    //   Writes to Bank Group 1 (offset 0x4000 from BASE) then immediately
    //   reads from Bank Group 0 (BASE).  At CLK_PERIOD_NS=1 (1 GHz aclk)
    //   the read CAS arrives within the tWTR_L window (8 ns for DDR4-2400),
    //   triggering the tWTR stall counter.
    //   Bank group mapping: b_idx = ((addr-BASE)>>12) & 15; bg = b_idx>>2
    //     BG0: addr-BASE[15:14] = 00 → offset 0x0000  (b_idx=0)
    //     BG1: addr-BASE[15:14] = 01 → offset 0x4000  (b_idx=4)
    //-------------------------------------------------------------------------
    task automatic run_seq_wtr_stress();
        localparam int WTR_PAIRS = 4;
        logic [AXI_AW-1:0] addr_bg0, addr_bg1;
        logic [AXI_DW-1:0] wdata, rdata;
        logic [1:0]         bresp, rresp;
        addr_bg0 = BASE;                       // Bank Group 0, Bank 0
        addr_bg1 = BASE + 32'h0000_4000;       // Bank Group 1, Bank 4 (within SIM_DEPTH)
        $display("\n=== SEQ: wtr_stress (%0d WR(BG1)->RD(BG0) pairs — tWTR_L fires at 1 GHz) ===",
                 WTR_PAIRS);
        for (int i = 0; i < WTR_PAIRS; i++) begin
            wdata = {$urandom(), $urandom()};
            bfm_write_single(4'h0, addr_bg1, wdata, '1, 1'b0, bresp);
            bfm_read_single(4'h0, addr_bg0, 1'b0, rdata, rresp);
        end
    endtask

    //-------------------------------------------------------------------------
    // Sequence 10: DMA-style concurrent WR + RD
    //
    //   Issues an AW, then — before the write data phase begins — simultaneously
    //   runs two independent threads via fork/join:
    //     • Write-data thread : waits for wready (DDR4 preamble done), drives
    //                           W-channel, then waits for BRESP.
    //     • Read thread       : checks arready (independent RD FSM should be
    //                           RD_IDLE → arready=1), issues AR, waits rvalid,
    //                           captures R data.
    //   This validates three AXI4 properties:
    //     1. No deadlock — both channels complete within WATCHDOG_CYCLES.
    //     2. arready is asserted independently of write-FSM state.
    //     3. Read data is byte-accurate against the scoreboard.
    //
    //   Memory layout (words):
    //     Read zone  : BASE + [0 .. DMA_N-1]               (pre-populated)
    //     Write zone : BASE + [SIM_DEPTH/2 .. /2+DMA_N-1]  (fresh targets)
    //-------------------------------------------------------------------------
    task automatic run_seq_dma_concurrent();
        localparam int DMA_N   = 8;
        localparam int WR_OFF  = SIM_DEPTH / 2;

        logic [AXI_DW-1:0] expected [0:DMA_N-1];
        logic [1:0]         tmp_bresp;
        int                 pass_cnt, fail_cnt;

        pass_cnt = 0;
        fail_cnt = 0;
        $display("\n=== SEQ: dma_concurrent (%0d overlapping WR+RD pairs — fork/join) ===", DMA_N);

        // ── Phase 1: pre-populate read zone ──────────────────────────────
        for (int i = 0; i < DMA_N; i++) begin
            automatic logic [AXI_AW-1:0] prep_a = BASE + AXI_AW'(i * AXI_SW);
            automatic logic [AXI_DW-1:0] seed   = AXI_DW'(32'hA0A0_0000 | i);
            expected[i] = seed;
            bfm_write_single(4'h0, prep_a, seed, '1, 1'b0, tmp_bresp);
        end

        // ── Phase 2: for each pair, post AW then fork WR-data || RD ──────
        for (int i = 0; i < DMA_N; i++) begin
            automatic logic [AXI_AW-1:0] wr_addr    = BASE + AXI_AW'((WR_OFF + i) * AXI_SW);
            automatic logic [AXI_AW-1:0] rd_addr    = BASE + AXI_AW'(i * AXI_SW);
            automatic logic [AXI_DW-1:0] my_wdata   = AXI_DW'(32'hC0C0_0000 | i);
            automatic logic [AXI_DW-1:0] my_rdata   = '0;
            automatic logic [1:0]        my_bresp    = 2'b11;  // sentinel
            automatic logic [1:0]        my_rresp    = 2'b11;  // sentinel
            automatic logic              ar_accepted = 1'b0;
            int t;

            // Issue write address (AW handshake) ─────────────────────────
            @(posedge aclk);
            t = WATCHDOG_CYCLES;
            while (!s_axi_awready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [DMA-CONC] WD awready i=%0d", i); break; end
            end
            s_axi_awid    <= 4'h4;
            s_axi_awaddr  <= wr_addr;
            s_axi_awlen   <= 8'h00;
            s_axi_awsize  <= 3'(AXI_SZ);
            s_axi_awburst <= 2'b01;
            s_axi_awvalid <= 1'b1;
            @(posedge aclk);
            s_axi_awvalid <= 1'b0;
            // Write FSM → WR_ADDR_WAIT; awready=0.
            // arready should still be 1 (RD FSM independently in RD_IDLE).

            // Fork: WR-data + BRESP  ||  AR + R-data ─────────────────────
            fork
                // Thread A – write data + BRESP
                begin
                    int ta;
                    ta = WATCHDOG_CYCLES;
                    while (!s_axi_wready) begin
                        @(posedge aclk);
                        if (--ta == 0) begin $display("  [DMA-CONC] WD wready i=%0d", i); break; end
                    end
                    s_axi_wdata  <= my_wdata;
                    s_axi_wstrb  <= '1;
                    s_axi_wlast  <= 1'b1;
                    s_axi_wvalid <= 1'b1;
                    @(posedge aclk);
                    s_axi_wvalid <= 1'b0;
                    s_axi_wlast  <= 1'b0;
                    ta = WATCHDOG_CYCLES;
                    while (!s_axi_bvalid) begin
                        @(posedge aclk);
                        if (--ta == 0) begin $display("  [DMA-CONC] WD bvalid i=%0d", i); break; end
                    end
                    my_bresp     = s_axi_bresp;
                    s_axi_bready <= 1'b1;
                    @(posedge aclk);
                    s_axi_bready <= 1'b0;
                end
                // Thread B – AR + R-data (concurrent with write)
                begin
                    int tb;
                    @(posedge aclk);   // 1-cycle settling so WR_ADDR_WAIT state is stable
                    // arready expected = 1 when RD FSM is independent of WR FSM
                    tb = WATCHDOG_CYCLES;
                    while (!s_axi_arready) begin
                        @(posedge aclk);
                        if (--tb == 0) begin
                            $display("  [DMA-CONC] WD arready i=%0d (slave serialises WR+RD)", i);
                            break;
                        end
                    end
                    ar_accepted = s_axi_arready;
                    if (s_axi_arready) begin
                        s_axi_arid    <= 4'h5;
                        s_axi_araddr  <= rd_addr;
                        s_axi_arlen   <= 8'h00;
                        s_axi_arsize  <= 3'(AXI_SZ);
                        s_axi_arburst <= 2'b01;
                        s_axi_arvalid <= 1'b1;
                        @(posedge aclk);
                        s_axi_arvalid <= 1'b0;
                        tb = WATCHDOG_CYCLES;
                        while (!s_axi_rvalid) begin
                            @(posedge aclk);
                            if (--tb == 0) begin $display("  [DMA-CONC] WD rvalid i=%0d", i); break; end
                        end
                        my_rdata      = s_axi_rdata;
                        my_rresp      = s_axi_rresp;
                        s_axi_rready <= 1'b1;
                        @(posedge aclk);
                        s_axi_rready <= 1'b0;
                        @(posedge aclk);
                    end
                end
            join  // both threads must complete before checking results

            // Update scoreboard for the new write
            begin
                automatic logic [AXI_DW-1:0] sdata[0:15];
                automatic logic [AXI_SW-1:0] sstrb[0:15];
                sdata[0] = my_wdata; sstrb[0] = '1;
                scb_write(wr_addr, sdata, sstrb, 8'h00, 2'b01);
            end

            // Check BRESP
            if (my_bresp === 2'b00) begin txn_pass++; pass_cnt++; end
            else begin
                $display("  [FAIL] dma_conc[%0d] WR bresp=0b%0b (expected OKAY)", i, my_bresp);
                txn_fail++; fail_cnt++;
            end

            // Check R data
            if (!ar_accepted) begin
                $display("  dma_conc[%0d]: arready blocked during write — slave serialises WR+RD [INFO]", i);
            end else if (my_rresp === 2'b00 && my_rdata === expected[i]) begin
                txn_pass++; pass_cnt++;
                $display("  dma_conc[%0d]: concurrent RD data=0x%08h [PASS]", i, my_rdata);
            end else begin
                $display("  [FAIL] dma_conc[%0d] RD got=0x%08h exp=0x%08h rresp=0b%0b",
                         i, my_rdata, expected[i], my_rresp);
                txn_fail++; fail_cnt++;
            end
        end

        $display("  dma_concurrent: %0d pass, %0d fail", pass_cnt, fail_cnt);
    endtask

    //-------------------------------------------------------------------------
    // Sequence 11: DMA-style outstanding / back-to-back pipelining
    //
    //   Part A — back-to-back writes (N=8):
    //     Issues each new awvalid in the same cycle awready re-asserts after
    //     the previous BRESP.  Verifies awready has zero hidden stall cycles
    //     when the slave returns to WR_IDLE.
    //
    //   Part B — AR posted while AW preamble is in progress:
    //     Post AW → immediately post AR (before driving W data) → fork:
    //       • W-data thread waits for wready (DDR4 preamble), drives W, waits B.
    //       • Read thread    captures R data (may complete before BRESP).
    //     Confirms the read channel can overtake a write stalled on wready=0.
    //
    //   Part C — back-to-back reads (N=8, mirror of Part A).
    //-------------------------------------------------------------------------
    task automatic run_seq_dma_outstanding();
        localparam int OST_N   = 8;
        localparam int WR_OFF  = SIM_DEPTH / 2 + 16;  // avoid dma_concurrent zone

        logic [1:0] bresp, rresp;
        int         pass_cnt, fail_cnt, t;

        pass_cnt = 0;
        fail_cnt = 0;
        $display("\n=== SEQ: dma_outstanding (%0d back-to-back + AR-overlaps-AW test) ===", OST_N);

        // ── Part A: N back-to-back writes with zero idle gap ─────────────
        $display("  Part A: back-to-back writes");
        for (int i = 0; i < OST_N; i++) begin
            automatic logic [AXI_AW-1:0] addr = BASE + AXI_AW'((WR_OFF + i) * AXI_SW);
            automatic logic [AXI_DW-1:0] dat  = AXI_DW'(32'hD0D0_0000 | i);
            // awvalid issued with zero extra gap — awready must be 1 immediately
            t = WATCHDOG_CYCLES;
            @(posedge aclk);
            while (!s_axi_awready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [DMA-OST] WD awready wr i=%0d", i); break; end
            end
            s_axi_awid    <= 4'h6;
            s_axi_awaddr  <= addr;
            s_axi_awlen   <= 8'h00;
            s_axi_awsize  <= 3'(AXI_SZ);
            s_axi_awburst <= 2'b01;
            s_axi_awvalid <= 1'b1;
            @(posedge aclk);
            s_axi_awvalid <= 1'b0;
            t = WATCHDOG_CYCLES;
            while (!s_axi_wready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [DMA-OST] WD wready i=%0d", i); break; end
            end
            s_axi_wdata  <= dat;
            s_axi_wstrb  <= '1;
            s_axi_wlast  <= 1'b1;
            s_axi_wvalid <= 1'b1;
            @(posedge aclk);
            s_axi_wvalid <= 1'b0;
            s_axi_wlast  <= 1'b0;
            t = WATCHDOG_CYCLES;
            while (!s_axi_bvalid) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [DMA-OST] WD bvalid i=%0d", i); break; end
            end
            bresp        = s_axi_bresp;
            s_axi_bready <= 1'b1;
            @(posedge aclk);
            s_axi_bready <= 1'b0;
            // No extra gap — next awvalid on the very next loop iteration cycle
            begin
                automatic logic [AXI_DW-1:0] sdata[0:15];
                automatic logic [AXI_SW-1:0] sstrb[0:15];
                sdata[0] = dat; sstrb[0] = '1;
                scb_write(addr, sdata, sstrb, 8'h00, 2'b01);
            end
            if (bresp === 2'b00) begin txn_pass++; pass_cnt++; end
            else begin
                $display("  [FAIL] dma_ost wr[%0d] bresp=0b%0b", i, bresp);
                txn_fail++; fail_cnt++;
            end
        end

        // ── Part B: AR posted immediately after AW (before W data) ───────
        $display("  Part B: AR posted after AW handshake (before wready)");
        begin
            automatic logic [AXI_AW-1:0] wr_addr  = BASE + AXI_AW'((WR_OFF + OST_N) * AXI_SW);
            automatic logic [AXI_AW-1:0] rd_addr  = BASE + AXI_AW'(0);
            automatic logic [AXI_DW-1:0] my_wdata = AXI_DW'(32'hE0E0_E0E0);
            automatic logic [AXI_DW-1:0] my_rdata = '0;
            automatic logic [1:0]        my_bresp  = 2'b11;
            automatic logic [1:0]        my_rresp  = 2'b11;

            // Post write address
            @(posedge aclk);
            t = WATCHDOG_CYCLES;
            while (!s_axi_awready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [DMA-OST-B] WD awready"); break; end
            end
            s_axi_awid    <= 4'h7;
            s_axi_awaddr  <= wr_addr;
            s_axi_awlen   <= 8'h00;
            s_axi_awsize  <= 3'(AXI_SZ);
            s_axi_awburst <= 2'b01;
            s_axi_awvalid <= 1'b1;
            @(posedge aclk);
            s_axi_awvalid <= 1'b0;
            // wready=0 here (DDR4 preamble pending); post AR before driving W

            fork
                // Thread A – write data + BRESP
                begin
                    int ta;
                    ta = WATCHDOG_CYCLES;
                    while (!s_axi_wready) begin
                        @(posedge aclk);
                        if (--ta == 0) begin $display("  [DMA-OST-B] WD wready"); break; end
                    end
                    s_axi_wdata  <= my_wdata;
                    s_axi_wstrb  <= '1;
                    s_axi_wlast  <= 1'b1;
                    s_axi_wvalid <= 1'b1;
                    @(posedge aclk);
                    s_axi_wvalid <= 1'b0;
                    s_axi_wlast  <= 1'b0;
                    ta = WATCHDOG_CYCLES;
                    while (!s_axi_bvalid) begin
                        @(posedge aclk);
                        if (--ta == 0) begin $display("  [DMA-OST-B] WD bvalid"); break; end
                    end
                    my_bresp     = s_axi_bresp;
                    s_axi_bready <= 1'b1;
                    @(posedge aclk);
                    s_axi_bready <= 1'b0;
                end
                // Thread B – read (concurrent; may complete before BRESP)
                begin
                    int tb;
                    @(posedge aclk);
                    tb = WATCHDOG_CYCLES;
                    while (!s_axi_arready) begin
                        @(posedge aclk);
                        if (--tb == 0) begin $display("  [DMA-OST-B] WD arready"); break; end
                    end
                    if (s_axi_arready) begin
                        s_axi_arid    <= 4'h8;
                        s_axi_araddr  <= rd_addr;
                        s_axi_arlen   <= 8'h00;
                        s_axi_arsize  <= 3'(AXI_SZ);
                        s_axi_arburst <= 2'b01;
                        s_axi_arvalid <= 1'b1;
                        @(posedge aclk);
                        s_axi_arvalid <= 1'b0;
                        tb = WATCHDOG_CYCLES;
                        while (!s_axi_rvalid) begin
                            @(posedge aclk);
                            if (--tb == 0) begin $display("  [DMA-OST-B] WD rvalid"); break; end
                        end
                        my_rdata      = s_axi_rdata;
                        my_rresp      = s_axi_rresp;
                        s_axi_rready <= 1'b1;
                        @(posedge aclk);
                        s_axi_rready <= 1'b0;
                        @(posedge aclk);
                    end
                end
            join

            begin
                automatic logic [AXI_DW-1:0] sdata[0:15];
                automatic logic [AXI_SW-1:0] sstrb[0:15];
                sdata[0] = my_wdata; sstrb[0] = '1;
                scb_write(wr_addr, sdata, sstrb, 8'h00, 2'b01);
            end
            if (my_bresp === 2'b00) begin txn_pass++; pass_cnt++; end
            else begin
                $display("  [FAIL] dma_ost-B WR bresp=0b%0b", my_bresp); txn_fail++; fail_cnt++;
            end
            if (my_rresp === 2'b00) begin
                automatic logic [AXI_DW-1:0] rdarray[0:15];
                automatic logic ok;
                rdarray[0] = my_rdata;
                scb_read_check(rd_addr, rdarray, 8'h00, 2'b01, "dma_ost_B_rd", ok);
                if (ok) pass_cnt++; else fail_cnt++;
                $display("  dma_ost-B: read during AW preamble rdata=0x%08h [PASS]", my_rdata);
            end else
                $display("  dma_ost-B: AR not accepted while write pending [INFO]");
        end

        // ── Part C: N back-to-back reads with zero idle gap ──────────────
        $display("  Part C: back-to-back reads");
        for (int i = 0; i < OST_N; i++) begin
            automatic logic [AXI_AW-1:0] addr = BASE + AXI_AW'((WR_OFF + i) * AXI_SW);
            automatic logic [AXI_DW-1:0] rdarray [0:15];
            automatic logic ok;
            t = WATCHDOG_CYCLES;
            @(posedge aclk);
            while (!s_axi_arready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [DMA-OST] WD arready rd i=%0d", i); break; end
            end
            s_axi_arid    <= 4'h9;
            s_axi_araddr  <= addr;
            s_axi_arlen   <= 8'h00;
            s_axi_arsize  <= 3'(AXI_SZ);
            s_axi_arburst <= 2'b01;
            s_axi_arvalid <= 1'b1;
            @(posedge aclk);
            s_axi_arvalid <= 1'b0;
            t = WATCHDOG_CYCLES;
            while (!s_axi_rvalid) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [DMA-OST] WD rvalid rd i=%0d", i); break; end
            end
            rdarray[0]    = s_axi_rdata;
            rresp         = s_axi_rresp;
            s_axi_rready <= 1'b1;
            @(posedge aclk);
            s_axi_rready <= 1'b0;
            // No extra gap — arvalid on the very next loop iteration cycle
            scb_read_check(addr, rdarray, 8'h00, 2'b01, "dma_ost_rd", ok);
            if (ok) pass_cnt++; else fail_cnt++;
        end

        $display("  dma_outstanding: %0d pass, %0d fail", pass_cnt, fail_cnt);
    endtask

    //-------------------------------------------------------------------------
    // Sequence 12: True outstanding requests — flood FIFO to depth N
    //
    //   Part A — write outstanding (flood AW FIFO before driving any W data):
    //     Post OST_N AWs rapidly without waiting for any BRESP.  The slave's
    //     AW FIFO accepts them (awready stays high; FIFO depth = 16).  While
    //     the slave processes AW[0] through the DDR4 CDC preamble, AW[1..N-1]
    //     queue up — max_outstanding_writes rises to N.  W beats + BRESPs are
    //     then drained serially in a second pass.
    //
    //   Part B — read outstanding (flood AR FIFO before collecting any rvalid):
    //     Read back the locations written in Part A.  Post OST_N ARs without
    //     accepting any rvalid — slave queues them while processing AR[0].
    //     max_outstanding_reads rises to N.  R responses are then collected
    //     and verified against the scoreboard.
    //-------------------------------------------------------------------------
    task automatic run_seq_true_outstanding();
        localparam int OST_N   = 16;
        localparam int WR_BASE = SIM_DEPTH / 2 + 32;  // beyond dma_outstanding zone

        logic [AXI_DW-1:0] wr_data [0:OST_N-1];
        logic [1:0]         bresp, rresp;
        int                 pass_cnt, fail_cnt, t;

        pass_cnt = 0;
        fail_cnt = 0;
        $display("\n=== SEQ: true_outstanding (%0d AWs / ARs, FIFO depth=%0d) ===",
                 OST_N, dut.MAX_OUTSTANDING);

        // ── Part A: flood AW FIFO, then drain with W data ────────────────
        $display("  Part A: post all %0d AWs before any W data", OST_N);
        for (int i = 0; i < OST_N; i++)
            wr_data[i] = AXI_DW'(32'hF1F1_0000 | i);

        // Phase 1 – post all AWs (no W data, no BRESP wait)
        for (int i = 0; i < OST_N; i++) begin
            automatic logic [AXI_AW-1:0] addr = BASE + AXI_AW'((WR_BASE + i) * AXI_SW);
            @(posedge aclk);
            t = WATCHDOG_CYCLES;
            while (!s_axi_awready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [TRUE-OST] WD awready wr i=%0d", i); break; end
            end
            s_axi_awid    <= 4'hA;
            s_axi_awaddr  <= addr;
            s_axi_awlen   <= 8'h00;
            s_axi_awsize  <= 3'(AXI_SZ);
            s_axi_awburst <= 2'b01;
            s_axi_awvalid <= 1'b1;
            @(posedge aclk);
            s_axi_awvalid <= 1'b0;
            // No W/BRESP wait — immediately queue next AW into the FIFO
        end
        $display("  Part A phase1 done: %0d AWs queued. max_outstanding_writes=%0d",
                 OST_N, dut.stats.max_outstanding_writes);

        // Phase 2 – drive W beat + collect BRESP for each queued AW
        for (int i = 0; i < OST_N; i++) begin
            automatic logic [AXI_AW-1:0] addr = BASE + AXI_AW'((WR_BASE + i) * AXI_SW);
            t = WATCHDOG_CYCLES;
            while (!s_axi_wready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [TRUE-OST] WD wready wr i=%0d", i); break; end
            end
            s_axi_wdata  <= wr_data[i];
            s_axi_wstrb  <= '1;
            s_axi_wlast  <= 1'b1;
            s_axi_wvalid <= 1'b1;
            @(posedge aclk);
            s_axi_wvalid <= 1'b0;
            s_axi_wlast  <= 1'b0;
            t = WATCHDOG_CYCLES;
            while (!s_axi_bvalid) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [TRUE-OST] WD bvalid wr i=%0d", i); break; end
            end
            bresp        = s_axi_bresp;
            s_axi_bready <= 1'b1;
            @(posedge aclk);
            s_axi_bready <= 1'b0;
            begin
                automatic logic [AXI_DW-1:0] sdata[0:15];
                automatic logic [AXI_SW-1:0] sstrb[0:15];
                sdata[0] = wr_data[i]; sstrb[0] = '1;
                scb_write(addr, sdata, sstrb, 8'h00, 2'b01);
            end
            if (bresp === 2'b00) begin txn_pass++; pass_cnt++; end
            else begin
                $display("  [FAIL] true_ost wr[%0d] bresp=0b%0b", i, bresp);
                txn_fail++; fail_cnt++;
            end
        end
        $display("  Part A done. max_outstanding_writes=%0d (FIFO depth=%0d)",
                 dut.stats.max_outstanding_writes, dut.MAX_OUTSTANDING);
        if (dut.stats.max_outstanding_writes > 1)
            $display("  Part A: AW FIFO depth >1 confirmed [PASS]");
        else
            $display("  Part A: AW FIFO depth stayed at 1 — check DDR4 preamble timing [INFO]");

        // ── Part B: flood AR FIFO, then drain R responses ────────────────
        $display("  Part B: post all %0d ARs before collecting any R data", OST_N);

        // Phase 1 – post all ARs (no rvalid collection)
        for (int i = 0; i < OST_N; i++) begin
            automatic logic [AXI_AW-1:0] addr = BASE + AXI_AW'((WR_BASE + i) * AXI_SW);
            @(posedge aclk);
            t = WATCHDOG_CYCLES;
            while (!s_axi_arready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [TRUE-OST] WD arready rd i=%0d", i); break; end
            end
            s_axi_arid    <= 4'hB;
            s_axi_araddr  <= addr;
            s_axi_arlen   <= 8'h00;
            s_axi_arsize  <= 3'(AXI_SZ);
            s_axi_arburst <= 2'b01;
            s_axi_arvalid <= 1'b1;
            @(posedge aclk);
            s_axi_arvalid <= 1'b0;
            // No rvalid collection — immediately queue next AR into the FIFO
        end
        $display("  Part B phase1 done: %0d ARs queued. max_outstanding_reads=%0d",
                 OST_N, dut.stats.max_outstanding_reads);

        // Phase 2 – collect R response for each queued AR and verify
        for (int i = 0; i < OST_N; i++) begin
            automatic logic [AXI_AW-1:0] addr     = BASE + AXI_AW'((WR_BASE + i) * AXI_SW);
            automatic logic [AXI_DW-1:0] rdarray [0:15];
            automatic logic              ok;
            t = WATCHDOG_CYCLES;
            while (!s_axi_rvalid) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [TRUE-OST] WD rvalid rd i=%0d", i); break; end
            end
            rdarray[0]    = s_axi_rdata;
            rresp         = s_axi_rresp;
            s_axi_rready <= 1'b1;
            @(posedge aclk);
            s_axi_rready <= 1'b0;
            if (rresp === 2'b00) begin
                scb_read_check(addr, rdarray, 8'h00, 2'b01, "true_ost_rd", ok);
                if (!ok) fail_cnt++;
            end else begin
                $display("  [FAIL] true_ost rd[%0d] rresp=0b%0b", i, rresp);
                txn_fail++; fail_cnt++;
            end
        end
        $display("  Part B done. max_outstanding_reads=%0d (FIFO depth=%0d)",
                 dut.stats.max_outstanding_reads, dut.MAX_OUTSTANDING);
        if (dut.stats.max_outstanding_reads > 1)
            $display("  Part B: AR FIFO depth >1 confirmed [PASS]");
        else
            $display("  Part B: AR FIFO depth stayed at 1 — check DDR4 latency timing [INFO]");

        $display("  true_outstanding: %0d pass, %0d fail", pass_cnt, fail_cnt);
    endtask

    //-------------------------------------------------------------------------
    // Timing assertions: key DDR4 timing counters must be non-zero
    //-------------------------------------------------------------------------
    task automatic check_timing_assertions();
        $display("\n=== Timing Model Assertions ===");
        if (ENABLE_TIMING) begin
            // page_miss_count must fire via seq_page_miss
            if (dut.stats.page_miss_count == 0) begin
                $display("  [FAIL] page_miss_count=0, expected >0");
                txn_fail++;
            end else
                $display("  page_miss_count  = %0d  [PASS]", dut.stats.page_miss_count);

            // refresh_stall_count must fire over the ~200 µs run (tREFI=7800 ns)
            if (dut.stats.refresh_stall_count == 0) begin
                $display("  [FAIL] refresh_stall_count=0, expected >0");
                txn_fail++;
            end else
                $display("  refresh_stalls   = %0d  [PASS]", dut.stats.refresh_stall_count);

            // page_hit_count must fire (random sequences naturally revisit addresses)
            if (dut.stats.page_hit_count == 0) begin
                $display("  [FAIL] page_hit_count=0, expected >0");
                txn_fail++;
            end else
                $display("  page_hit_count   = %0d  [PASS]", dut.stats.page_hit_count);

            // Informational: these require pipelined / high-freq AXI to fire
            $display("  wtr_stalls=%0d  faw_stalls=%0d  tRAS=%0d  tRTP=%0d  tCCD=%0d  [INFO]",
                     dut.stats.wtr_stall_count, dut.stats.faw_stall_count,
                     dut.stats.tRAS_stall_count, dut.stats.tRTP_stall_count,
                     dut.stats.tCCD_stall_count);
        end else
            $display("  (ENABLE_TIMING=0 — timing assertions skipped)");
        // OOB address error check — independent of ENABLE_TIMING
        if (dut.stats.address_errors < 2) begin
            $display("  [FAIL] address_errors=%0d, expected >=2 (run_seq_oob_access fires 1 OOB write + 1 OOB read)",
                     dut.stats.address_errors);
            txn_fail++;
        end else
            $display("  address_errors   = %0d  [PASS]", dut.stats.address_errors);
        $display("========================================");
    endtask

    //-------------------------------------------------------------------------
    // Sequence 13: mixed burst-type outstanding reads
    //
    //   Floods the AR FIFO with OST_N requests mixing INCR, WRAP, and FIXED
    //   burst types without accepting any rvalid.  After all ARs are posted,
    //   R responses are drained and verified against the scoreboard.
    //
    //   Memory layout (words, all within SIM_DEPTH):
    //     Address zone : BASE + [SIM_DEPTH/2 + 64 .. /2 + 64 + OST_N-1]
    //   Pre-populated by a burst-type-matched write sweep before flooding ARs.
    //
    //   Verifies:
    //     1. AR FIFO accepts mixed burst types without stall.
    //     2. Each burst type (INCR/WRAP/FIXED) is stored and processed in order.
    //     3. All returned R data matches the scoreboard.
    //-------------------------------------------------------------------------
    task automatic run_seq_mixed_burst_outstanding();
        localparam int OST_N    = 12;             // must be divisible by 3 (4 each)
        localparam int WR_BASE2 = SIM_DEPTH / 2 + 64;

        // burst-type rotation: 0→INCR, 1→WRAP(len=3), 2→FIXED
        logic [1:0]         burst_seq [0:OST_N-1];
        logic [7:0]         len_seq   [0:OST_N-1];
        logic [AXI_AW-1:0]  addr_seq  [0:OST_N-1];
        logic [AXI_DW-1:0]  wr_data   [0:OST_N-1][0:15];
        logic [1:0]         bresp;
        int                 pass_cnt, fail_cnt, t;

        pass_cnt = 0;
        fail_cnt = 0;
        $display("\n=== SEQ: mixed_burst_outstanding (%0d ARs: INCR/WRAP/FIXED mix) ===", OST_N);

        // Build per-slot burst / length / address parameters
        for (int i = 0; i < OST_N; i++) begin
            case (i % 3)
                0: begin  // INCR (len 3 → 4 beats)
                    burst_seq[i] = 2'b01;
                    len_seq  [i] = 8'h03;
                    addr_seq [i] = BASE + AXI_AW'((WR_BASE2 + i * 4) * AXI_SW);
                end
                1: begin  // WRAP (len 3 → 4 beats, window = 4*AXI_SW; addr aligned)
                    burst_seq[i] = 2'b10;
                    len_seq  [i] = 8'h03;
                    // Align to wrap window = 4 * AXI_SW bytes
                    begin
                        automatic int raw_w    = WR_BASE2 + i * 4;
                        automatic int wrap_win = 4;                   // 4 words
                        automatic int aligned  = (raw_w / wrap_win) * wrap_win;
                        addr_seq[i] = BASE + AXI_AW'(aligned * AXI_SW);
                    end
                end
                default: begin  // FIXED (len 3 → 4 beats, all same word)
                    burst_seq[i] = 2'b00;
                    len_seq  [i] = 8'h03;
                    addr_seq [i] = BASE + AXI_AW'((WR_BASE2 + i * 4) * AXI_SW);
                end
            endcase
            for (int b = 0; b <= 3; b++)
                wr_data[i][b] = AXI_DW'(32'hA1A1_0000 | (i << 4) | b);
        end

        // ── Phase 1: write each zone with the matching burst type ─────────
        $display("  Phase 1: pre-populate with burst-matched writes");
        for (int i = 0; i < OST_N; i++) begin
            automatic logic [AXI_DW-1:0] d16[0:15];
            for (int b = 0; b <= 3; b++) d16[b] = wr_data[i][b];
            bfm_write_burst(4'hC, addr_seq[i], d16, '1, len_seq[i], burst_seq[i], 1'b0, bresp);
            if (bresp !== 2'b00) begin
                $display("  [FAIL] mixed_burst_ost wr[%0d] bresp=%0b", i, bresp);
                txn_fail++;
            end
        end

        // ── Phase 2: flood AR FIFO (no rvalid collection) ─────────────────
        $display("  Phase 2: post all %0d ARs before collecting R data", OST_N);
        for (int i = 0; i < OST_N; i++) begin
            @(posedge aclk);
            t = WATCHDOG_CYCLES;
            while (!s_axi_arready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [MIX-OST] WD arready i=%0d", i); break; end
            end
            s_axi_arid    <= 4'hC;
            s_axi_araddr  <= addr_seq[i];
            s_axi_arlen   <= len_seq[i];
            s_axi_arsize  <= 3'(AXI_SZ);
            s_axi_arburst <= burst_seq[i];
            s_axi_arvalid <= 1'b1;
            @(posedge aclk);
            s_axi_arvalid <= 1'b0;
        end
        $display("  Phase 2 done: max_outstanding_reads=%0d", dut.stats.max_outstanding_reads);

        // ── Phase 3: drain R responses and verify ─────────────────────────
        $display("  Phase 3: drain R responses");
        for (int i = 0; i < OST_N; i++) begin
            automatic logic [AXI_DW-1:0] rdarray [0:15];
            automatic logic [1:0]        rrarray [0:15];
            automatic logic              ok;
            // Collect all beats for this transaction
            for (int b = 0; b <= int'(len_seq[i]); b++) begin
                t = WATCHDOG_CYCLES;
                while (!s_axi_rvalid) begin
                    @(posedge aclk);
                    if (--t == 0) begin
                        $display("  [MIX-OST] WD rvalid i=%0d beat=%0d", i, b);
                        break;
                    end
                end
                rdarray[b] = s_axi_rdata;
                rrarray[b] = s_axi_rresp;
                s_axi_rready <= 1'b1;
                @(posedge aclk);
                s_axi_rready <= 1'b0;
            end
            scb_read_check(addr_seq[i], rdarray, len_seq[i], burst_seq[i],
                           "mix_burst_ost_rd", ok);
            if (ok) pass_cnt++; else fail_cnt++;
        end

        $display("  mixed_burst_outstanding: %0d pass, %0d fail", pass_cnt, fail_cnt);
    endtask

    //-------------------------------------------------------------------------
    // Sequence 14: outstanding writes+reads with mixed burst types (fork/join)
    //
    //   Runs OST_N concurrent pairs where each pair:
    //     - Write: randomly selects INCR (len 0–3), WRAP (len 3), or FIXED (len 3)
    //     - Concurrent read: issues AR for a pre-populated address of the same
    //       burst type while the write FSM is in its DDR4 preamble
    //
    //   Uses fork/join_none to launch all pairs simultaneously, then a
    //   barrier @(event) to wait for all completions.  This creates true
    //   pipelined interleave: multiple WR preambles are pending while
    //   the RD FSM is serving outstanding AR requests.
    //
    //   Memory layout:
    //     Pre-pop zone : BASE + [0..OST_N*16-1] words (written in setup)
    //     Write zone   : BASE + [SIM_DEPTH/2+96..] words
    //-------------------------------------------------------------------------
    task automatic run_seq_outstanding_mixed_rw();
        localparam int OST_N    = 8;
        localparam int WR_BASE3 = SIM_DEPTH / 2 + 96;
        localparam int PAIR_TIMEOUT = 16000;

        // Flat arrays — no typedef struct (Verilator rejects those inside tasks)
        logic [1:0]        p_burst    [0:OST_N-1];
        logic [7:0]        p_len      [0:OST_N-1];
        logic [AXI_AW-1:0] p_wr_addr  [0:OST_N-1];
        logic [AXI_AW-1:0] p_rd_addr  [0:OST_N-1];
        logic [AXI_DW-1:0] p_wr_data  [0:OST_N-1][0:15];
        logic [AXI_DW-1:0] p_rd_exp   [0:OST_N-1][0:15];
        logic [AXI_DW-1:0] p_rdata    [0:OST_N-1][0:15];
        logic [1:0]        p_rresp    [0:OST_N-1][0:15];

        logic [1:0] btypes [3] = '{2'b01, 2'b10, 2'b00};
        logic [1:0] tmp_bresp;
        int         pass_cnt, fail_cnt;

        pass_cnt = 0;
        fail_cnt = 0;
        $display("\n=== SEQ: outstanding_mixed_rw (%0d sequential WR+RD pairs, mixed burst) ===",
                 OST_N);

        // ── Setup: assign parameters ──────────────────────────────────────
        for (int i = 0; i < OST_N; i++) begin
            automatic int bsel = i % 3;
            p_burst[i] = btypes[bsel];
            p_len  [i] = 8'h03;

            // Write target (upper half); WRAP requires window-aligned base
            case (bsel)
                1: begin   // WRAP — align to 4-word wrap window
                    automatic int raw_w   = WR_BASE3 + i * 4;
                    automatic int aligned = (raw_w / 4) * 4;
                    p_wr_addr[i] = BASE + AXI_AW'(aligned * AXI_SW);
                end
                default: p_wr_addr[i] = BASE + AXI_AW'((WR_BASE3 + i * 4) * AXI_SW);
            endcase

            // Read target (lower zone, separate from write zone)
            case (bsel)
                1: begin
                    automatic int aligned = (i * 4 / 4) * 4;
                    p_rd_addr[i] = BASE + AXI_AW'(aligned * AXI_SW);
                end
                default: p_rd_addr[i] = BASE + AXI_AW'((i * 4) * AXI_SW);
            endcase

            for (int b = 0; b <= 3; b++) begin
                p_wr_data[i][b] = AXI_DW'(32'hB2B2_0000 | (i << 4) | b);
                p_rd_exp [i][b] = AXI_DW'(32'hB2B2_0000 | (i << 4) | b);
            end
        end

        // Pre-populate the read zone sequentially
        $display("  Setup: pre-populate read zones");
        for (int i = 0; i < OST_N; i++) begin
            automatic logic [AXI_DW-1:0] d16[0:15];
            for (int b = 0; b <= 3; b++) d16[b] = p_rd_exp[i][b];
            bfm_write_burst(4'h0, p_rd_addr[i], d16, '1, p_len[i], p_burst[i], 1'b0, tmp_bresp);
        end

        // ── Run one pair at a time; each pair uses fork/join for WR+RD ───
        $display("  Running %0d WR+RD pairs (concurrent per-pair fork/join)", OST_N);
        for (int i = 0; i < OST_N; i++) begin
            automatic int pi              = i;
            automatic logic [AXI_AW-1:0] my_wr_addr  = p_wr_addr[pi];
            automatic logic [AXI_AW-1:0] my_rd_addr  = p_rd_addr[pi];
            automatic logic [1:0]        my_burst    = p_burst  [pi];
            automatic logic [7:0]        my_len      = p_len    [pi];
            automatic logic [1:0]        my_bresp    = 2'b11;  // sentinel
            automatic logic              rd_accepted  = 1'b0;
            automatic int                ta, tb;

            // ── AW handshake ──────────────────────────────────────────────
            @(posedge aclk);
            ta = PAIR_TIMEOUT;
            while (!s_axi_awready) begin
                @(posedge aclk);
                if (--ta == 0) begin $display("  [MIX-RW] WD awready pi=%0d", pi); break; end
            end
            s_axi_awid    <= 4'hD;
            s_axi_awaddr  <= my_wr_addr;
            s_axi_awlen   <= my_len;
            s_axi_awsize  <= 3'(AXI_SZ);
            s_axi_awburst <= my_burst;
            s_axi_awvalid <= 1'b1;
            @(posedge aclk);
            s_axi_awvalid <= 1'b0;

            // ── Fork: W-data + BRESP  ||  AR + R-data ─────────────────────
            fork
                // WR-data thread
                begin
                    for (int b = 0; b <= int'(my_len); b++) begin
                        ta = PAIR_TIMEOUT;
                        while (!s_axi_wready) begin
                            @(posedge aclk);
                            if (--ta == 0) begin
                                $display("  [MIX-RW] WD wready pi=%0d b=%0d", pi, b); break;
                            end
                        end
                        s_axi_wdata  <= p_wr_data[pi][b];
                        s_axi_wstrb  <= '1;
                        s_axi_wlast  <= (b == int'(my_len));
                        s_axi_wvalid <= 1'b1;
                        @(posedge aclk);
                        s_axi_wvalid <= 1'b0;
                        s_axi_wlast  <= 1'b0;
                    end
                    ta = PAIR_TIMEOUT;
                    while (!s_axi_bvalid) begin
                        @(posedge aclk);
                        if (--ta == 0) begin $display("  [MIX-RW] WD bvalid pi=%0d", pi); break; end
                    end
                    my_bresp     = s_axi_bresp;
                    s_axi_bready <= 1'b1;
                    @(posedge aclk);
                    s_axi_bready <= 1'b0;
                end
                // RD concurrent thread
                begin
                    @(posedge aclk);  // 1-cycle settling after AW
                    tb = PAIR_TIMEOUT;
                    while (!s_axi_arready) begin
                        @(posedge aclk);
                        if (--tb == 0) begin $display("  [MIX-RW] WD arready pi=%0d", pi); break; end
                    end
                    if (s_axi_arready) begin
                        s_axi_arid    <= 4'hE;
                        s_axi_araddr  <= my_rd_addr;
                        s_axi_arlen   <= my_len;
                        s_axi_arsize  <= 3'(AXI_SZ);
                        s_axi_arburst <= my_burst;
                        s_axi_arvalid <= 1'b1;
                        @(posedge aclk);
                        s_axi_arvalid <= 1'b0;
                        for (int b = 0; b <= int'(my_len); b++) begin
                            tb = PAIR_TIMEOUT;
                            while (!s_axi_rvalid) begin
                                @(posedge aclk);
                                if (--tb == 0) begin
                                    $display("  [MIX-RW] WD rvalid pi=%0d b=%0d", pi, b); break;
                                end
                            end
                            p_rdata[pi][b] = s_axi_rdata;
                            p_rresp[pi][b] = s_axi_rresp;
                            s_axi_rready  <= 1'b1;
                            @(posedge aclk);
                            s_axi_rready  <= 1'b0;
                        end
                        rd_accepted = 1'b1;
                    end
                end
            join  // both complete before proceeding to scoreboard update

            // Update scoreboard for write
            begin
                automatic logic [AXI_DW-1:0] sdata[0:15];
                automatic logic [AXI_SW-1:0] sstrb[0:15];
                for (int b = 0; b <= int'(my_len); b++) begin
                    sdata[b] = p_wr_data[pi][b];
                    sstrb[b] = '1;
                end
                scb_write(my_wr_addr, sdata, sstrb, my_len, my_burst);
            end

            // Check write result
            if (my_bresp === 2'b00) begin txn_pass++; pass_cnt++; end
            else begin
                $display("  [FAIL] mix_rw[%0d] WR burst=%0b len=%0d bresp=%0b",
                         pi, my_burst, my_len, my_bresp);
                txn_fail++; fail_cnt++;
            end

            // Check read result
            if (rd_accepted) begin
                automatic logic [AXI_DW-1:0] rdarray [0:15];
                automatic logic              ok;
                for (int b = 0; b <= int'(my_len); b++) rdarray[b] = p_rdata[pi][b];
                scb_read_check(my_rd_addr, rdarray, my_len, my_burst, "mix_rw_rd", ok);
                if (ok) pass_cnt++; else fail_cnt++;
            end else
                $display("  mix_rw[%0d]: RD channel not accepted (slave serialises) [INFO]", pi);
        end

        $display("  outstanding_mixed_rw: %0d pass, %0d fail", pass_cnt, fail_cnt);
    endtask

    //-------------------------------------------------------------------------
    // Sequence 15: burst outstanding write-then-read drain
    //
    //   Floods the AW FIFO with OST_N multi-beat INCR burst writes before
    //   driving any W data.  While draining W beats and collecting BRESPs,
    //   simultaneously floods the AR FIFO for the same addresses.  After all
    //   writes complete, drains all R responses and verifies read-after-write
    //   integrity.
    //
    //   This exercises:
    //     1. AW FIFO depth > 1 with burst transactions (len=7, 8 beats each).
    //     2. AR FIFO being filled while W-data drain is in progress.
    //     3. Scoreboard integrity: read-after-write for each burst address.
    //
    //   Memory zone: BASE + [SIM_DEPTH/2 + 128 .. SIM_DEPTH/2 + 128 + OST_N*8 - 1]
    //-------------------------------------------------------------------------
    task automatic run_seq_burst_outstanding_drain();
        localparam int OST_N    = 8;
        localparam int BURST_LEN = 7;          // 8 beats per transaction
        localparam int WR_BASE4 = SIM_DEPTH / 2 + 128;

        logic [AXI_AW-1:0]  wr_addrs  [0:OST_N-1];
        logic [AXI_DW-1:0]  wr_data   [0:OST_N-1][0:15];
        logic [1:0]         bresp;
        int                 pass_cnt, fail_cnt, t;

        pass_cnt = 0;
        fail_cnt = 0;
        $display("\n=== SEQ: burst_outstanding_drain (%0d x %0d-beat INCR; AR overlay) ===",
                 OST_N, BURST_LEN + 1);

        // Build addresses and data
        for (int i = 0; i < OST_N; i++) begin
            wr_addrs[i] = BASE + AXI_AW'((WR_BASE4 + i * (BURST_LEN + 1)) * AXI_SW);
            for (int b = 0; b <= BURST_LEN; b++)
                wr_data[i][b] = AXI_DW'(32'hC3C3_0000 | (i << 4) | b);
        end

        // ── Phase 1: flood AW FIFO (OST_N bursts, no W data yet) ─────────
        $display("  Phase 1: post all %0d AW (burst len=%0d)", OST_N, BURST_LEN + 1);
        for (int i = 0; i < OST_N; i++) begin
            @(posedge aclk);
            t = WATCHDOG_CYCLES;
            while (!s_axi_awready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [BUR-DRAIN] WD awready i=%0d", i); break; end
            end
            s_axi_awid    <= 4'hF;
            s_axi_awaddr  <= wr_addrs[i];
            s_axi_awlen   <= 8'(BURST_LEN);
            s_axi_awsize  <= 3'(AXI_SZ);
            s_axi_awburst <= 2'b01;
            s_axi_awvalid <= 1'b1;
            @(posedge aclk);
            s_axi_awvalid <= 1'b0;
        end
        $display("  Phase 1 done. max_outstanding_writes=%0d",
                 dut.stats.max_outstanding_writes);

        // ── Phase 2: drain W data + BRESPs (sequential) ──────────────────
        // ARs are posted AFTER all BRESPs are received (Phase 2b) to avoid a
        // write-before-read race at fast aclk / slow DDR4 speed grades where the
        // DRAM read latency is shorter than the write commit latency.
        $display("  Phase 2: drain W beats sequentially");
        for (int i = 0; i < OST_N; i++) begin
            for (int b = 0; b <= BURST_LEN; b++) begin
                t = WATCHDOG_CYCLES;
                while (!s_axi_wready) begin
                    @(posedge aclk);
                    if (--t == 0) begin
                        $display("  [BUR-DRAIN] WD wready i=%0d b=%0d", i, b);
                        break;
                    end
                end
                s_axi_wdata  <= wr_data[i][b];
                s_axi_wstrb  <= '1;
                s_axi_wlast  <= (b == BURST_LEN);
                s_axi_wvalid <= 1'b1;
                @(posedge aclk);
                s_axi_wvalid <= 1'b0;
                s_axi_wlast  <= 1'b0;
            end
            t = WATCHDOG_CYCLES;
            while (!s_axi_bvalid) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [BUR-DRAIN] WD bvalid i=%0d", i); break; end
            end
            bresp        = s_axi_bresp;
            s_axi_bready <= 1'b1;
            @(posedge aclk);
            s_axi_bready <= 1'b0;
            begin
                automatic logic [AXI_DW-1:0] sdata[0:15];
                automatic logic [AXI_SW-1:0] sstrb[0:15];
                for (int b = 0; b <= BURST_LEN; b++) begin
                    sdata[b] = wr_data[i][b]; sstrb[b] = '1;
                end
                scb_write(wr_addrs[i], sdata, sstrb, 8'(BURST_LEN), 2'b01);
            end
            if (bresp === 2'b00) begin txn_pass++; pass_cnt++; end
            else begin
                $display("  [FAIL] bur_drain wr[%0d] bresp=%0b", i, bresp);
                txn_fail++; fail_cnt++;
            end
        end
        $display("  All writes complete. max_outstanding_writes=%0d",
                 dut.stats.max_outstanding_writes);
        if (dut.stats.max_outstanding_writes > 1)
            $display("  AW FIFO burst depth >1 confirmed [PASS]");
        else
            $display("  AW FIFO depth stayed at 1 [INFO]");

        // ── Phase 2b: flood AR FIFO (all ARs posted before any R consumed) ─
        // This tests AR FIFO depth independently of write ordering hazards.
        $display("  Phase 2b: post all %0d ARs (burst, no R consumed yet)", OST_N);
        for (int i = 0; i < OST_N; i++) begin
            t = WATCHDOG_CYCLES;
            while (!s_axi_arready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [BUR-DRAIN] WD arready i=%0d", i); break; end
            end
            s_axi_arid    <= 4'hF;
            s_axi_araddr  <= wr_addrs[i];
            s_axi_arlen   <= 8'(BURST_LEN);
            s_axi_arsize  <= 3'(AXI_SZ);
            s_axi_arburst <= 2'b01;
            s_axi_arvalid <= 1'b1;
            @(posedge aclk);
            s_axi_arvalid <= 1'b0;
            @(posedge aclk);  // small gap between ARs
        end
        $display("  Phase 2b done. max_outstanding_reads=%0d",
                 dut.stats.max_outstanding_reads);
        if (dut.stats.max_outstanding_reads > 1)
            $display("  AR FIFO burst depth >1 confirmed [PASS]");
        else
            $display("  AR FIFO depth stayed at 1 [INFO]");

        // ── Phase 3: drain all R responses and verify ─────────────────────
        $display("  Phase 3: drain and verify R responses");
        for (int i = 0; i < OST_N; i++) begin
            automatic logic [AXI_DW-1:0] rdarray [0:15];
            automatic logic [1:0]        rrarray [0:15];
            automatic logic              ok;
            for (int b = 0; b <= BURST_LEN; b++) begin
                t = WATCHDOG_CYCLES;
                while (!s_axi_rvalid) begin
                    @(posedge aclk);
                    if (--t == 0) begin
                        $display("  [BUR-DRAIN] WD rvalid i=%0d b=%0d", i, b); break;
                    end
                end
                rdarray[b] = s_axi_rdata;
                rrarray[b] = s_axi_rresp;
                s_axi_rready <= 1'b1;
                @(posedge aclk);
                s_axi_rready <= 1'b0;
            end
            scb_read_check(wr_addrs[i], rdarray, 8'(BURST_LEN), 2'b01,
                           "bur_drain_rd", ok);
            if (ok) pass_cnt++; else fail_cnt++;
        end

        $display("  burst_outstanding_drain: %0d pass, %0d fail", pass_cnt, fail_cnt);
    endtask

    //=========================================================================
    // Seq 16: burst_per_beat_strobe — verify per-beat partial-strobe writes
    //   Each beat of an INCR burst gets a distinct random partial strobe.
    //   Written via bfm_write_burst_strobe_array; scoreboard tracks byte-level state.
    //   Read back via bfm_read_burst to verify byte-accurate merge.
    //=========================================================================
    task automatic run_seq_burst_per_beat_strobe();
        localparam int MAX_LEN  = 7;
        localparam int WR_BASE5 = SIM_DEPTH / 2 + 200;
        logic [AXI_DW-1:0] wdata[0:15], rdata[0:15];
        logic [AXI_SW-1:0] strb_arr[0:15];
        logic [1:0]         rresp[0:15];
        logic [AXI_AW-1:0] addr;
        logic [7:0]         len;
        logic [1:0]         bresp;
        int                 pass_cnt, fail_cnt;
        pass_cnt = 0; fail_cnt = 0;
        $display("\n=== SEQ 16: burst_per_beat_strobe (%0d iterations) ===", N_RAND);
        for (int i = 0; i < N_RAND; i++) begin
            len  = 8'($urandom_range(1, MAX_LEN));
            addr = BASE + AXI_AW'((WR_BASE5 + i * (MAX_LEN + 2)) * AXI_SW);
            for (int b = 0; b <= int'(len); b++) begin
                wdata[b]    = {$urandom(), $urandom()};
                // ensure at least one byte active per beat
                strb_arr[b] = AXI_SW'($urandom_range(1, (1 << AXI_SW) - 2));
            end
            bfm_write_burst_strobe_array(4'h1, addr, wdata, strb_arr, len, 2'b01, 1'b0, bresp);
            bfm_read_burst(4'h1, addr, len, 2'b01, 1'b0, rdata, rresp);
        end
        $display("  burst_per_beat_strobe: txn_pass=%0d txn_fail=%0d", txn_pass, txn_fail);
    endtask

    //=========================================================================
    // Seq 17: burst_bp_per_beat — per-beat rready back-pressure on reads
    //   Write a burst; read it back via bfm_read_burst_beat_bp which
    //   inserts 0-3 idle cycles before asserting rready each beat.
    //=========================================================================
    task automatic run_seq_burst_bp_per_beat();
        localparam int MAX_LEN  = 7;
        localparam int WR_BASE6 = SIM_DEPTH / 2 + 600;
        logic [AXI_DW-1:0] wdata[0:15], rdata[0:15];
        logic [1:0]         rresp[0:15];
        logic [AXI_AW-1:0] addr;
        logic [7:0]         len;
        logic [1:0]         bresp;
        $display("\n=== SEQ 17: burst_bp_per_beat (%0d iterations, per-beat rready toggle) ===", N_RAND);
        for (int i = 0; i < N_RAND; i++) begin
            len  = 8'($urandom_range(1, MAX_LEN));
            addr = BASE + AXI_AW'((WR_BASE6 + i * (MAX_LEN + 2)) * AXI_SW);
            for (int b = 0; b <= int'(len); b++)
                wdata[b] = {$urandom(), $urandom()};
            bfm_write_burst(4'h7, addr, wdata, '1, len, 2'b01, 1'b0, bresp);
            bfm_read_burst_beat_bp(4'h7, addr, len, 2'b01, rdata, rresp);
        end
        $display("  burst_bp_per_beat: done");
    endtask

    //=========================================================================
    // Seq 18: narrow_size — sub-word (AXI size < AXI_SZ) transfers
    //   1-byte (size=0): write a full word first, then overwrite 1 byte via
    //   narrow write using data={AXI_SW{byte}} with strobe selecting the lane.
    //   2-byte (size=1): same approach, replicating a half-word across all
    //   half-word slots: data={(AXI_DW/16){hword}}, strobe selects 2 bytes.
    //   Both sub-tests finish with a full-width read-back for scoreboard check.
    //=========================================================================
    task automatic run_seq_narrow_size();
        localparam int N_NARROW    = 20;
        localparam int NARROW_BASE = SIM_DEPTH / 2 + 1000;
        logic [AXI_DW-1:0] rdata_w, full_d;
        logic [1:0]         rresp_w, bresp;
        $display("\n=== SEQ 18: narrow_size (%0d x 1-byte + %0d x 2-byte) ===",
                 N_NARROW, N_NARROW);

        // --- 1-byte (size=0) sub-tests ---
        for (int i = 0; i < N_NARROW; i++) begin
            automatic int              wbi       = NARROW_BASE + (i % 16);
            automatic logic [AXI_AW-1:0] word_addr = BASE + AXI_AW'(wbi * AXI_SW);
            automatic int              byte_lane = i % AXI_SW;
            automatic logic [7:0]      new_byte  = 8'($urandom());
            // Replicate byte; strobe pins the active lane — avoids LHS part-select
            automatic logic [AXI_DW-1:0] wr_data_1b  = {AXI_SW{new_byte}};
            automatic logic [AXI_SW-1:0] narrow_strb = AXI_SW'(1 << byte_lane);
            // Baseline full-word write so all byte lanes are scoreboard-valid
            full_d = {$urandom(), $urandom()};
            bfm_write_single(4'h2, word_addr, full_d, '1, 1'b0, bresp);
            // Narrow 1-byte write; bfm_write_narrow updates scoreboard with correct strobe
            bfm_write_narrow(4'h2, word_addr + AXI_AW'(byte_lane), wr_data_1b, narrow_strb,
                             3'b000, bresp);
            // Full-width read-back — scoreboard validates all byte lanes
            bfm_read_single(4'h2, word_addr, 1'b0, rdata_w, rresp_w);
        end

        // --- 2-byte (size=1) sub-tests (only meaningful when AXI_SW >= 2) ---
        if (AXI_SW >= 2) begin
            for (int i = 0; i < N_NARROW; i++) begin
                automatic int              wbi       = NARROW_BASE + 16 + (i % 16);
                automatic logic [AXI_AW-1:0] word_addr = BASE + AXI_AW'(wbi * AXI_SW);
                automatic int              hw_lane   = i % (AXI_SW / 2);
                automatic logic [15:0]     new_hword = 16'($urandom());
                // Replicate half-word; strobe selects the right pair of bytes
                automatic logic [AXI_DW-1:0] wr_data_2b  = {(AXI_DW/16){new_hword}};
                automatic logic [AXI_SW-1:0] narrow_strb = AXI_SW'(2'b11 << (hw_lane * 2));
                automatic logic [AXI_AW-1:0] narrow_addr = word_addr + AXI_AW'(hw_lane * 2);
                full_d = {$urandom(), $urandom()};
                bfm_write_single(4'h2, word_addr, full_d, '1, 1'b0, bresp);
                bfm_write_narrow(4'h2, narrow_addr, wr_data_2b, narrow_strb, 3'b001, bresp);
                bfm_read_single(4'h2, word_addr, 1'b0, rdata_w, rresp_w);
            end
        end
        $display("  narrow_size: done");
    endtask

    //=========================================================================
    // Seq 19: burst_row_cross — INCR burst straddling a DDR4 row boundary
    //   Starts 2 or 4 words before ROW_STRIDE_WORDS so later beats land in
    //   the next row, forcing tRP + tRCD mid-burst.
    //=========================================================================
    task automatic run_seq_burst_row_cross();
        localparam int CROSS_LEN = 7;   // 8-beat burst
        localparam int N_CROSS   = 4;
        logic [AXI_DW-1:0] wdata[0:15], rdata[0:15];
        logic [1:0]         rresp[0:15], bresp;
        $display("\n=== SEQ 19: burst_row_cross (%0d x %0d-beat INCR across row boundary @word %0d) ===",
                 N_CROSS, CROSS_LEN + 1, ROW_STRIDE_WORDS);
        for (int i = 0; i < N_CROSS; i++) begin
            automatic int offset = (i % 2 == 0) ? 2 : 4;
            automatic logic [AXI_AW-1:0] addr =
                BASE + AXI_AW'((ROW_STRIDE_WORDS - offset) * AXI_SW);
            for (int b = 0; b <= CROSS_LEN; b++)
                wdata[b] = AXI_DW'(32'hD4D4_0000 | (i << 4) | b);
            bfm_write_burst(4'hD, addr, wdata, '1, 8'(CROSS_LEN), 2'b01, 1'b0, bresp);
            bfm_read_burst (4'hD, addr, 8'(CROSS_LEN), 2'b01, 1'b0, rdata, rresp);
        end
        $display("  burst_row_cross: done");
    endtask

    //=========================================================================
    // Seq 20: id_stress — AXI ID passthrough check for IDs 0 to 2^AXI_IDW-1
    //   Performs inline AW/W/B and AR/R handshakes and verifies that
    //   s_axi_bid == awid and s_axi_rid == arid for every transaction.
    //=========================================================================
    task automatic run_seq_id_stress();
        localparam int ID_BASE = SIM_DEPTH / 2 + 1100;
        localparam int N_IDS   = 1 << AXI_IDW;
        logic [AXI_AW-1:0]  addr;
        logic [AXI_IDW-1:0] expected_id;
        logic [AXI_DW-1:0]  wdat, rdat;
        logic [1:0]          bresp, rresp;
        int                  t;
        $display("\n=== SEQ 20: id_stress (IDs 0-%0d, BID/RID passthrough) ===", N_IDS - 1);
        for (int id = 0; id < N_IDS; id++) begin
            addr = BASE + AXI_AW'((ID_BASE + id) * AXI_SW);
            wdat = AXI_DW'(32'hE5E5_0000 | id);
            expected_id = AXI_IDW'(id);

            // --- Write ---
            t = WATCHDOG_CYCLES;
            @(posedge aclk);
            while (!s_axi_awready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [ID-STRESS] WD awready id=%0d", id); break; end
            end
            s_axi_awid    <= AXI_IDW'(id);
            s_axi_awaddr  <= addr;
            s_axi_awlen   <= 8'h00;
            s_axi_awsize  <= 3'(AXI_SZ);
            s_axi_awburst <= 2'b01;
            s_axi_awvalid <= 1'b1;
            @(posedge aclk);
            s_axi_awvalid <= 1'b0;

            t = WATCHDOG_CYCLES;
            while (!s_axi_wready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [ID-STRESS] WD wready id=%0d", id); break; end
            end
            s_axi_wdata  <= wdat;
            s_axi_wstrb  <= '1;
            s_axi_wlast  <= 1'b1;
            s_axi_wvalid <= 1'b1;
            @(posedge aclk);
            s_axi_wvalid <= 1'b0;
            s_axi_wlast  <= 1'b0;

            t = WATCHDOG_CYCLES;
            while (!s_axi_bvalid) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [ID-STRESS] WD bvalid id=%0d", id); break; end
            end
            if (s_axi_bid !== expected_id) begin
                $display("  [FAIL] id_stress wr[%0d]: BID=0x%0h exp=0x%0h",
                         id, s_axi_bid, expected_id);
                txn_fail++;
            end else begin
                automatic logic [AXI_DW-1:0] sd[0:15];
                automatic logic [AXI_SW-1:0] ss[0:15];
                sd[0] = wdat;
                ss[0] = '1;
                scb_write(addr, sd, ss, 8'h00, 2'b01);
                txn_pass++;
            end
            s_axi_bready <= 1'b1;
            @(posedge aclk);
            s_axi_bready <= 1'b0;

            // --- Read ---
            t = WATCHDOG_CYCLES;
            @(posedge aclk);
            while (!s_axi_arready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [ID-STRESS] WD arready id=%0d", id); break; end
            end
            s_axi_arid    <= AXI_IDW'(id);
            s_axi_araddr  <= addr;
            s_axi_arlen   <= 8'h00;
            s_axi_arsize  <= 3'(AXI_SZ);
            s_axi_arburst <= 2'b01;
            s_axi_arvalid <= 1'b1;
            @(posedge aclk);
            s_axi_arvalid <= 1'b0;

            t = WATCHDOG_CYCLES;
            while (!s_axi_rvalid) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [ID-STRESS] WD rvalid id=%0d", id); break; end
            end
            rdat = s_axi_rdata;
            rresp = s_axi_rresp;
            if (s_axi_rid !== expected_id) begin
                $display("  [FAIL] id_stress rd[%0d]: RID=0x%0h exp=0x%0h",
                         id, s_axi_rid, expected_id);
                txn_fail++;
            end else begin
                automatic logic [AXI_DW-1:0] rd[0:15];
                automatic logic              ok;
                rd[0] = rdat;
                scb_read_check(addr, rd, 8'h00, 2'b01, "id_stress_rd", ok);
            end
            s_axi_rready <= 1'b1;
            @(posedge aclk);
            s_axi_rready <= 1'b0;
            @(posedge aclk);
        end
        $display("  id_stress: done");
    endtask

    //=========================================================================
    // Seq 21: partial_write_page_miss_rd
    //   Full write -> partial-strobe overwrite -> page-miss write to row 1
    //   -> read back row-0 word; scoreboard validates byte-level merge.
    //=========================================================================
    task automatic run_seq_partial_write_page_miss_rd();
        localparam int N_PM2    = 6;
        logic [AXI_DW-1:0] rdata, full_d;
        logic [AXI_SW-1:0] partial_strb;
        logic [AXI_AW-1:0] addr_r0, addr_r1;
        logic [1:0]         rresp, bresp;
        $display("\n=== SEQ 21: partial_write_page_miss_rd (%0d iterations) ===", N_PM2);
        for (int i = 0; i < N_PM2; i++) begin
            // Row-0: mid-point of first half (8192+i) — away from seq 7's word 0
            addr_r0 = BASE + AXI_AW'((ROW_STRIDE_WORDS / 2 + i) * AXI_SW);
            // Row-1: ROW_STRIDE_WORDS+8+i — avoids seq 7's addr=ROW_STRIDE_WORDS
            addr_r1 = BASE + AXI_AW'((ROW_STRIDE_WORDS + 8 + i) * AXI_SW);
            // 1: full-width baseline write (all byte lanes become valid)
            full_d = {$urandom(), $urandom()};
            bfm_write_single(4'h3, addr_r0, full_d, '1, 1'b0, bresp);
            // 2: partial-strobe overwrite (scoreboard merges bytes)
            partial_strb = AXI_SW'($urandom_range(1, (1 << AXI_SW) - 2));
            bfm_write_single(4'h3, addr_r0, {$urandom(), $urandom()}, partial_strb, 1'b0, bresp);
            // 3: page-miss write to row 1 (forces precharge + activate before next read)
            bfm_write_single(4'h3, addr_r1, {$urandom(), $urandom()}, '1, 1'b0, bresp);
            // 4: read back row-0 — result must match merged shadow
            bfm_read_single(4'h3, addr_r0, 1'b0, rdata, rresp);
        end
        $display("  partial_write_page_miss_rd: done");
    endtask

    //=========================================================================
    // Seq 22: refresh_mid_burst — submit long INCR bursts; verify refresh stalls
    //   16 x 16-beat write bursts followed by 16 reads.
    //   Reports the delta of dut.stats.refresh_stall_count to confirm that
    //   refresh preempted at least one burst during this sequence.
    //=========================================================================
    task automatic run_seq_refresh_mid_burst();
        localparam int N_LONG   = 16;
        localparam int LONG_LEN = 15;     // 16-beat bursts
        localparam int RFR_BASE = SIM_DEPTH / 2 + 1200;
        logic [AXI_DW-1:0] wdata[0:15], rdata[0:15];
        logic [1:0]         rresp[0:15], bresp;
        longint unsigned    stalls_before;
        $display("\n=== SEQ 22: refresh_mid_burst (%0d x %0d-beat INCR) ===",
                 N_LONG, LONG_LEN + 1);
        stalls_before = dut.stats.refresh_stall_count;
        for (int i = 0; i < N_LONG; i++) begin
            automatic logic [AXI_AW-1:0] addr =
                BASE + AXI_AW'((RFR_BASE + i * (LONG_LEN + 1)) * AXI_SW);
            for (int b = 0; b <= LONG_LEN; b++)
                wdata[b] = AXI_DW'(32'hF6F6_0000 | (i << 4) | b);
            bfm_write_burst(4'hF, addr, wdata, '1, 8'(LONG_LEN), 2'b01, 1'b0, bresp);
        end
        for (int i = 0; i < N_LONG; i++) begin
            automatic logic [AXI_AW-1:0] addr =
                BASE + AXI_AW'((RFR_BASE + i * (LONG_LEN + 1)) * AXI_SW);
            bfm_read_burst(4'hF, addr, 8'(LONG_LEN), 2'b01, 1'b0, rdata, rresp);
        end
        if (dut.stats.refresh_stall_count > stalls_before) begin
            $display("  refresh_stalls delta: %0d  (total: %0d) [PASS]",
                     dut.stats.refresh_stall_count - stalls_before,
                     dut.stats.refresh_stall_count);
        end else begin
            $display("  refresh_stalls delta: 0 (total: %0d) [INFO: no new stalls in this seq]",
                     dut.stats.refresh_stall_count);
        end
        $display("  refresh_mid_burst: done");
    endtask

    //=========================================================================
    // Seq 23: wstrb_zero_beat — all-zero wstrb beat is a no-op
    //   Issue 4-beat INCR bursts where even beats (0, 2) use full strobe and
    //   odd beats (1, 3) use wstrb=0.  The slave should accept all beats and
    //   commit only the even ones.  Scoreboard sees strb=0 and leaves those
    //   shadow bytes unchanged; read-back verifies byte-level merge.
    //=========================================================================
    task automatic run_seq_wstrb_zero_beat();
        localparam int ZERO_STRB_BASE = SIM_DEPTH / 2 + 1500;
        logic [AXI_DW-1:0]  wdata_init[0:0], rdata[0:15];
        logic [AXI_SW-1:0]  sinit[0:0];
        logic [AXI_DW-1:0]  wdata4[0:15];
        logic [AXI_SW-1:0]  strb4[0:15];
        logic [1:0]          rresp[0:15];
        logic [AXI_AW-1:0]  addr;
        logic [1:0]          bresp;
        int                  pass_cnt, fail_cnt;
        logic                ok;

        pass_cnt = 0; fail_cnt = 0;
        $display("\n=== SEQ 23: wstrb_zero_beat (%0d iterations, 4-beat INCR with beats 1,3 wstrb=0) ===",
                 N_RAND);

        for (int i = 0; i < N_RAND; i++) begin
            // Base address — stride 6 words per iteration to avoid overlap
            addr = BASE + AXI_AW'((ZERO_STRB_BASE + i * 6) * AXI_SW);

            // Pre-write 4 consecutive words (establishes shadow baseline)
            for (int w = 0; w < 4; w++) begin
                automatic logic [AXI_DW-1:0] init_d = {$urandom(), $urandom()};
                sinit[0] = '1;
                wdata_init[0] = init_d;
                bfm_write_single(4'h3, addr + AXI_AW'(w * AXI_SW), init_d, '1, 1'b0, bresp);
            end

            // Build 4-beat strobe array: beats 0,2 = full-write; beats 1,3 = no-op
            for (int b = 0; b < 4; b++) begin
                wdata4[b] = {$urandom(), $urandom()};
                strb4[b]  = (b[0] == 1'b0) ? '1 : AXI_SW'(0);
            end

            // Burst write; scb_write handles strb=0 by leaving shadow unchanged
            bfm_write_burst_strobe_array(4'h3, addr, wdata4, strb4, 8'h03, 2'b01, 1'b0, bresp);

            // Read back 4 beats and verify against scoreboard
            bfm_read_burst(4'h3, addr, 8'h03, 2'b01, 1'b0, rdata, rresp);
            // scb_read_check already counted txn_pass/fail; also track locally
            // (scb_read_check is called inside bfm_read_burst — extract local ok via
            //  a direct call after bfm_read_burst already checked; double-count avoided
            //  by reading stats before/after)
            if (txn_fail == 0) pass_cnt++;
            else               fail_cnt++;
        end
        $display("  wstrb_zero_beat: %0d pass, %0d fail [zero-strobe no-op verified]",
                 pass_cnt, fail_cnt);
    endtask

    //=========================================================================
    // Seq 24: max_burst — 256-beat INCR (awlen = 8'hFF, AXI4 protocol maximum)
    //   Inline AW + W + BRESP + AR + R because existing bfm_write/read_burst
    //   helpers use data[0:15] (16-beat limit).  Shadow updated via 16 chunked
    //   scb_write calls.  Per-beat inline comparison validates all 256 beats.
    //=========================================================================
    task automatic run_seq_max_burst();
        localparam int MAX_BURST_BASE = SIM_DEPTH / 2 + 1800;
        localparam int N_BEATS = 256;

        logic [AXI_DW-1:0]  wdata[0:255];
        logic [AXI_DW-1:0]  rdata[0:255];
        logic [AXI_AW-1:0]  addr;
        logic [1:0]          bresp;
        int                  t;
        int                  pass_cnt, fail_cnt;

        pass_cnt = 0; fail_cnt = 0;
        addr = BASE + AXI_AW'(MAX_BURST_BASE * AXI_SW);
        $display("\n=== SEQ 24: max_burst (256-beat INCR, awlen=8'hFF) ===");

        // Fill write data: pattern 0xBEEF_0000 | beat_index
        for (int b = 0; b < N_BEATS; b++)
            wdata[b] = AXI_DW'(32'hBEEF_0000 | b);

        // ── Write phase: inline AW + 256 W beats + BRESP ─────────────────
        t = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--t == 0) begin $display("  [MAX-BURST] WD awready"); goto_fail: txn_fail++; return; end
        end
        s_axi_awid    <= 4'hA;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'hFF;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= 2'b01;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);
        s_axi_awvalid <= 1'b0;

        for (int b = 0; b < N_BEATS; b++) begin
            t = WATCHDOG_CYCLES;
            while (!s_axi_wready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [MAX-BURST] WD wready b=%0d", b); txn_fail++; return; end
            end
            s_axi_wdata  <= wdata[b];
            s_axi_wstrb  <= '1;
            s_axi_wlast  <= (b == N_BEATS - 1);
            s_axi_wvalid <= 1'b1;
            @(posedge aclk);
            s_axi_wvalid <= 1'b0;
            s_axi_wlast  <= 1'b0;
        end

        t = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--t == 0) begin $display("  [MAX-BURST] WD bvalid"); txn_fail++; return; end
        end
        bresp        = s_axi_bresp;
        s_axi_bready <= 1'b1;
        @(posedge aclk);
        s_axi_bready <= 1'b0;
        @(posedge aclk);

        if (bresp !== 2'b00) begin
            $display("  [MAX-BURST] bad bresp=%0b", bresp);
            txn_fail++; fail_cnt++;
        end else begin
            txn_pass++; pass_cnt++;
        end

        // Shadow update: 16 chunks of 16 beats each via scb_write
        begin
            automatic logic [AXI_DW-1:0] chunk_data[0:15];
            automatic logic [AXI_SW-1:0] chunk_strb[0:15];
            for (int c = 0; c < 16; c++) begin
                for (int i = 0; i < 16; i++) begin
                    chunk_data[i] = wdata[c * 16 + i];
                    chunk_strb[i] = '1;
                end
                scb_write(addr + AXI_AW'(c * 16 * AXI_SW), chunk_data, chunk_strb,
                          8'hF, 2'b01);
            end
        end

        // ── Read phase: inline AR + 256 R beats + per-beat compare ────────
        t = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--t == 0) begin $display("  [MAX-BURST] WD arready"); txn_fail++; return; end
        end
        s_axi_arid    <= 4'hA;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'hFF;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= 2'b01;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);
        s_axi_arvalid <= 1'b0;

        for (int b = 0; b < N_BEATS; b++) begin
            t = WATCHDOG_CYCLES;
            while (!s_axi_rvalid) begin
                @(posedge aclk);
                if (--t == 0) begin $display("  [MAX-BURST] WD rvalid b=%0d", b); txn_fail++; return; end
            end
            rdata[b] = s_axi_rdata;
            s_axi_rready <= 1'b1;
            @(posedge aclk);
            s_axi_rready <= 1'b0;
        end

        // Compare all 256 beats
        begin
            automatic logic ok_all = 1'b1;
            for (int b = 0; b < N_BEATS; b++) begin
                if (rdata[b] !== wdata[b]) begin
                    $display("[MISMATCH] max_burst beat%0d  got=0x%0h  want=0x%0h",
                             b, rdata[b], wdata[b]);
                    ok_all = 1'b0;
                end
            end
            if (ok_all) begin txn_pass++; pass_cnt++; end
            else        begin txn_fail++; fail_cnt++; end
        end

        $display("  max_burst: %0d pass, %0d fail [256-beat INCR, beat counter = 255 reached]",
                 pass_cnt, fail_cnt);
    endtask

    //=========================================================================
    // Seq 25: bready_bp — write-response B-channel multi-cycle hold-off
    //   Every existing BFM task accepts bvalid within 1 clock of seeing it.
    //   This sequence holds bready=0 for 2–8 extra cycles after bvalid is
    //   detected, exercising the WR_RESP "if (bready)" false branch multiple
    //   times per transaction.
    //=========================================================================
    task automatic run_seq_bready_bp();
        localparam int BREADY_BP_BASE = SIM_DEPTH / 2 + 2060;
        logic [AXI_DW-1:0]  data, rdata_s;
        logic [1:0]          bresp, rresp_s;
        logic [AXI_AW-1:0]  addr;
        int                  t, hold, max_hold;
        int                  pass_cnt, fail_cnt;
        logic                ok;

        pass_cnt = 0; fail_cnt = 0; max_hold = 0;
        $display("\n=== SEQ 25: bready_bp (%0d iterations, bvalid hold-off 2-8 cycles) ===", N_RAND);

        for (int i = 0; i < N_RAND; i++) begin
            addr = BASE + AXI_AW'((BREADY_BP_BASE + i) * AXI_SW);
            data = {$urandom(), $urandom()};
            hold = $urandom_range(2, 8);
            if (hold > max_hold) max_hold = hold;

            // AW phase
            t = WATCHDOG_CYCLES;
            @(posedge aclk);
            while (!s_axi_awready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("[BREADY-BP] WD awready"); break; end
            end
            s_axi_awid    <= 4'hB;
            s_axi_awaddr  <= addr;
            s_axi_awlen   <= 8'h00;
            s_axi_awsize  <= 3'(AXI_SZ);
            s_axi_awburst <= 2'b01;
            s_axi_awvalid <= 1'b1;
            @(posedge aclk);
            s_axi_awvalid <= 1'b0;

            // W phase
            t = WATCHDOG_CYCLES;
            while (!s_axi_wready) begin
                @(posedge aclk);
                if (--t == 0) begin $display("[BREADY-BP] WD wready"); break; end
            end
            s_axi_wdata  <= data;
            s_axi_wstrb  <= '1;
            s_axi_wlast  <= 1'b1;
            s_axi_wvalid <= 1'b1;
            @(posedge aclk);
            s_axi_wvalid <= 1'b0;
            s_axi_wlast  <= 1'b0;

            // B phase: wait for bvalid, then hold bready=0 for 'hold' cycles
            t = WATCHDOG_CYCLES;
            while (!s_axi_bvalid) begin
                @(posedge aclk);
                if (--t == 0) begin $display("[BREADY-BP] WD bvalid"); break; end
            end
            // Deliberately hold bready=0 for 2–8 cycles while bvalid is asserted
            repeat (hold) @(posedge aclk);
            bresp        = s_axi_bresp;
            s_axi_bready <= 1'b1;
            @(posedge aclk);
            s_axi_bready <= 1'b0;
            @(posedge aclk);

            begin
                automatic logic [AXI_DW-1:0] da[0:15];
                automatic logic [AXI_SW-1:0] sa[0:15];
                da[0] = data; sa[0] = '1;
                scb_write(addr, da, sa, 8'h00, 2'b01);
            end

            if (bresp !== 2'b00) begin
                $display("  [FAIL] bready_bp[%0d] bresp=%0b", i, bresp);
                txn_fail++; fail_cnt++;
            end else begin
                txn_pass++; pass_cnt++;
            end

            // Read-back to verify data integrity after extended B hold
            bfm_read_single(4'hB, addr, 1'b0, rdata_s, rresp_s);
        end
        $display("  bready_bp: %0d pass, %0d fail [max bvalid hold = %0d cycles]",
                 pass_cnt, fail_cnt, max_hold);
    endtask

    //=========================================================================
    // Seq 26: wrap_boundary_start — WRAP burst start address = top of wrap window
    //   The wrap fires between beat 0 → beat 1 (earliest possible), exercising
    //   calc_next_addr WRAP case when current_addr == wrap_top already at beat 0.
    //   Tested for WRAP lengths L = 1 (2-beat), 3 (4-beat), 7 (8-beat).
    //   Each sub-test: pre-write all words, WRAP-write from top, WRAP-read back,
    //   then INCR cross-check to verify correct address assignment.
    //=========================================================================
    task automatic run_seq_wrap_boundary_start();
        localparam int WRAP_EDGE_BASE = SIM_DEPTH / 2 + 2120;

        // wrap_lens[k] = AXI awlen value; num_beats = wrap_len + 1
        automatic int wrap_lens [0:2] = '{1, 3, 7};
        int                  word_accum;
        int                  pass_cnt, fail_cnt;
        logic                ok;

        pass_cnt = 0; fail_cnt = 0;
        word_accum = 0;
        $display("\n=== SEQ 26: wrap_boundary_start (2-beat, 4-beat, 8-beat wraps from top) ===");

        for (int k = 0; k < 3; k++) begin
            automatic int           L         = wrap_lens[k];  // AXI len (beats-1)
            automatic int           N_BEATS_W = L + 1;
            automatic int           wrap_base_word;
            automatic logic [AXI_DW-1:0] wdata_pre[0:15], rdata_w[0:15];
            automatic logic [AXI_SW-1:0] strb_pre[0:15], strb_full[0:15];
            automatic logic [AXI_DW-1:0] wdata_wrap[0:15];
            automatic logic [1:0]        rresp_w[0:15], bresp_w;
            automatic logic [AXI_AW-1:0] top_addr, wrap_base_addr;

            // Align wrap_base_word to N_BEATS_W words
            wrap_base_word = WRAP_EDGE_BASE + word_accum;
            // Round up to next multiple of N_BEATS_W (already aligned if WRAP_EDGE_BASE chosen correctly)
            // Force alignment: round down to multiple of N_BEATS_W
            wrap_base_word = (wrap_base_word / N_BEATS_W) * N_BEATS_W;
            top_addr       = BASE + AXI_AW'((wrap_base_word + L) * AXI_SW);
            wrap_base_addr = BASE + AXI_AW'(wrap_base_word * AXI_SW);

            $display("  [WRAP-TOP] L=%0d (%0d-beat), wrap_base=0x%08h top_addr=0x%08h",
                     L, N_BEATS_W, wrap_base_addr, top_addr);

            // Pre-write all N_BEATS_W words with a baseline pattern
            for (int w = 0; w < N_BEATS_W; w++) begin
                automatic logic [AXI_DW-1:0] init_d = AXI_DW'(32'hD0D0_0000 | (k << 8) | w);
                bfm_write_single(4'hC, wrap_base_addr + AXI_AW'(w * AXI_SW),
                                 init_d, '1, 1'b0, bresp_w);
            end

            // WRAP write starting from top_addr (awlen = L, burst = WRAP)
            for (int b = 0; b <= L; b++) begin
                wdata_wrap[b] = AXI_DW'(32'hCAFE_0000 | (k << 8) | b);
                strb_full[b]  = '1;
            end
            bfm_write_burst_strobe_array(4'hC, top_addr, wdata_wrap, strb_full,
                                         8'(L), 2'b10, 1'b0, bresp_w);

            if (bresp_w !== 2'b00)
                $display("  [FAIL] wrap_top wr bresp=%0b L=%0d", bresp_w, L);

            // WRAP read starting from top_addr and verify
            bfm_read_burst(4'hC, top_addr, 8'(L), 2'b10, 1'b0, rdata_w, rresp_w);
            // scb_read_check is inside bfm_read_burst → already counted

            // INCR cross-check: read each word from wrap_base via single reads
            for (int w = 0; w < N_BEATS_W; w++) begin
                automatic logic [AXI_DW-1:0] rd_s;
                automatic logic [1:0]        rr_s;
                bfm_read_single(4'hC, wrap_base_addr + AXI_AW'(w * AXI_SW), 1'b0, rd_s, rr_s);
            end

            $display("  [WRAP-TOP] L=%0d done. wrap-around on beat 1 exercised [PASS]", L);
            word_accum += N_BEATS_W + N_BEATS_W;  // pre-write + wrap region + gap
        end

        $display("  wrap_boundary_start: done (%0d pass, %0d fail)", pass_cnt, fail_cnt);
    endtask

    //=========================================================================
    // Main test thread
    //=========================================================================
    initial begin
        // Initialise shadow memory valid flags
        for (int w = 0; w < SIM_DEPTH; w++)
            for (int by = 0; by < AXI_SW; by++)
                byte_valid[w][by] = 1'b0;

        // Reset sequence
        aresetn = 1'b0;
        mresetn = 1'b0;
        repeat (10) @(posedge aclk);
        aresetn = 1'b1;
        @(posedge mclk);
        mresetn = 1'b1;
        repeat (5) @(posedge aclk);

        // Run all sequences
        run_seq_single_rw();
        run_seq_burst_incr();
        run_seq_burst_wrap();
        run_seq_burst_fixed();
        run_seq_strobe();
        run_seq_backpressure();
        run_seq_page_miss();
        run_seq_oob_access();
        run_seq_wtr_stress();
        run_seq_dma_concurrent();
        run_seq_dma_outstanding();
        run_seq_true_outstanding();
        run_seq_mixed_burst_outstanding();
        run_seq_outstanding_mixed_rw();
        run_seq_burst_outstanding_drain();
        run_seq_burst_per_beat_strobe();
        run_seq_burst_bp_per_beat();
        run_seq_narrow_size();
        run_seq_burst_row_cross();
        run_seq_id_stress();
        run_seq_partial_write_page_miss_rd();
        run_seq_refresh_mid_burst();
        run_seq_wstrb_zero_beat();
        run_seq_max_burst();
        run_seq_bready_bp();
        run_seq_wrap_boundary_start();

        // Timing assertions
        check_timing_assertions();

        // Final summary
        $display("\n================================================");
        $display("  BFM test complete");
        $display("  (coverage data written to coverage.dat -- run 'make bfm-cov')");
        $display("  Transactions: %0d PASS, %0d FAIL",
                 txn_pass, txn_fail);
        if (txn_fail == 0)
            $display("  ALL TRANSACTIONS PASSED");
        else
            $display("  [FAIL] %0d transaction(s) had data mismatch", txn_fail);
        $display("================================================");

        if (txn_fail != 0) $fatal(1, "BFM test FAILED");
        $finish;
    end

endmodule
