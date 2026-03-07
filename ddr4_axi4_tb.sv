// ============================================================================
// File: ddr4_axi4_tb.sv
// Project: KV32 RISC-V Processor
// Description: Verilator-compatible testbench for ddr4_axi4_slave.sv
//
// Tests: single R/W, INCR/WRAP/FIXED burst, byte strobes, latency measurement,
// address-error detection, 16-beat sequential stress run, and AXI4 compliance
// checks (ID round-trip, RLAST/BVALID/RVALID stability, exclusive-access
// rejection, narrow transfers, back-pressure tolerance).
// Expected result (DDR4-2400, AXI 32-bit): all 16 tests PASS.
// ============================================================================

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */

`timescale 1ns/1ps
`include "ddr4_axi4_pkg.sv"
`include "ddr4_axi4_slave.sv"

module ddr4_axi4_tb;

    //=========================================================================
    // Testbench Parameters  (overrideable via -G on the Verilator command line)
    //=========================================================================
    parameter int         DDR4_SPEED       = 2400;        // DDR4 speed grade (MT/s)
    parameter int         AXI_DW           = 32;          // AXI data width (32 or 64)
    parameter int         ENABLE_TIMING    = 1;           // 1 = real DDR4 delays, 0 = bypass
    parameter int         RANDOM_DELAY_EN  = 0;           // 1 = inject random extra latency
    parameter int         MAX_RANDOM_DELAY = 8;           // max random extra mclk cycles
    parameter int         SIM_DEPTH        = 4096;        // simulation memory depth

    // Derived: mclk period in ns from the speed grade (half-rate clock = speed/2 MHz)
    localparam real       MCLK_PERIOD_NS   = 1000.0 * 2.0 / DDR4_SPEED;
    parameter  int        CLK_PERIOD_NS    = 10;         // aclk period (ns): 1=1GHz, 2=500MHz, 10=100MHz, 20=50MHz
    localparam [31:0]     BASE             = 32'h8000_0000;
    localparam int        AXI_SW           = AXI_DW / 8;
    localparam int        AXI_SZ           = $clog2(AXI_SW); // transfer size field (log2 bytes)
    localparam int        AXI_IDW          = 4;
    localparam int        AXI_AW           = 32;
    localparam int        WATCHDOG_CYCLES  = 2000;        // enlarged for realistic DDR4 latency

    //=========================================================================
    // Clock & Reset
    //=========================================================================
    logic aclk    = 1'b0;
    logic aresetn = 1'b0;
    logic mclk    = 1'b0;
    logic mresetn = 1'b0;

    // aclk: 100 MHz
    always #(CLK_PERIOD_NS / 2.0) aclk = ~aclk;
    // mclk: DDR4-2400 half-rate ≈ 1200 MHz (asynchronous to aclk)
    always #(MCLK_PERIOD_NS / 2.0) mclk = ~mclk;

    //=========================================================================
    // AXI4 Bus Signals
    //=========================================================================
    // Write address channel
    logic [AXI_IDW-1:0]  s_axi_awid    = '0;
    logic [AXI_AW-1:0]   s_axi_awaddr  = '0;
    logic [7:0]           s_axi_awlen   = '0;
    logic [2:0]           s_axi_awsize  = 3'(AXI_SZ);   // full-width default
    logic [1:0]           s_axi_awburst = 2'b01;        // INCR default
    logic                 s_axi_awlock  = '0;
    logic [3:0]           s_axi_awcache = '0;
    logic [2:0]           s_axi_awprot  = '0;
    logic [3:0]           s_axi_awqos   = '0;
    logic                 s_axi_awvalid = 1'b0;
    logic                 s_axi_awready;
    // Write data channel
    logic [AXI_DW-1:0]   s_axi_wdata   = '0;
    logic [AXI_SW-1:0]   s_axi_wstrb   = '1;
    logic                 s_axi_wlast   = 1'b0;
    logic                 s_axi_wvalid  = 1'b0;
    logic                 s_axi_wready;
    // Write response channel
    logic [AXI_IDW-1:0]  s_axi_bid;
    logic [1:0]           s_axi_bresp;
    logic                 s_axi_bvalid;
    logic                 s_axi_bready  = 1'b0;
    // Read address channel
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
    // Read data channel
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
    // Pass/Fail Counters
    //=========================================================================
    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check(input string name, input logic cond);
        if (cond) begin
            pass_cnt++;
            $display("[PASS] %s", name);
        end else begin
            fail_cnt++;
            $display("[FAIL] %s", name);
        end
    endtask

    //=========================================================================
    // AXI4 Utility Tasks
    //=========================================================================

    // Wait N rising clock edges
    task automatic clk_delay(input int n);
        repeat (n) @(posedge aclk);
    endtask

    // Single-beat AXI4 write.  Returns BRESP.
    task automatic axi4_write_single(
        input  [AXI_IDW-1:0]  id,
        input  [AXI_AW-1:0]   addr,
        input  [AXI_DW-1:0]   data,
        input  [AXI_SW-1:0]   strb,
        output logic [1:0]    bresp
    );
        int timeout;
        // --- AW: wait for awready, then drive awvalid for one cycle ---
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin
                $display("[TB] WATCHDOG: AWREADY timeout (write, addr=0x%h)", addr);
                break;
            end
        end
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'h00;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= 2'b01;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);           // handshake: awvalid=1, awready=1
        s_axi_awvalid <= 1'b0;

        // --- W: wait for wready, then drive wdata/wvalid for one cycle ---
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_wready) begin
            @(posedge aclk);
            if (--timeout == 0) begin
                $display("[TB] WATCHDOG: WREADY timeout (write, addr=0x%h)", addr);
                break;
            end
        end
        s_axi_wdata  <= data;
        s_axi_wstrb  <= strb;
        s_axi_wlast  <= 1'b1;
        s_axi_wvalid <= 1'b1;
        @(posedge aclk);           // handshake: wvalid=1, wready=1
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        // --- B: wait for bvalid (bready=0), then complete handshake ---
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin
                $display("[TB] WATCHDOG: BVALID timeout (write, addr=0x%h)", addr);
                break;
            end
        end
        bresp        = s_axi_bresp;
        s_axi_bready <= 1'b1;
        @(posedge aclk);           // handshake: bvalid=1, bready=1
        s_axi_bready <= 1'b0;
        @(posedge aclk);
    endtask

    // Single-beat AXI4 read.  Returns RDATA and RRESP.
    task automatic axi4_read_single(
        input  [AXI_IDW-1:0]  id,
        input  [AXI_AW-1:0]   addr,
        output logic [AXI_DW-1:0] rdata,
        output logic [1:0]        rresp
    );
        int timeout;
        // --- AR: wait for arready, then drive arvalid for one cycle ---
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin
                $display("[TB] WATCHDOG: ARREADY timeout (read, addr=0x%h)", addr);
                break;
            end
        end
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'h00;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= 2'b01;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);           // handshake
        s_axi_arvalid <= 1'b0;

        // --- R: wait for rvalid (rready=0), then complete handshake ---
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin
                $display("[TB] WATCHDOG: RVALID timeout (read, addr=0x%h)", addr);
                break;
            end
        end
        rdata        = s_axi_rdata;
        rresp        = s_axi_rresp;
        s_axi_rready <= 1'b1;
        @(posedge aclk);           // handshake
        s_axi_rready <= 1'b0;
        @(posedge aclk);
    endtask

    // Burst write (up to 16 beats). burst: 00=FIXED 01=INCR 10=WRAP
    task automatic axi4_write_burst(
        input  [AXI_IDW-1:0]  id,
        input  [AXI_AW-1:0]   addr,
        input  [AXI_DW-1:0]   data [0:15],
        input  [7:0]           len,        // AXI len field (beats-1)
        input  [1:0]           burst,
        output logic [1:0]     bresp
    );
        int timeout;
        // --- AW: wait for awready, then drive awvalid ---
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin
                $display("[TB] WATCHDOG: AWREADY timeout (burst write)"); break;
            end
        end
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= len;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= burst;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);           // handshake
        s_axi_awvalid <= 1'b0;

        // --- W: for each beat wait for wready, then drive wvalid ---
        for (int b = 0; b <= int'(len); b++) begin
            timeout = WATCHDOG_CYCLES;
            while (!s_axi_wready) begin
                @(posedge aclk);
                if (--timeout == 0) begin
                    $display("[TB] WATCHDOG: WREADY timeout (burst write beat %0d)", b); break;
                end
            end
            s_axi_wdata  <= data[b];
            s_axi_wstrb  <= '1;
            s_axi_wlast  <= (b == int'(len));
            s_axi_wvalid <= 1'b1;
            @(posedge aclk);       // handshake
            s_axi_wvalid <= 1'b0;
            s_axi_wlast  <= 1'b0;
        end

        // --- B: wait for bvalid (bready=0), then complete handshake ---
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin
                $display("[TB] WATCHDOG: BVALID timeout (burst write)"); break;
            end
        end
        bresp        = s_axi_bresp;
        s_axi_bready <= 1'b1;
        @(posedge aclk);           // handshake
        s_axi_bready <= 1'b0;
        @(posedge aclk);
    endtask

    // Burst read (up to 16 beats)
    task automatic axi4_read_burst(
        input  [AXI_IDW-1:0]  id,
        input  [AXI_AW-1:0]   addr,
        input  [7:0]           len,
        input  [1:0]           burst,
        output logic [AXI_DW-1:0] rdata [0:15],
        output logic [1:0]        rresp [0:15]
    );
        int timeout;
        // --- AR: wait for arready, then drive arvalid ---
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin
                $display("[TB] WATCHDOG: ARREADY timeout (burst read)"); break;
            end
        end
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= len;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= burst;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);           // handshake
        s_axi_arvalid <= 1'b0;

        // --- R: wait for first rvalid (rready=0), capture beat 0,
        //        then assert rready and collect beats 1..len ---
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin
                $display("[TB] WATCHDOG: RVALID timeout (burst read beat 0)"); break;
            end
        end
        // beat 0: rvalid=1, rready=0 – data stable, no handshake yet
        rdata[0] = s_axi_rdata;
        rresp[0] = s_axi_rresp;
        s_axi_rready <= 1'b1;      // enable handshakes from next cycle
        for (int beat = 1; beat <= int'(len); beat++) begin
            @(posedge aclk);       // beat(beat-1) handshake; beat_beat data latched
            rdata[beat] = s_axi_rdata;
            rresp[beat] = s_axi_rresp;
        end
        @(posedge aclk);           // final handshake for last beat (rlast)
        s_axi_rready <= 1'b0;
        @(posedge aclk);
    endtask

    //=========================================================================
    // Test Cases
    //=========================================================================

    // -----------------------------------------------------------------------
    // Test 1: Single write then single read
    // -----------------------------------------------------------------------
    task automatic test_single_rw();
        logic [AXI_DW-1:0] rdata;
        logic [1:0]         rresp, bresp;
        logic [AXI_DW-1:0] wdata = 32'hCAFE_0001;
        logic [AXI_AW-1:0] addr  = BASE + 32'h0000_0000;

        $display("\n--- Test 1: Single R/W ---");
        axi4_write_single(4'h1, addr, wdata, 4'hF, bresp);
        check("T1: BRESP=OKAY", bresp == 2'b00);
        axi4_read_single (4'h1, addr, rdata, rresp);
        check("T1: RRESP=OKAY", rresp == 2'b00);
        check("T1: data match", rdata === wdata);
    endtask

    // -----------------------------------------------------------------------
    // Test 2: 8-beat INCR burst write + burst read, verify all beats
    // -----------------------------------------------------------------------
    task automatic test_burst_incr();
        logic [AXI_DW-1:0] wdata [0:15];
        logic [AXI_DW-1:0] rdata [0:15];
        logic [1:0]         rresp [0:15];
        logic [1:0]         bresp;
        logic [AXI_AW-1:0] addr = BASE + 32'h0000_0100;
        logic               all_ok = 1'b1;

        $display("\n--- Test 2: 8-beat INCR burst ---");
        for (int i = 0; i < 8; i++) wdata[i] = 32'hAA00_0000 | i;
        for (int i = 8; i < 16; i++) wdata[i] = '0;

        axi4_write_burst(4'h2, addr, wdata, 8'h07, 2'b01, bresp);
        check("T2: BRESP=OKAY", bresp == 2'b00);
        axi4_read_burst (4'h2, addr, 8'h07, 2'b01, rdata, rresp);
        for (int i = 0; i < 8; i++) begin
            if (rdata[i] !== wdata[i]) all_ok = 1'b0;
        end
        check("T2: all 8 beats data match", all_ok);
    endtask

    // -----------------------------------------------------------------------
    // Test 3: 4-beat WRAP burst — verify wrap-boundary data placement
    // -----------------------------------------------------------------------
    task automatic test_burst_wrap();
        // 4-beat WRAP, size=AXI_SW bytes → wrap_size = 4*AXI_SW bytes
        // Start 2 beats into the aligned window to force wrapping on beat 2
        logic [AXI_DW-1:0] wdata [0:15];
        logic [AXI_DW-1:0] rdata [0:15];
        logic [1:0]         rresp [0:15];
        logic [1:0]         bresp;
        // Aligned 4*AXI_SW window; start at offset AXI_SW*2 to force wrap
        logic [AXI_AW-1:0] wrap_base = BASE + 32'h0000_0200;
        logic [AXI_AW-1:0] addr      = wrap_base + 32'(AXI_SW * 2);
        logic               all_ok = 1'b1;

        $display("\n--- Test 3: 4-beat WRAP burst ---");
        wdata[0] = AXI_DW'(32'hBB00_0002);  // goes to wrap_base+AXI_SW*2
        wdata[1] = AXI_DW'(32'hBB00_0003);  // goes to wrap_base+AXI_SW*3
        wdata[2] = AXI_DW'(32'hBB00_0000);  // wraps → wrap_base+0
        wdata[3] = AXI_DW'(32'hBB00_0001);  // → wrap_base+AXI_SW
        for (int i = 4; i < 16; i++) wdata[i] = '0;

        axi4_write_burst(4'h3, addr, wdata, 8'h03, 2'b10, bresp);
        check("T3: BRESP=OKAY", bresp == 2'b00);

        // Read all 4 locations individually and verify
        begin
            logic [AXI_DW-1:0] r;
            logic [1:0]         rr;
            axi4_read_single(4'h3, wrap_base + 32'(AXI_SW*0), r, rr);
            if (r !== wdata[2]) begin
                $display("  wrap+0x00: got 0x%h want 0x%h", r, wdata[2]); all_ok = 1'b0;
            end
            axi4_read_single(4'h3, wrap_base + 32'(AXI_SW*1), r, rr);
            if (r !== wdata[3]) begin
                $display("  wrap+AXI_SW: got 0x%h want 0x%h", r, wdata[3]); all_ok = 1'b0;
            end
            axi4_read_single(4'h3, wrap_base + 32'(AXI_SW*2), r, rr);
            if (r !== wdata[0]) begin
                $display("  wrap+AXI_SW*2: got 0x%h want 0x%h", r, wdata[0]); all_ok = 1'b0;
            end
            axi4_read_single(4'h3, wrap_base + 32'(AXI_SW*3), r, rr);
            if (r !== wdata[1]) begin
                $display("  wrap+AXI_SW*3: got 0x%h want 0x%h", r, wdata[1]); all_ok = 1'b0;
            end
        end
        check("T3: WRAP data placement correct", all_ok);
    endtask

    // -----------------------------------------------------------------------
    // Test 4: 4-beat FIXED burst — last write wins at same address
    // -----------------------------------------------------------------------
    task automatic test_burst_fixed();
        logic [AXI_DW-1:0] wdata [0:15];
        logic [AXI_DW-1:0] rdata;
        logic [1:0]         rresp, bresp;
        logic [AXI_AW-1:0] addr = BASE + 32'h0000_0400;

        $display("\n--- Test 4: 4-beat FIXED burst ---");
        wdata[0] = 32'hCC00_0000;
        wdata[1] = 32'hCC00_0001;
        wdata[2] = 32'hCC00_0002;
        wdata[3] = 32'hCC00_0003;  // last write wins
        for (int i = 4; i < 16; i++) wdata[i] = '0;

        axi4_write_burst(4'h4, addr, wdata, 8'h03, 2'b00, bresp);
        check("T4: BRESP=OKAY", bresp == 2'b00);
        axi4_read_single(4'h4, addr, rdata, rresp);
        check("T4: FIXED last-write wins", rdata === wdata[3]);
    endtask

    // -----------------------------------------------------------------------
    // Test 5: Byte-strobe partial write
    // -----------------------------------------------------------------------
    task automatic test_byte_strobe();
        logic [AXI_DW-1:0] rdata;
        logic [1:0]         rresp, bresp;
        logic [AXI_AW-1:0] addr = BASE + 32'h0000_0500;
        // First: write all-ones
        axi4_write_single(4'h5, addr, 32'hFFFF_FFFF, 4'hF, bresp);
        // Second: write 0x0000 with strobe on lower 2 bytes only
        axi4_write_single(4'h5, addr, 32'h0000_0000, 4'h3, bresp);
        // Read back
        axi4_read_single (4'h5, addr, rdata, rresp);

        $display("\n--- Test 5: Byte strobe ---");
        // Lower 2 bytes should be 0x0000, upper 2 bytes still 0xFFFF
        check("T5: strobe – lower bytes zeroed", rdata[15:0]  === 16'h0000);
        check("T5: strobe – upper bytes intact", rdata[31:16] === 16'hFFFF);
    endtask

    // -----------------------------------------------------------------------
    // Test 6: Read latency measurement
    // The elapsed AXI-clock time from AR-accept to RVALID must cover at least
    // READ_LAT_CYC mclk cycles (each TCK_PS ps long).
    // -----------------------------------------------------------------------
    task automatic test_read_latency();
        longint t_start_ps, t_end_ps, elapsed_ps;
        longint min_ps;
        logic [AXI_DW-1:0] rdata;
        logic [1:0]         rresp, bresp;
        logic [AXI_AW-1:0] addr = BASE + 32'h0000_0600;
        int timeout;

        $display("\n--- Test 6: Read latency measurement ---");
        // Pre-write a known value
        axi4_write_single(4'h6, addr, 32'hAAAA_6666, 4'hF, bresp);

        // Issue AR: wait for arready, then present arvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T6 arready"); break; end
        end
        s_axi_arid    <= 4'h6;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'h00;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= 2'b01;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);           // AR handshake
        t_start_ps = $time;        // capture time of AR accept
        s_axi_arvalid <= 1'b0;

        // Wait for rvalid without rready
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T6 rvalid"); break; end
        end
        t_end_ps    = $time;
        elapsed_ps  = (t_end_ps - t_start_ps) * 1000;  // ns → ps
        min_ps      = longint'(dut.READ_LAT_CYC) * longint'(dut.TCK_PS);
        s_axi_rready <= 1'b1;
        @(posedge aclk);           // R handshake
        s_axi_rready <= 1'b0;
        @(posedge aclk);

        $display("  Elapsed: %0d ps  |  Minimum required: %0d ps  (READ_LAT=%0d * TCK=%0d)",
                 elapsed_ps, min_ps, dut.READ_LAT_CYC, dut.TCK_PS);
        check("T6: read latency >= READ_LAT_CYC * TCK_PS", elapsed_ps >= min_ps);
    endtask

    // -----------------------------------------------------------------------
    // Test 7: Write preamble latency
    // Elapsed time from AW-accept to WREADY must cover WRITE_PRE_CYC mclk cycles.
    // -----------------------------------------------------------------------
    task automatic test_write_latency();
        longint t_start_ps, t_end_ps, elapsed_ps;
        longint min_ps;
        logic [1:0] bresp;
        logic [AXI_AW-1:0] addr = BASE + 32'h0000_0700;
        int timeout;

        $display("\n--- Test 7: Write preamble latency measurement ---");

        // AW: wait for awready, then present awvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T7 awready"); break; end
        end
        s_axi_awid    <= 4'h7;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'h00;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= 2'b01;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);           // AW handshake
        t_start_ps    = $time;
        s_axi_awvalid <= 1'b0;

        // W: wait for wready, then drive wvalid
        s_axi_wdata  <= 32'h7777_7777;
        s_axi_wstrb  <= 4'hF;
        s_axi_wlast  <= 1'b1;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_wready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T7 wready"); break; end
        end
        t_end_ps   = $time;
        elapsed_ps = (t_end_ps - t_start_ps) * 1000;  // ns → ps
        min_ps     = longint'(dut.WRITE_PRE_CYC) * longint'(dut.TCK_PS);
        s_axi_wvalid <= 1'b1;
        @(posedge aclk);           // W handshake
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        // B: wait for bvalid (bready=0), then complete handshake
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) break;
        end
        bresp        = s_axi_bresp;
        s_axi_bready <= 1'b1;
        @(posedge aclk);           // B handshake
        s_axi_bready <= 1'b0;
        @(posedge aclk);

        $display("  Elapsed: %0d ps  |  Minimum required: %0d ps  (WRITE_PRE=%0d * TCK=%0d)",
                 elapsed_ps, min_ps, dut.WRITE_PRE_CYC, dut.TCK_PS);
        check("T7: write preamble >= WRITE_PRE_CYC * TCK_PS", elapsed_ps >= min_ps);
        check("T7: BRESP=OKAY", bresp == 2'b00);
    endtask

    // -----------------------------------------------------------------------
    // Test 8: Out-of-range address → SLVERR
    // -----------------------------------------------------------------------
    task automatic test_addr_error();
        logic [AXI_DW-1:0] rdata;
        logic [1:0]         rresp, bresp;
        // Address well beyond SIM_DEPTH × 8 bytes from BASE
        logic [AXI_AW-1:0] bad_addr = BASE + 32'(SIM_DEPTH * 8 + 32'h1000);

        $display("\n--- Test 8: Address-error (SLVERR) ---");
        axi4_write_single(4'h8, bad_addr, 32'hBAD_BAD00, 4'hF, bresp);
        check("T8: write SLVERR on bad addr", bresp == 2'b10);
        axi4_read_single (4'h8, bad_addr, rdata, rresp);
        check("T8: read SLVERR on bad addr", rresp == 2'b10);
    endtask

    // -----------------------------------------------------------------------
    // Test 9: Sequential 16 write-read pairs with pseudo-random data
    // -----------------------------------------------------------------------
    task automatic test_sequential();
        logic [AXI_DW-1:0] wdata, rdata;
        logic [1:0]         rresp, bresp;
        logic               all_ok = 1'b1;
        logic [AXI_AW-1:0] addr;
        logic [AXI_DW-1:0] seed = 32'hDEAD_BE00;

        $display("\n--- Test 9: Sequential 16 write-read pairs ---");
        for (int i = 0; i < 16; i++) begin
            // Simple LFSR-style address spread within depth
            addr  = BASE + 32'((i * 32'h20) & 32'h3FFC);  // 4-byte aligned, within 4096 window
            wdata = seed ^ 32'(i * 32'hFEED_CAFE);
            axi4_write_single(4'(i & 4'hF), addr, wdata, 4'hF, bresp);
            axi4_read_single (4'(i & 4'hF), addr, rdata, rresp);
            if (rdata !== wdata) begin
                $display("  [i=%0d] addr=0x%h: wrote 0x%h read 0x%h", i, addr, wdata, rdata);
                all_ok = 1'b0;
            end
        end
        check("T9: all 16 pairs match", all_ok);
    endtask

    // -----------------------------------------------------------------------
    // Test 10: BID / RID round-trip – slave echoes back the transaction ID
    // AXI spec: BID must equal the corresponding AWID; RID must equal ARID.
    // -----------------------------------------------------------------------
    task automatic test_id_roundtrip();
        logic [AXI_IDW-1:0] wid   = 4'hA;
        logic [AXI_IDW-1:0] rid   = 4'hB;
        logic [AXI_AW-1:0]  addr  = BASE + 32'h0000_0A00;
        logic [AXI_DW-1:0]  wdata = 32'hAA55_AA55;
        int timeout;

        $display("\n--- Test 10: ID round-trip (BID/RID matching) ---");

        // Write with ID=wid – AW: wait for awready, then drive awvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T10 awready"); break; end
        end
        s_axi_awid    <= wid;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'h00;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= 2'b01;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);           // AW handshake
        s_axi_awvalid <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_wready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T10 wready"); break; end
        end
        s_axi_wdata  <= wdata;
        s_axi_wstrb  <= 4'hF;
        s_axi_wlast  <= 1'b1;
        s_axi_wvalid <= 1'b1;
        @(posedge aclk);           // W handshake
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T10 bvalid"); break; end
        end
        check("T10: BID matches AWID", s_axi_bid === wid);
        s_axi_bready <= 1'b1;
        @(posedge aclk);           // B handshake
        s_axi_bready <= 1'b0;
        @(posedge aclk);

        // Read with ID=rid – AR: wait for arready, then drive arvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T10 arready"); break; end
        end
        s_axi_arid    <= rid;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'h00;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= 2'b01;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);           // AR handshake
        s_axi_arvalid <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T10 rvalid"); break; end
        end
        check("T10: RID matches ARID",  s_axi_rid   === rid);
        check("T10: data correct",       s_axi_rdata === wdata);
        s_axi_rready <= 1'b1;
        @(posedge aclk);           // R handshake
        s_axi_rready <= 1'b0;
        @(posedge aclk);
    endtask

    // -----------------------------------------------------------------------
    // Test 11: RLAST alignment – must be asserted exactly on the last beat.
    // AXI spec: slave asserts RLAST on beat arlen (0-based), never earlier.
    // -----------------------------------------------------------------------
    task automatic test_rlast_alignment();
        localparam int BEATS = 4;
        logic [AXI_DW-1:0] wdata [0:15];
        logic [1:0]         bresp;
        logic [AXI_AW-1:0] addr       = BASE + 32'h0000_0B00;
        logic               early_last = 1'b0;
        logic               last_seen  = 1'b0;
        int timeout;

        $display("\n--- Test 11: RLAST alignment (only on last beat) ---");

        // Pre-fill memory so read returns meaningful data
        for (int i = 0; i < BEATS; i++) wdata[i] = 32'hBB00_0000 | i;
        for (int i = BEATS; i < 16;   i++) wdata[i] = '0;
        axi4_write_burst(4'hC, addr, wdata, BEATS-1, 2'b01, bresp);

        // Issue AR burst: wait for arready, then drive arvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T11 arready"); break; end
        end
        s_axi_arid    <= 4'hC;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= BEATS - 1;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= 2'b01;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);           // AR handshake
        s_axi_arvalid <= 1'b0;

        // Wait for first rvalid (rready=0), then assert rready and collect all beats
        timeout = WATCHDOG_CYCLES * BEATS;
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T11 beat 0"); break; end
        end
        // beat 0: rvalid=1, rready=0 – check rlast pre-handshake
        if (s_axi_rlast && 0 < BEATS-1) early_last = 1'b1;
        if (0 == BEATS-1)               last_seen  = s_axi_rlast;
        s_axi_rready <= 1'b1;
        for (int b = 1; b < BEATS; b++) begin
            @(posedge aclk);       // beat(b-1) handshake; beat_b data latched
            if (s_axi_rlast && b < BEATS-1) early_last = 1'b1;
            if (b == BEATS-1)               last_seen  = s_axi_rlast;
        end
        @(posedge aclk);           // final handshake for last beat
        s_axi_rready <= 1'b0;
        @(posedge aclk);

        check("T11: RLAST not asserted early",   !early_last);
        check("T11: RLAST asserted on last beat",  last_seen);
    endtask

    // -----------------------------------------------------------------------
    // Test 12: BVALID stability – once asserted, must remain HIGH until BREADY.
    // AXI spec §A3.2.1: "Once VALID is asserted it must remain asserted until
    //                    the handshake occurs."
    // -----------------------------------------------------------------------
    task automatic test_bvalid_stable();
        logic [AXI_AW-1:0] addr          = BASE + 32'h0000_0C00;
        logic               bvalid_dropped = 1'b0;
        int timeout;

        $display("\n--- Test 12: BVALID stability (held until BREADY) ---");

        // AW: wait for awready, then drive awvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T12 awready"); break; end
        end
        s_axi_awid    <= 4'hD;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'h00;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= 2'b01;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);           // AW handshake
        s_axi_awvalid <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_wready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T12 wready"); break; end
        end
        s_axi_wdata  <= 32'hCC00_CC00;
        s_axi_wstrb  <= 4'hF;
        s_axi_wlast  <= 1'b1;
        s_axi_wvalid <= 1'b1;
        @(posedge aclk);           // W handshake
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        // Wait for BVALID without asserting BREADY
        s_axi_bready <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T12 bvalid"); break; end
        end

        // Observe BVALID for 15 cycles while holding BREADY low
        repeat (15) begin
            @(posedge aclk);
            if (!s_axi_bvalid) bvalid_dropped = 1'b1;
        end

        check("T12: BVALID stable until BREADY", !bvalid_dropped);

        // Complete the handshake
        s_axi_bready <= 1'b1;
        @(posedge aclk);
        s_axi_bready <= 1'b0;
        @(posedge aclk);
    endtask

    // -----------------------------------------------------------------------
    // Test 13: RVALID stability – once asserted per beat, must remain HIGH
    //          until RREADY is asserted (AXI spec §A3.2.1).
    // -----------------------------------------------------------------------
    task automatic test_rvalid_stable();
        logic [AXI_AW-1:0] addr          = BASE + 32'h0000_0D00;
        logic [1:0]         bresp;
        logic               rvalid_dropped = 1'b0;
        int timeout;

        $display("\n--- Test 13: RVALID stability (held until RREADY) ---");

        axi4_write_single(4'hE, addr, 32'hDD00_DD00, 4'hF, bresp);

        // Issue AR: wait for arready, then drive arvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T13 arready"); break; end
        end
        s_axi_arid    <= 4'hE;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'h00;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= 2'b01;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);           // AR handshake
        s_axi_arvalid <= 1'b0;

        // Hold RREADY low, wait for RVALID
        s_axi_rready <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T13 rvalid"); break; end
        end

        // Observe RVALID for 15 cycles while holding RREADY low
        repeat (15) begin
            @(posedge aclk);
            if (!s_axi_rvalid) rvalid_dropped = 1'b1;
        end

        check("T13: RVALID stable until RREADY", !rvalid_dropped);

        // Complete the handshake
        s_axi_rready <= 1'b1;
        @(posedge aclk);
        s_axi_rready <= 1'b0;
        @(posedge aclk);
    endtask

    // -----------------------------------------------------------------------
    // Test 14: Exclusive access not supported.
    // AXI spec allows EXOKAY (2'b01) only when exclusive access is supported.
    // This slave does not implement the exclusive-access monitor, so it must
    // never return EXOKAY on BRESP or RRESP.
    // -----------------------------------------------------------------------
    task automatic test_exclusive_access();
        logic [AXI_AW-1:0] addr = BASE + 32'h0000_0E00;
        logic [1:0]         bresp, rresp;
        int timeout;

        $display("\n--- Test 14: Exclusive access not supported (no EXOKAY) ---");

        // Exclusive write (awlock=1): wait for awready, then drive awvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T14 awready"); break; end
        end
        s_axi_awid    <= 4'hF;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'h00;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= 2'b01;
        s_axi_awlock  <= 1'b1;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);           // AW handshake
        s_axi_awvalid <= 1'b0;
        s_axi_awlock  <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_wready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T14 wready"); break; end
        end
        s_axi_wdata  <= 32'hEE00_EE00;
        s_axi_wstrb  <= 4'hF;
        s_axi_wlast  <= 1'b1;
        s_axi_wvalid <= 1'b1;
        @(posedge aclk);           // W handshake
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T14 bvalid"); break; end
        end
        bresp = s_axi_bresp;
        s_axi_bready <= 1'b1;
        @(posedge aclk);           // B handshake
        s_axi_bready <= 1'b0;
        @(posedge aclk);
        check("T14: excl write – BRESP != EXOKAY", bresp !== 2'b01);

        // Exclusive read (arlock=1): wait for arready, then drive arvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T14 arready"); break; end
        end
        s_axi_arid    <= 4'hF;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'h00;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= 2'b01;
        s_axi_arlock  <= 1'b1;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);           // AR handshake
        s_axi_arvalid <= 1'b0;
        s_axi_arlock  <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T14 rvalid"); break; end
        end
        rresp = s_axi_rresp;
        s_axi_rready <= 1'b1;
        @(posedge aclk);           // R handshake
        s_axi_rready <= 1'b0;
        @(posedge aclk);
        check("T14: excl read  – RRESP != EXOKAY", rresp !== 2'b01);
    endtask

    // -----------------------------------------------------------------------
    // Test 15: Narrow transfer – awsize = 3'b001 (2 bytes) on a 32-bit bus.
    // Only the byte-lane selected by the strobe is written; other lanes must
    // retain their previous values (verified by the slave's strobe logic).
    // -----------------------------------------------------------------------
    task automatic test_narrow_transfer();
        logic [AXI_AW-1:0] addr = BASE + 32'h0000_0F00;
        logic [AXI_DW-1:0] rdata;
        logic [1:0]         rresp, bresp;
        int timeout;

        $display("\n--- Test 15: Narrow transfer (2-byte size on 32-bit bus) ---");

        // Initialise the word to all-zeros
        axi4_write_single(4'h1, addr, 32'h0000_0000, 4'hF, bresp);

        // Narrow write: awsize=3'b001 – wait for awready, then drive awvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T15 awready"); break; end
        end
        s_axi_awid    <= 4'h1;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'h00;
        s_axi_awsize  <= 3'b001;   // 2-byte size
        s_axi_awburst <= 2'b01;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);           // AW handshake
        s_axi_awvalid <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_wready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T15 wready"); break; end
        end
        s_axi_wdata  <= 32'hFF00_ABCD;   // upper half is noise; strobe gates it out
        s_axi_wstrb  <= 4'b0011;          // bytes [1:0] active
        s_axi_wlast  <= 1'b1;
        s_axi_wvalid <= 1'b1;
        @(posedge aclk);           // W handshake
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T15 bvalid"); break; end
        end
        bresp = s_axi_bresp;
        s_axi_bready <= 1'b1;
        @(posedge aclk);           // B handshake
        s_axi_bready <= 1'b0;
        @(posedge aclk);

        axi4_read_single(4'h1, addr, rdata, rresp);

        check("T15: narrow write BRESP=OKAY",      bresp == 2'b00);
        check("T15: lower 2B written correctly",   rdata[15:0]  === 16'hABCD);
        check("T15: upper 2B unchanged (0x0000)",  rdata[31:16] === 16'h0000);
    endtask

    // -----------------------------------------------------------------------
    // Test 16: Back-pressure – master holds BREADY / RREADY low for 20 cycles
    //          after the slave asserts BVALID / RVALID.  The transaction must
    //          complete correctly once ready is eventually asserted.
    // -----------------------------------------------------------------------
    task automatic test_back_pressure();
        logic [AXI_AW-1:0] addr  = BASE + 32'h0000_1000;
        logic [AXI_DW-1:0] wdata = 32'hBEEF_1234;
        logic [AXI_DW-1:0] rdata;
        logic [1:0]         bresp, rresp;
        int timeout;

        $display("\n--- Test 16: Back-pressure (delayed BREADY / RREADY) ---");

        // ---- Write with 20-cycle BREADY back-pressure ----
        // AW: wait for awready, then drive awvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_awready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T16 awready"); break; end
        end
        s_axi_awid    <= 4'h2;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'h00;
        s_axi_awsize  <= 3'(AXI_SZ);
        s_axi_awburst <= 2'b01;
        s_axi_awvalid <= 1'b1;
        @(posedge aclk);           // AW handshake
        s_axi_awvalid <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        while (!s_axi_wready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T16 wready"); break; end
        end
        s_axi_wdata  <= wdata;
        s_axi_wstrb  <= 4'hF;
        s_axi_wlast  <= 1'b1;
        s_axi_wvalid <= 1'b1;
        @(posedge aclk);           // W handshake
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;
        s_axi_bready <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_bvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T16 bvalid"); break; end
        end
        repeat (20) @(posedge aclk);   // deliberate back-pressure
        s_axi_bready <= 1'b1;
        @(posedge aclk);
        bresp = s_axi_bresp;
        s_axi_bready <= 1'b0;
        @(posedge aclk);

        // ---- Read with 20-cycle RREADY back-pressure ----
        // AR: wait for arready, then drive arvalid
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_arready) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T16 arready"); break; end
        end
        s_axi_arid    <= 4'h2;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'h00;
        s_axi_arsize  <= 3'(AXI_SZ);
        s_axi_arburst <= 2'b01;
        s_axi_arvalid <= 1'b1;
        @(posedge aclk);           // AR handshake
        s_axi_arvalid <= 1'b0;
        s_axi_rready  <= 1'b0;
        timeout = WATCHDOG_CYCLES;
        @(posedge aclk);
        while (!s_axi_rvalid) begin
            @(posedge aclk);
            if (--timeout == 0) begin $display("[TB] WATCHDOG T16 rvalid"); break; end
        end
        repeat (20) @(posedge aclk);   // deliberate back-pressure
        s_axi_rready <= 1'b1;
        @(posedge aclk);
        rdata = s_axi_rdata;
        rresp = s_axi_rresp;
        s_axi_rready <= 1'b0;
        @(posedge aclk);

        check("T16: back-pressure write BRESP=OKAY", bresp == 2'b00);
        check("T16: back-pressure read  RRESP=OKAY", rresp == 2'b00);
        check("T16: back-pressure data correct",      rdata === wdata);
    endtask

    //=========================================================================
    // Main Simulation
    //=========================================================================
    initial begin
        $display("========================================================");
        $display("  DDR4 AXI4 Slave Testbench  –  DDR4-%0d",  DDR4_SPEED);
        $display("  aclk = %0d MHz  |  mclk = %0d MHz (async, DDR4 half-rate)",
                 1000/CLK_PERIOD_NS, DDR4_SPEED/2);
        $display("  SIM_MEM_DEPTH = %0d entries (%0d KB)",
                 SIM_DEPTH, (SIM_DEPTH * 8) / 1024);
        $display("========================================================");

        // Reset – assert both domain resets together
        aresetn = 1'b0;
        mresetn = 1'b0;
        clk_delay(10);
        @(posedge aclk);
        aresetn = 1'b1;
        mresetn = 1'b1;
        clk_delay(5);

        $display("\nDerived timing parameters from DUT:");
        $display("  TCK_PS       = %0d ps  (DDR4-%0d data-rate clock)", dut.TCK_PS, DDR4_SPEED);
        $display("  mclk rate    = %0d MHz (half-rate; async to aclk @ %0d MHz)",
                 DDR4_SPEED/2, 1000/CLK_PERIOD_NS);
        $display("  tRCD_CYC     = %0d mclk cycles", dut.tRCD_CYC);
        $display("  CL_CYC       = %0d mclk cycles", dut.CL_CYC);
        $display("  CWL_CYC      = %0d mclk cycles", dut.CWL_CYC);
        $display("  READ_LAT_CYC = %0d mclk cycles (tRCD + CL)", dut.READ_LAT_CYC);
        $display("  WRITE_PRE    = %0d mclk cycles (tRCD + CWL)", dut.WRITE_PRE_CYC);
        $display("  WRITE_REC    = %0d mclk cycles (tWR)", dut.WRITE_REC_CYC);
        $display("");

        // Run test cases sequentially
        test_single_rw();
        clk_delay(2);
        test_burst_incr();
        clk_delay(2);
        test_burst_wrap();
        clk_delay(2);
        test_burst_fixed();
        clk_delay(2);
        test_byte_strobe();
        clk_delay(2);
        test_read_latency();
        clk_delay(2);
        test_write_latency();
        clk_delay(2);
        test_addr_error();
        clk_delay(2);
        test_sequential();
        clk_delay(2);
        test_id_roundtrip();
        clk_delay(2);
        test_rlast_alignment();
        clk_delay(2);
        test_bvalid_stable();
        clk_delay(2);
        test_rvalid_stable();
        clk_delay(2);
        test_exclusive_access();
        clk_delay(2);
        test_narrow_transfer();
        clk_delay(2);
        test_back_pressure();
        clk_delay(2);

        // Final statistics
        dut.print_statistics();

        $display("========================================================");
        if (fail_cnt == 0)
            $display("  ALL %0d TESTS PASSED", pass_cnt);
        else
            $display("  RESULT: %0d passed, %0d FAILED", pass_cnt, fail_cnt);
        $display("========================================================\n");

        $finish;
    end

    // Global timeout watchdog – prevents infinite simulation
    initial begin
        #(10_000_000);   // 10 ms sim time, generous for 100 MHz aclk + 1200 MHz mclk
        $display("[TB] GLOBAL TIMEOUT – simulation terminated");
        $finish;
    end

endmodule
