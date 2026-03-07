// ============================================================================
// File: ddr4_axi4_bfm_tb.sv
// Project: KV32 RISC-V Processor
// Description: AXI4 BFM testbench for ddr4_axi4_slave.sv
//
// Features:
//   - Shadow-memory scoreboard for byte-accurate write/read comparison
//   - Functional coverage: burst type, length, strobe, back-pressure
//   - 6 randomised sequence tasks (N=50 each)
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
        .VERBOSE_MODE        (0),
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
            $display("  (ENABLE_TIMING=0 — assertions skipped)");
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
