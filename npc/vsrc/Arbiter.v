//============================================================================
// Arbiter.v - AXI read arbitration between I-fetch and LSU.
//
// Demand fetch wins over LSU when both are demanded in the same cycle.
//
// Outstanding reads are tracked per *downstream device channel*, not per
// master: each downstream slot serves one transaction at a time (AXI4RAM keeps
// a single r_full/r_id pair, AXI4ToAPB is a three-state machine, PMEM has one
// read_state).  Two masters may be in flight together only when their targets
// map to different channels -- see the dev_chan() function below.  SDRAM has a
// private AXI4Xbar port in SoC mode; everything else shares one path through
// AXI4Fragmenter, whose single `busy` state machine cannot split two requests
// concurrently.  Requests that cannot be proven to be on separate channels are
// treated as sharing a channel, which is always the safe choice.
//============================================================================
module Arbiter(
  input clk,
  input rst,

  // IFU AR (from ICache)
  input        ifu_arvalid,
  output       ifu_arready,
  input [31:0] ifu_araddr,
  input [7:0]  ifu_arlen,
  input [1:0]  ifu_arburst,
  input        ifu_ar_prefetch,

  // IFU R
  output       ifu_rvalid,
  input        ifu_rready,
  output [31:0] ifu_rdata,
  output       ifu_rlast,

  // LSU AR
  input        lsu_arvalid,
  output       lsu_arready,
  input [31:0] lsu_araddr,
  input [3:0]  lsu_arid,
  input [7:0]  lsu_arlen,
  input [2:0]  lsu_arsize,
  input [1:0]  lsu_arburst,

  // LSU R
  output       lsu_rvalid,
  input        lsu_rready,
  output [1:0] lsu_rresp,
  output [31:0] lsu_rdata,
  output       lsu_rlast,
  output [3:0] lsu_rid,

  // LSU AW
  input        lsu_awvalid,
  output       lsu_awready,
  input [31:0] lsu_awaddr,
  input [3:0]  lsu_awid,
  input [7:0]  lsu_awlen,
  input [2:0]  lsu_awsize,
  input [1:0]  lsu_awburst,

  // LSU W
  input        lsu_wvalid,
  output       lsu_wready,
  input [31:0] lsu_wdata,
  input [3:0]  lsu_wstrb,
  input        lsu_wlast,

  // LSU B
  output       lsu_bvalid,
  input        lsu_bready,
  output [1:0] lsu_bresp,
  output [3:0] lsu_bid,

  // MEM AXI4 AR
  output        mem_arvalid,
  input         mem_arready,
  output [31:0] mem_araddr,
  output [3:0]  mem_arid,
  output [7:0]  mem_arlen,
  output [2:0]  mem_arsize,
  output [1:0]  mem_arburst,

  // MEM AXI4 R
  input         mem_rvalid,
  output        mem_rready,
  input  [1:0]  mem_rresp,
  input  [31:0] mem_rdata,
  input         mem_rlast,
  input  [3:0]  mem_rid,

  // MEM AXI4 AW
  output        mem_awvalid,
  input         mem_awready,
  output [31:0] mem_awaddr,
  output [3:0]  mem_awid,
  output [7:0]  mem_awlen,
  output [2:0]  mem_awsize,
  output [1:0]  mem_awburst,

  // MEM AXI4 W
  output        mem_wvalid,
  input         mem_wready,
  output [31:0] mem_wdata,
  output [3:0]  mem_wstrb,
  output        mem_wlast,

  // MEM AXI4 B
  input         mem_bvalid,
  output        mem_bready,
  input  [1:0]  mem_bresp,
  input  [3:0]  mem_bid
);

  localparam IFU_ID = 4'b0001;
  localparam LSU_ID = 4'b0010;
  localparam [2:0] IFU_SIZE = 3'b010;

  // write path passes straight through
  assign mem_awvalid = lsu_awvalid;
  assign mem_awaddr  = lsu_awaddr;
  assign mem_awid    = lsu_awid;
  assign mem_awlen   = lsu_awlen;
  assign mem_awsize  = lsu_awsize;
  assign mem_awburst = lsu_awburst;
  assign lsu_awready = mem_awready;

  assign mem_wvalid  = lsu_wvalid;
  assign mem_wdata   = lsu_wdata;
  assign mem_wstrb   = lsu_wstrb;
  assign mem_wlast   = lsu_wlast;
  assign lsu_wready  = mem_wready;

  assign lsu_bvalid  = mem_bvalid;
  assign lsu_bresp   = mem_bresp;
  assign lsu_bid     = mem_bid;
  assign mem_bready  = lsu_bready;

  //--------------------------------------------------------------------------
  // Device channel
  //--------------------------------------------------------------------------
  // Concurrency is only safe between requests that reach the memory system
  // through *different* downstream slots.  In SoC mode the AXI4Xbar gives
  // SDRAM its own output port (xbar -> AXI4Delayer -> AXI4SDRAM), while every
  // other slave (XIP flash, the 8KB SRAM, MROM, and the whole APB fan-out for
  // UART/SPI/GPIO/PS2/VGA/PSRAM) hangs off xbar2, which is fed through a single
  // AXI4Fragmenter with one shared `busy` state machine.  Two requests going
  // that way must therefore stay serial even if they target different slaves.
  //
  // Channel 0 = the shared/Fragmenter path, channel 1 = the private SDRAM path.
  // Anything not provably on the private path is treated as channel 0, which is
  // always the safe (serialising) choice.
  //
  // In standalone mode there is only PMEM with a single `read_state`, so every
  // address maps to channel 0 and behaviour degrades to the previous global lock.
  function dev_chan;
    input [31:0] addr;
    begin
`ifdef SOC_MODE
      dev_chan = (addr >= 32'ha000_0000) && (addr < 32'ha200_0000);
`else
      dev_chan = 1'b0;
`endif
    end
  endfunction

  wire ifu_chan = dev_chan(ifu_araddr);
  wire lsu_chan = dev_chan(lsu_araddr);

  //--------------------------------------------------------------------------
  // Read arbitration
  //--------------------------------------------------------------------------
  // One outstanding read per *channel*, not per master: each downstream slot
  // accepts exactly one transaction (AXI4RAM keeps a single r_full/r_id pair,
  // AXI4ToAPB is a three-state machine, PMEM has one read_state).  A master is
  // only allowed to start when its target channel is idle.
  reg rd_busy_ifu, rd_busy_lsu;
  reg rd_chan_ifu, rd_chan_lsu;   // channel of the transaction in flight

  wire ch0_used = (rd_busy_ifu && rd_chan_ifu == 1'b0) ||
                  (rd_busy_lsu && rd_chan_lsu == 1'b0);
  wire ch1_used = (rd_busy_ifu && rd_chan_ifu == 1'b1) ||
                  (rd_busy_lsu && rd_chan_lsu == 1'b1);

  wire ifu_free = !(ifu_chan ? ch1_used : ch0_used);
  wire lsu_free = !(lsu_chan ? ch1_used : ch0_used);

  // Priority must be built from "free AND requesting", otherwise a master that
  // is blocked on a busy channel would still mask the other one and no grant
  // would be issued at all.
  wire ifu_grant = ifu_free && ifu_arvalid;
  wire lsu_grant = lsu_free && lsu_arvalid;

  // Simultaneous demand: I-fetch wins.  LSU only wins when it is a real
  // alternative, i.e. I-fetch is not asking, or it is a prefetch.
  wire lsu_first = lsu_grant && (!ifu_grant || ifu_ar_prefetch);

  // AR issue / hold.  AXI4 forbids changing the payload or dropping valid
  // while valid is asserted and ready has not come back.  Grants are
  // re-evaluated every cycle here, so the winner must be latched until the
  // transfer is actually accepted.
  reg ar_hold;
  reg ar_hold_ifu;

  wire ifu_sel = ar_hold ?  ar_hold_ifu : (ifu_grant && !lsu_first);
  wire lsu_sel = ar_hold ? !ar_hold_ifu : (lsu_grant && lsu_first);

  // A held grant still needs valid from its source, so a stale grant cannot
  // turn into a phantom request.
  assign mem_arvalid = (ifu_sel && ifu_arvalid) || (lsu_sel && lsu_arvalid);
  assign mem_araddr  = ifu_sel ? ifu_araddr : lsu_araddr;
  assign mem_arid    = ifu_sel ? IFU_ID : lsu_arid;
  assign mem_arlen   = ifu_sel ? ifu_arlen : lsu_arlen;
  assign mem_arsize  = ifu_sel ? IFU_SIZE : lsu_arsize;
  assign mem_arburst = ifu_sel ? ifu_arburst : lsu_arburst;

  assign ifu_arready = ifu_sel && mem_arready;
  assign lsu_arready = lsu_sel && mem_arready;

  assign ifu_rvalid  = mem_rvalid && (mem_rid == IFU_ID);
  assign ifu_rdata   = mem_rdata;
  assign ifu_rlast   = mem_rlast;

  assign lsu_rvalid  = mem_rvalid && (mem_rid == LSU_ID);
  assign lsu_rresp   = mem_rresp;
  assign lsu_rdata   = mem_rdata;
  assign lsu_rlast   = mem_rlast;
  assign lsu_rid     = mem_rid;

  assign mem_rready  = (mem_rid == IFU_ID) ? ifu_rready : lsu_rready;

  wire ar_fire = mem_arvalid && mem_arready;
  wire r_fire  = mem_rvalid && mem_rready;

  // Occupy the channel for *every* request, single-beat included.  A single
  // beat still holds the downstream slot for a cycle or more (r_full in
  // AXI4RAM, the APB state machine), and reclaiming the slot early would let a
  // second request overwrite r_id while the first response is still pending.
  wire ar_open_ifu = ar_fire && ifu_sel;
  wire ar_open_lsu = ar_fire && lsu_sel;

  // Release whichever master's transaction just completed, matched by ID.
  wire rd_close_ifu = rd_busy_ifu && r_fire && mem_rlast && (mem_rid == IFU_ID);
  wire rd_close_lsu = rd_busy_lsu && r_fire && mem_rlast && (mem_rid == LSU_ID);

  always @(posedge clk) begin
    if (rst) begin
      rd_busy_ifu <= 1'b0;
      rd_busy_lsu <= 1'b0;
      rd_chan_ifu <= 1'b0;
      rd_chan_lsu <= 1'b0;
      ar_hold     <= 1'b0;
      ar_hold_ifu <= 1'b0;
    end else begin
      if (ar_open_ifu) begin
        rd_busy_ifu <= 1'b1;
        rd_chan_ifu <= ifu_chan;
      end else if (rd_close_ifu) begin
        rd_busy_ifu <= 1'b0;
      end

      if (ar_open_lsu) begin
        rd_busy_lsu <= 1'b1;
        rd_chan_lsu <= lsu_chan;
      end else if (rd_close_lsu) begin
        rd_busy_lsu <= 1'b0;
      end

      // Latch the winner while valid is asserted but not yet accepted, and
      // release it on the accepted transfer so payload/valid stay stable.
      if (ar_fire) begin
        ar_hold     <= 1'b0;
        ar_hold_ifu <= 1'b0;
      end else if (mem_arvalid) begin
        ar_hold     <= 1'b1;
        ar_hold_ifu <= ifu_sel;
      end else begin
        ar_hold     <= 1'b0;   // source withdrew valid; drop the stale grant
        ar_hold_ifu <= 1'b0;
      end
    end
  end

endmodule
