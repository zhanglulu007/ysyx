module ICache (
  input clk,
  input rst,

  // IFU AXI4 AR
  input ifu_arvalid,
  output ifu_arready,
  input [31:0] ifu_araddr,
  input [3:0] ifu_arid,
  input [7:0] ifu_arlen,
  input [2:0] ifu_arsize,
  input [1:0] ifu_arburst,

  // IFU AXI4 R
  output ifu_rvalid,
  input ifu_rready,
  output [1:0] ifu_rresp,
  output [31:0] ifu_rdata,
  output ifu_rlast,
  output [3:0] ifu_rid,

  // AXI4 AR to Arbiter
  output arvalid,
  input arready,
  output [31:0] araddr,
  output [3:0] arid,
  output [7:0] arlen,
  output [2:0] arsize,
  output [1:0] arburst,

  // AXI4 R to Arbiter
  input rvalid,
  output rready,
  input [1:0] rresp,
  input [31:0] rdata,
  input rlast,
  input [3:0] rid,

  output icache_access,       // IFU 发出一次取指请求
  output icache_hit,          // 命中
  output icache_miss,         // 缺失
  output icache_refill,       // 缺失时发起一次总线 AR
  output icache_miss_ar_wait, // 缺失等待 AR 握手的周期
  output icache_miss_r_wait   // 缺失等待 R 数据的周期

);

  localparam BLOCKS = 16;
  localparam INDEX_BITS = 4;
  localparam TAG_BITS = 26;
  localparam OFFSET_BITS = 2;

  localparam IDLE = 2'b00;
  localparam MISS_AR = 2'b01;
  localparam MISS_R = 2'b10;
  localparam RETURN = 2'b11;

  reg [TAG_BITS+31:0] cache [0:BLOCKS-1];
  reg [BLOCKS-1:0] cache_valid;
  reg [1:0] state;

  reg [TAG_BITS-1:0] req_tag;
  reg [INDEX_BITS-1:0] req_index;

  wire [INDEX_BITS-1:0] req_index_in = ifu_araddr[5:2];
  wire [TAG_BITS-1:0] req_tag_in = ifu_araddr[31:6];
  wire hit = cache_valid[req_index_in] &&
             (cache[req_index_in][TAG_BITS+31:32] == req_tag_in);

  assign ifu_arready = !rst && (state == IDLE);
  assign ifu_rvalid  = !rst && (state == RETURN);
  assign ifu_rdata   = cache[req_index][31:0];
  assign ifu_rresp   = 2'b00;
  assign ifu_rlast   = 1'b1;
  assign ifu_rid     = 4'b0001;

  assign arvalid = !rst && (state == MISS_AR);
  assign araddr  = {req_tag, req_index, {OFFSET_BITS{1'b0}}};
  assign arid    = 4'b0001;
  assign arlen   = 8'b0;
  assign arsize  = 3'b010;
  assign arburst = 2'b01;

  assign rready  = !rst && (state == MISS_R);

  // 性能计数器观测信号
  assign icache_access       = !rst && (state == IDLE) && ifu_arvalid && ifu_arready;
  assign icache_hit          = icache_access && hit;
  assign icache_miss         = icache_access && !hit;
  assign icache_refill       = !rst && (state == MISS_AR) && arvalid && arready;
  assign icache_miss_ar_wait = !rst && (state == MISS_AR);
  assign icache_miss_r_wait  = !rst && (state == MISS_R);

  always @(posedge clk) begin
    if (rst) begin
      cache_valid <= {BLOCKS{1'b0}};
      state <= IDLE;
      req_tag <= {TAG_BITS{1'b0}};
      req_index <= {INDEX_BITS{1'b0}};
    end else begin
      case (state)
        IDLE: begin
          if (ifu_arvalid && ifu_arready) begin
            req_tag <= req_tag_in;
            req_index <= req_index_in;
            if (hit) begin
              state <= RETURN;
            end else begin
              state <= MISS_AR;
            end
          end
        end

        MISS_AR: begin
          if (arvalid && arready) begin
            state <= MISS_R;
          end
        end

        MISS_R: begin
          if (rvalid && rready && rlast) begin
            cache[req_index] <= {req_tag, rdata};
            cache_valid[req_index] <= 1'b1;
            state <= RETURN;
          end
        end

        RETURN: begin
          if (ifu_rvalid && ifu_rready) begin
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
