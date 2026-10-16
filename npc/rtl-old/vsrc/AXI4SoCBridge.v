module AXI4SoCBridge(
  input clk,
  input rst,

  input lite_arvalid,
  output lite_arready,
  input [31:0] lite_araddr,
  input [2:0] lite_arsize,
  output lite_rvalid,
  input lite_rready,
  output [31:0] lite_rdata,
  output [1:0] lite_rresp,

  input lite_awvalid,
  output lite_awready,
  input [31:0] lite_awaddr,
  input [2:0] lite_awsize,
  input lite_wvalid,
  output lite_wready,
  input [31:0] lite_wdata,
  input [3:0] lite_wstrb,
  output lite_bvalid,
  input lite_bready,
  output [1:0] lite_bresp,

  output clint_arvalid,
  input clint_arready,
  output [31:0] clint_araddr,
  output [3:0] clint_arid,
  output [7:0] clint_arlen,
  output [2:0] clint_arsize,
  output [1:0] clint_arburst,
  input clint_rvalid,
  output clint_rready,
  input [31:0] clint_rdata,
  input [1:0] clint_rresp,
  input clint_rlast,
  input [3:0] clint_rid,
  output clint_awvalid,
  input clint_awready,
  output [31:0] clint_awaddr,
  output [3:0] clint_awid,
  output [7:0] clint_awlen,
  output [2:0] clint_awsize,
  output [1:0] clint_awburst,
  output clint_wvalid,
  input clint_wready,
  output [31:0] clint_wdata,
  output [3:0] clint_wstrb,
  output clint_wlast,
  input clint_bvalid,
  output clint_bready,
  input [1:0] clint_bresp,
  input [3:0] clint_bid,

  output mem_arvalid,
  input mem_arready,
  output [31:0] mem_araddr,
  output [3:0] mem_arid,
  output [7:0] mem_arlen,
  output [2:0] mem_arsize,
  output [1:0] mem_arburst,
  input mem_rvalid,
  output mem_rready,
  input [31:0] mem_rdata,
  input [1:0] mem_rresp,
  input mem_rlast,
  input [3:0] mem_rid,
  output mem_awvalid,
  input mem_awready,
  output [31:0] mem_awaddr,
  output [3:0] mem_awid,
  output [7:0] mem_awlen,
  output [2:0] mem_awsize,
  output [1:0] mem_awburst,
  output mem_wvalid,
  input mem_wready,
  output [31:0] mem_wdata,
  output [3:0] mem_wstrb,
  output mem_wlast,
  input mem_bvalid,
  output mem_bready,
  input [1:0] mem_bresp,
  input [3:0] mem_bid
);

  wire read_clint = lite_araddr[31:20] == 12'h020;
  wire write_clint = lite_awaddr[31:20] == 12'h020;
  wire read_flash = lite_araddr[31:24] == 8'h30;
  reg read_route_clint;
  reg write_route_clint;

  wire lite_ar_fire = lite_arvalid && lite_arready;
  wire lite_r_fire = lite_rvalid && lite_rready;
  wire lite_aw_fire = lite_awvalid && lite_awready;
  wire lite_b_fire = lite_bvalid && lite_bready;

  assign mem_arvalid = !rst && lite_arvalid && !read_clint;
  assign mem_araddr = read_flash ? {lite_araddr[31:2], 2'b0} : lite_araddr;
  assign mem_arid = 4'b0;
  assign mem_arlen = 8'b0;
  assign mem_arsize = read_flash ? 3'b010 : lite_arsize;
  assign mem_arburst = 2'b01;

  assign clint_arvalid = !rst && lite_arvalid && read_clint;
  assign clint_araddr = lite_araddr;
  assign clint_arid = 4'b0;
  assign clint_arlen = 8'b0;
  assign clint_arsize = lite_arsize;
  assign clint_arburst = 2'b01;

  assign lite_arready = read_clint ? clint_arready : mem_arready;
  assign lite_rvalid = read_route_clint ? clint_rvalid : mem_rvalid;
  assign lite_rdata = read_route_clint ? clint_rdata : mem_rdata;
  assign lite_rresp = read_route_clint ? clint_rresp : mem_rresp;
  assign clint_rready = read_route_clint && lite_rready;
  assign mem_rready = !read_route_clint && lite_rready;

  assign mem_awvalid = !rst && lite_awvalid && !write_clint;
  assign mem_awaddr = lite_awaddr;
  assign mem_awid = 4'b0;
  assign mem_awlen = 8'b0;
  assign mem_awsize = lite_awsize;
  assign mem_awburst = 2'b01;
  assign mem_wvalid = !rst && lite_wvalid && !write_clint;
  assign mem_wdata = lite_wdata;
  assign mem_wstrb = lite_wstrb;
  assign mem_wlast = mem_wvalid;

  assign clint_awvalid = !rst && lite_awvalid && write_clint;
  assign clint_awaddr = lite_awaddr;
  assign clint_awid = 4'b0;
  assign clint_awlen = 8'b0;
  assign clint_awsize = lite_awsize;
  assign clint_awburst = 2'b01;
  assign clint_wvalid = !rst && lite_wvalid && write_clint;
  assign clint_wdata = lite_wdata;
  assign clint_wstrb = lite_wstrb;
  assign clint_wlast = clint_wvalid;

  assign lite_awready = write_clint ? clint_awready : mem_awready;
  assign lite_wready = write_clint ? clint_wready : mem_wready;
  assign lite_bvalid = write_route_clint ? clint_bvalid : mem_bvalid;
  assign lite_bresp = write_route_clint ? clint_bresp : mem_bresp;
  assign clint_bready = write_route_clint && lite_bready;
  assign mem_bready = !write_route_clint && lite_bready;

  always @(posedge clk) begin
    if (rst) begin
      read_route_clint <= 1'b0;
      write_route_clint <= 1'b0;
    end else begin
      if (lite_ar_fire) begin
        read_route_clint <= read_clint;
      end else if (lite_r_fire) begin
        read_route_clint <= 1'b0;
      end

      if (lite_aw_fire) begin
        write_route_clint <= write_clint;
      end else if (lite_b_fire) begin
        write_route_clint <= 1'b0;
      end
    end
  end

endmodule
