module CLINT(
  input clk,
  input rst,
  input [63:0] mtime,

  // AXI4 AR
  input clint_arvalid,
  output clint_arready,
  input [31:0] clint_araddr,
  input [3:0] clint_arid,
  input [7:0] clint_arlen,
  input [2:0] clint_arsize,
  input [1:0] clint_arburst,

  // AXI4 R
  output clint_rvalid,
  input clint_rready,
  output [1:0] clint_rresp,
  output [31:0] clint_rdata,
  output clint_rlast,
  output [3:0] clint_rid,

  // AXI4 AW
  input clint_awvalid,
  output clint_awready,
  input [31:0] clint_awaddr,
  input [3:0] clint_awid,
  input [7:0] clint_awlen,
  input [2:0] clint_awsize,
  input [1:0] clint_awburst,

  // AXI4 W
  input clint_wvalid,
  output clint_wready,
  input [31:0] clint_wdata,
  input [3:0] clint_wstrb,
  input clint_wlast,

  // AXI4 B
  output clint_bvalid,
  input clint_bready,
  output [1:0] clint_bresp,
  output [3:0] clint_bid
);

  localparam IDLE = 1'b0;
  localparam WAIT = 1'b1;

  reg read_state;
  reg write_state;
  reg aw_done;
  reg w_done;
  reg [31:0] rdata_reg;
  reg [3:0] rid_reg;
  reg [3:0] bid_reg;

  wire is_mtime_lo = clint_araddr[15:0] == 16'hbff8;
  wire is_mtime_hi = clint_araddr[15:0] == 16'hbffc;
  wire ar_fire = clint_arvalid && clint_arready;
  wire r_fire = clint_rvalid && clint_rready;
  wire aw_fire = clint_awvalid && clint_awready;
  wire w_fire = clint_wvalid && clint_wready;
  wire aw_complete = aw_done || aw_fire;
  wire w_complete = w_done || w_fire;
  wire b_fire = clint_bvalid && clint_bready;

  assign clint_arready = !rst && (read_state == IDLE);
  assign clint_rvalid = !rst && (read_state == WAIT);
  assign clint_rresp = 2'b00;
  assign clint_rdata = rdata_reg;
  assign clint_rlast = clint_rvalid;
  assign clint_rid = rid_reg;

  assign clint_awready = !rst && (write_state == IDLE) && !aw_done;
  assign clint_wready = !rst && (write_state == IDLE) && !w_done;
  assign clint_bvalid = !rst && (write_state == WAIT);
  assign clint_bresp = 2'b10;
  assign clint_bid = bid_reg;

  always @(posedge clk) begin
    if (rst) begin
      read_state <= IDLE;
      write_state <= IDLE;
      aw_done <= 1'b0;
      w_done <= 1'b0;
      rdata_reg <= 32'b0;
      rid_reg <= 4'b0;
      bid_reg <= 4'b0;
    end else begin
      case (read_state)
        IDLE: begin
          if (ar_fire) begin
            case (1'b1)
              is_mtime_lo: rdata_reg <= mtime[31:0];
              is_mtime_hi: rdata_reg <= mtime[63:32];
              default: rdata_reg <= 32'b0;
            endcase
            rid_reg <= clint_arid;
            read_state <= WAIT;
          end
        end
        WAIT: begin
          if (r_fire) begin
            read_state <= IDLE;
          end
        end
        default: read_state <= IDLE;
      endcase

      case (write_state)
        IDLE: begin
          if (aw_fire) begin
            bid_reg <= clint_awid;
            aw_done <= 1'b1;
          end
          if (w_fire) begin
            w_done <= 1'b1;
          end
          if (aw_complete && w_complete) begin
            aw_done <= 1'b0;
            w_done <= 1'b0;
            write_state <= WAIT;
          end
        end
        WAIT: begin
          if (b_fire) begin
            write_state <= IDLE;
          end
        end
        default: write_state <= IDLE;
      endcase
    end
  end

endmodule
