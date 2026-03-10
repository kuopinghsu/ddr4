// ============================================================================
// File: uvm/ddr4_axi4_if.sv
// Project: KV32 RISC-V Processor
// Description: AXI4 SystemVerilog interface for DDR4 AXI4 slave UVM testbench
//
// Provides:
//   - All AXI4 write/read channel signals
//   - drv_mp  : driver modport (direct signal access)
//   - mon_mp  : monitor modport (direct signal access, all inputs)
//
// Note: Clocking blocks are intentionally absent.  Output-skew scheduling
// (#1 after posedge) conflicts with blocking-assignment-based driving used
// by the UVM driver and resets signals to zero between clock edges.
// ============================================================================

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off WIDTHEXPAND  */
/* verilator lint_off WIDTHTRUNC   */
/* verilator lint_off TIMESCALEMOD */

`ifndef DDR4_AXI4_IF_SV
`define DDR4_AXI4_IF_SV

interface ddr4_axi4_if #(
    parameter int AXI_DW  = 32,
    parameter int AXI_IDW = 4,
    parameter int AXI_AW  = 32
)(
    input logic aclk,
    input logic aresetn
);
    localparam int AXI_SW = AXI_DW / 8;

    // ── Write address channel ────────────────────────────────────────────────
    logic [AXI_IDW-1:0]  awid;
    logic [AXI_AW-1:0]   awaddr;
    logic [7:0]           awlen;
    logic [2:0]           awsize;
    logic [1:0]           awburst;
    logic                 awlock;
    logic [3:0]           awcache;
    logic [2:0]           awprot;
    logic [3:0]           awqos;
    logic                 awvalid;
    logic                 awready;

    // ── Write data channel ───────────────────────────────────────────────────
    logic [AXI_DW-1:0]   wdata;
    logic [AXI_SW-1:0]   wstrb;
    logic                 wlast;
    logic                 wvalid;
    logic                 wready;

    // ── Write response channel ───────────────────────────────────────────────
    logic [AXI_IDW-1:0]  bid;
    logic [1:0]           bresp;
    logic                 bvalid;
    logic                 bready;

    // ── Read address channel ─────────────────────────────────────────────────
    logic [AXI_IDW-1:0]  arid;
    logic [AXI_AW-1:0]   araddr;
    logic [7:0]           arlen;
    logic [2:0]           arsize;
    logic [1:0]           arburst;
    logic                 arlock;
    logic [3:0]           arcache;
    logic [2:0]           arprot;
    logic [3:0]           arqos;
    logic                 arvalid;
    logic                 arready;

    // ── Read data channel ────────────────────────────────────────────────────
    logic [AXI_IDW-1:0]  rid;
    logic [AXI_DW-1:0]   rdata;
    logic [1:0]           rresp;
    logic                 rlast;
    logic                 rvalid;
    logic                 rready;

    // ── Driver and monitor modports (direct signal access, no clocking blocks)
    // Clocking blocks are intentionally absent: output-skew scheduling (#1 after
    // the clock edge) in simulation conflicts with blocking-assignment driving and
    // resets output signals (e.g. wlast) to zero between clock edges.
    modport drv_mp (
        input  aclk, aresetn,
        input  awready, wready, bid, bresp, bvalid,
               arready, rid, rdata, rresp, rlast, rvalid,
        output awid, awaddr, awlen, awsize, awburst, awlock,
               awcache, awprot, awqos, awvalid,
               wdata, wstrb, wlast, wvalid, bready,
               arid, araddr, arlen, arsize, arburst, arlock,
               arcache, arprot, arqos, arvalid, rready
    );
    modport mon_mp (
        input  aclk, aresetn,
        input  awid, awaddr, awlen, awsize, awburst, awvalid, awready,
               wdata, wstrb, wlast, wvalid, wready,
               bid, bresp, bvalid, bready,
               arid, araddr, arlen, arsize, arburst, arvalid, arready,
               rid, rdata, rresp, rlast, rvalid, rready
    );

    // ── Protocol assertion helpers (optional, wired to interface signals) ────
    // awburst != 2'b11  (reserved)
    // AXI4 implies arvalid/awvalid must not depend on ready — not checkable here

endinterface : ddr4_axi4_if

`endif // DDR4_AXI4_IF_SV
