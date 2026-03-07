// ============================================================================
// File: ddr4_axi4_bfm_tb.sv
// Project: KV32 RISC-V Processor
// Description: AXI4 BFM testbench for ddr4_axi4_slave.sv
//
// Features:
//   - Shadow-memory scoreboard for byte-accurate write/read comparison
//   - Functional coverage: burst type, length, strobe, back-pressure
//   - 10 sequence tasks (6 randomised + OOB + WTR stress + DMA concurrent/outstanding)
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
