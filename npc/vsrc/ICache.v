// ICache — 最简状态机直通, 用于隔离问题
module ICache #(
  parameter BLOCK_SIZE   = 16,
  parameter NR_CACHE_BLK = 16
)(
  input clk, input rst,
  input cpu_arvalid, output cpu_arready, input [31:0] cpu_araddr, input [3:0] cpu_arid, input [7:0] cpu_arlen, input [2:0] cpu_arsize, input [1:0] cpu_arburst,
  output cpu_rvalid, input cpu_rready, output [31:0] cpu_rdata, output [1:0] cpu_rresp, output cpu_rlast, output [3:0] cpu_rid,
  output bus_arvalid, input bus_arready, output [31:0] bus_araddr, output [3:0] bus_arid, output [7:0] bus_arlen, output [2:0] bus_arsize, output [1:0] bus_arburst,
  input bus_rvalid, output bus_rready, input [31:0] bus_rdata, input [1:0] bus_rresp, input bus_rlast, input [3:0] bus_rid,
  output icache_access, output icache_hit, output icache_miss, output icache_uncache,
  output icache_refill_req, output icache_wait_ar, output icache_wait_r
);
  localparam IC_IDLE = 2'b00, IC_WAIT_AR = 2'b01, IC_WAIT_R = 2'b10;
  reg [1:0] state;
  reg [31:0] req_addr;
  reg [3:0] req_arid;

  assign cpu_arready = (state == IC_IDLE);
  assign bus_arvalid = (state == IC_WAIT_AR);
  assign bus_araddr  = req_addr;
  assign bus_arid    = req_arid;
  assign bus_arlen   = 8'b0;
  assign bus_arsize  = 3'b010;
  assign bus_arburst = 2'b01;

  assign bus_rready  = (state == IC_WAIT_R);
  assign cpu_rvalid  = (state == IC_WAIT_R) && bus_rvalid;
  assign cpu_rdata   = bus_rdata;
  assign cpu_rresp   = bus_rresp;
  assign cpu_rlast   = 1'b1;
  assign cpu_rid     = req_arid;

  always @(posedge clk) begin
    if (rst) begin
      state <= IC_IDLE; req_addr <= 0; req_arid <= 0;
    end else begin
      case (state)
        IC_IDLE: if (cpu_arvalid && cpu_arready) begin
          req_addr <= cpu_araddr; req_arid <= cpu_arid; state <= IC_WAIT_AR;
        end
        IC_WAIT_AR: if (bus_arready) state <= IC_WAIT_R;
        IC_WAIT_R: if (bus_rvalid && bus_rready) state <= IC_IDLE;
        default: state <= IC_IDLE;
      endcase
    end
  end

  assign icache_access = 1'b0;
  assign icache_hit = 1'b0; assign icache_miss = 1'b0; assign icache_uncache = 1'b0;
  assign icache_refill_req = 1'b0; assign icache_wait_ar = 1'b0; assign icache_wait_r = 1'b0;
endmodule
