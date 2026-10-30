module Arbiter(
  input clk,
  input rst,

  // IFU AR (from ICache)
  input        ifu_arvalid,
  output       ifu_arready,
  input [31:0] ifu_araddr,
  input [7:0]  ifu_arlen,
  input [1:0]  ifu_arburst,

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

`ifdef SOC_MODE
  wire ifu_chan = (ifu_araddr >= 32'ha000_0000) && (ifu_araddr < 32'ha200_0000);
  wire lsu_chan = (lsu_araddr >= 32'ha000_0000) && (lsu_araddr < 32'ha200_0000);
`else
  wire ifu_chan = 1'b0;
  wire lsu_chan = 1'b0;
`endif

  reg rd_busy_ifu, rd_busy_lsu;
  reg rd_chan_ifu, rd_chan_lsu;

  wire ch0_used = (rd_busy_ifu && rd_chan_ifu == 1'b0) ||
                  (rd_busy_lsu && rd_chan_lsu == 1'b0);
  wire ch1_used = (rd_busy_ifu && rd_chan_ifu == 1'b1) ||
                  (rd_busy_lsu && rd_chan_lsu == 1'b1);

  wire ifu_free = !(ifu_chan ? ch1_used : ch0_used);
  wire lsu_free = !(lsu_chan ? ch1_used : ch0_used);

  wire ifu_req = ifu_arvalid && ifu_free;
  wire lsu_req = lsu_arvalid && lsu_free;

  localparam [1:0] S_IDLE = 2'd0, S_IFU  = 2'd1, S_LSU  = 2'd2;

  reg [1:0] state;
  reg rr_ifu;

  wire pick_ifu = ifu_req && (!lsu_req || rr_ifu);
  wire pick_lsu = lsu_req && (!ifu_req || !rr_ifu);

  wire sel_ifu = (state == S_IFU) || ((state == S_IDLE) && pick_ifu);
  wire sel_lsu = (state == S_LSU) || ((state == S_IDLE) && pick_lsu);

  assign mem_arvalid = (sel_ifu && ifu_arvalid) || (sel_lsu && lsu_arvalid);
  assign mem_araddr  = sel_ifu ? ifu_araddr : lsu_araddr;
  assign mem_arid    = sel_ifu ? IFU_ID : lsu_arid;
  assign mem_arlen   = sel_ifu ? ifu_arlen : lsu_arlen;
  assign mem_arsize  = sel_ifu ? IFU_SIZE : lsu_arsize;
  assign mem_arburst = sel_ifu ? ifu_arburst : lsu_arburst;

  assign ifu_arready = sel_ifu && mem_arready;
  assign lsu_arready = sel_lsu && mem_arready;

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

  wire ar_open_ifu = ar_fire && sel_ifu;
  wire ar_open_lsu = ar_fire && sel_lsu;

  wire rd_close_ifu = rd_busy_ifu && r_fire && mem_rlast && (mem_rid == IFU_ID);
  wire rd_close_lsu = rd_busy_lsu && r_fire && mem_rlast && (mem_rid == LSU_ID);

  always @(posedge clk) begin
    if (rst) begin
      state       <= S_IDLE;
      rr_ifu      <= 1'b1;
      rd_busy_ifu <= 1'b0;
      rd_busy_lsu <= 1'b0;
      rd_chan_ifu <= 1'b0;
      rd_chan_lsu <= 1'b0;
    end else begin
      case (state)
        S_IDLE: begin
          if (mem_arvalid && !mem_arready) begin
            state <= sel_ifu ? S_IFU : S_LSU;
          end
        end
        S_IFU: begin
          if (!ifu_arvalid || mem_arready) state <= S_IDLE;
        end
        S_LSU: begin
          if (!lsu_arvalid || mem_arready) state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase

      if (ar_fire) begin
        rr_ifu <= ~sel_ifu;
      end else if (!ifu_arvalid && !lsu_arvalid) begin
        rr_ifu <= 1'b1;
      end

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
    end
  end

endmodule