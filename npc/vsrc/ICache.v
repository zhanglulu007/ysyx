module ICache(
  input clk,
  input rst,

  // ===== CPU 侧 (IFU): AXI4 AR/R 通道 =====
  input             cpu_arvalid,
  output            cpu_arready,
  input  [31:0]     cpu_araddr,
  input  [ 3:0]     cpu_arid,
  input  [ 7:0]     cpu_arlen,
  input  [ 2:0]     cpu_arsize,
  input  [ 1:0]     cpu_arburst,

  output            cpu_rvalid,
  input             cpu_rready,
  output [31:0]     cpu_rdata,
  output [ 1:0]     cpu_rresp,
  output            cpu_rlast,
  output [ 3:0]     cpu_rid,

  // ===== 总线侧 (AXIArbiter): AXI4 AR/R 通道 =====
  output            bus_arvalid,
  input             bus_arready,
  output [31:0]     bus_araddr,
  output [ 3:0]     bus_arid,
  output [ 7:0]     bus_arlen,
  output [ 2:0]     bus_arsize,
  output [ 1:0]     bus_arburst,

  input             bus_rvalid,
  output            bus_rready,
  input  [31:0]     bus_rdata,
  input  [ 1:0]     bus_rresp,
  input             bus_rlast,
  input  [ 3:0]     bus_rid,

  // ===== 性能计数器观测端口 (仅仿真用, 由 ENABLE_PERF 实例化的 PerfCounter 使用) =====
  output icache_access,      // 一次取指访问 (IC_LOOKUP: 请求已被接受, 即将判定命中/缺失)
  output icache_hit,         // 命中 (IC_LOOKUP: 可缓存且命中, 当拍组合应答)
  output icache_miss,        // 缺失 (IC_LOOKUP: 可缓存但未命中, 需回填)
  output icache_uncache,     // 不可缓存访问 (IC_LOOKUP: 地址不在缓存范围, 直通总线)
  output icache_refill_req,  // 向总线发起一次回填/直通读请求 (IC_REFILL_AR)
  output icache_wait_ar,     // 处于等待总线 AR 握手状态 (IC_REFILL_AR)
  output icache_wait_r       // 处于等待总线 R  握手状态 (IC_REFILL_R)
);

  // ===================================================================
  // 可配置参数 (建议后续评估不同配置时调整)
  // ===================================================================
  localparam ADDR_WIDTH   = 32;
  localparam BLOCK_SIZE   = 4;          // 字节 (2^OFFSET_BITS)
  localparam OFFSET_BITS  = 2;          // log2(BLOCK_SIZE)
  localparam NR_CACHE_BLK = 16;         // 2^INDEX_BITS
  localparam INDEX_BITS   = 4;          // log2(NR_CACHE_BLK)
  localparam TAG_BITS     = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS;  // = 26

  // ===================================================================
  // 状态机
  //   IC_IDLE:      等待 IFU 取指请求 (AR 阶段), 与 IFU 的 arready 握手
  //   IC_LOOKUP:    IFU 已进入 WAIT, 本周期查命中/缺失, 决定应答方式
  //   IC_REFILL_AR: 缺失/不可缓存 -> 向 Arbiter 发 AR, 等握手
  //   IC_REFILL_R:  等 Arbiter R 握手; 缺失则回填 cache; 当拍应答 IFU
  // ===================================================================
  localparam IC_IDLE      = 2'b00;
  localparam IC_LOOKUP    = 2'b01;
  localparam IC_REFILL_AR = 2'b10;
  localparam IC_REFILL_R  = 2'b11;

  reg [1:0] state;

  // ===================================================================
  // 存储阵列 (触发器实现, 复位全部无效)
  // ===================================================================
  reg [31:0]         cache_data [0:NR_CACHE_BLK-1];
  reg [TAG_BITS-1:0] cache_tag  [0:NR_CACHE_BLK-1];
  reg                cache_valid[0:NR_CACHE_BLK-1];

  integer i;
  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < NR_CACHE_BLK; i = i + 1) begin
        cache_valid[i] <= 1'b0;
      end
    end
  end

  // ===================================================================
  // 请求信息 (锁存 IFU 的请求, 跨阶段稳定使用)
  // ===================================================================
  reg [31:0] req_addr;
  reg [ 3:0] req_arid;

  // 地址拆解 (基于锁存的 req_addr)
  wire [OFFSET_BITS-1:0] req_offset = req_addr[OFFSET_BITS-1:0];
  wire [INDEX_BITS-1:0]  req_index  = req_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  wire [TAG_BITS-1:0]    req_tag    = req_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];

  // 可缓存地址判定 (高 4 位): Flash=0x3, PSRAM=0x8, SDRAM=0xa
  wire req_cacheable = (req_addr[31:28] == 4'h3) ||
                       (req_addr[31:28] == 4'h8) ||
                       (req_addr[31:28] == 4'ha);

  // 命中判定 (IC_LOOKUP 阶段对锁存地址计算)
  wire hit = cache_valid[req_index] && (cache_tag[req_index] == req_tag);

  // ===================================================================
  // 总线侧 AR 通道 (向 Arbiter 发请求, 由 icache 自身驱动 valid)
  // ===================================================================
  assign bus_arvalid = (state == IC_REFILL_AR) ? 1'b1 : 1'b0;
  assign bus_araddr  = req_addr;
  assign bus_arid    = req_arid;
  assign bus_arlen   = 8'b0;        // 单 beat (len=0)
  assign bus_arsize  = 3'b010;      // 4 字节
  assign bus_arburst = 2'b01;       // INCR

  // ===================================================================
  // 总线侧 R 通道 (接收 Arbiter 返回数据)
  // ===================================================================
  assign bus_rready = (state == IC_REFILL_R);

  // 缺失回填: 仅缓存型请求在 R 握手当拍写入目标 cache 块 (跳过总线错误响应)
  wire do_refill = (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                   req_cacheable && !bus_rresp[1];

  always @(posedge clk) begin
    if (do_refill) begin
      cache_data [req_index] <= bus_rdata;
      cache_tag  [req_index] <= req_tag;
      cache_valid[req_index] <= 1'b1;
    end
  end

  // ===================================================================
  // CPU 侧 (IFU) AR 通道应答
  //   IC_IDLE 时 arready=1, 与 IFU 的 arvalid 握手并锁存请求.
  //   其余阶段 IFU 已离开 IDLE (arvalid 已撤销), arready 无意义, 保持 0.
  // ===================================================================
  assign cpu_arready = (state == IC_IDLE) ? 1'b1 : 1'b0;

  // ===================================================================
  // CPU 侧 (IFU) R 通道应答
  //   命中: IC_LOOKUP 当拍直出 cache 数据 + OK resp + last;
  //   缺失/不可缓存: IC_REFILL_R 握手当拍用 bus 数据应答.
  // ===================================================================
  wire lookup_hit  = (state == IC_LOOKUP)   && req_cacheable &&  hit;
  wire refill_done = (state == IC_REFILL_R) && bus_rvalid && bus_rready;

  assign cpu_rvalid = lookup_hit || refill_done;
  assign cpu_rdata  = lookup_hit ? cache_data[req_index] : bus_rdata;
  assign cpu_rresp  = refill_done ? bus_rresp :  // 透传下游错误标志 (SLVERR/DECERR)
                      2'b00;                      // 命中: 无错误
  assign cpu_rlast  = 1'b1;                       // 本 icache 只处理单 beat 读
  assign cpu_rid    = req_arid;

  // ===================================================================
  // 状态机
  // ===================================================================
  always @(posedge clk) begin
    if (rst) begin
      state    <= IC_IDLE;
      req_addr <= 32'b0;
      req_arid <= 4'b0;
    end else begin
      case (state)
        IC_IDLE: begin
          // IFU 发出取指请求, 本拍握手并锁存请求信息
          if (cpu_arvalid && cpu_arready) begin
            req_addr <= cpu_araddr;
            req_arid <= cpu_arid;
            state    <= IC_LOOKUP;
          end
        end

        IC_LOOKUP: begin
          if (req_cacheable && hit) begin
            // 命中: 本拍已组合逻辑应答 IFU 的 r 通道, 次拍回 IDLE 取下一条指令
            state <= IC_IDLE;
          end else begin
            // 缺失 或 不可缓存: 通过总线读取
            state <= IC_REFILL_AR;
          end
        end

        IC_REFILL_AR: begin
          // 等待总线侧 AR 握手
          if (bus_arready) state <= IC_REFILL_R;
        end

        IC_REFILL_R: begin
          // 等待总线侧 R 握手: 当拍回填(若缓存型)/透传 + 应答 IFU, 次拍回 IDLE
          if (bus_rvalid && bus_rready) state <= IC_IDLE;
        end

        default: state <= IC_IDLE;
      endcase
    end
  end

  // ===================================================================
  // 性能计数器观测信号 (供 PerfCounter 统计 icache 命中率/AMAT)
  // ===================================================================
  assign icache_access     = (state == IC_LOOKUP) && !rst;
  assign icache_hit        = (state == IC_LOOKUP) && req_cacheable &&  hit && !rst;
  assign icache_miss       = (state == IC_LOOKUP) && req_cacheable && !hit && !rst;
  assign icache_uncache    = (state == IC_LOOKUP) && !req_cacheable    && !rst;
  assign icache_refill_req = (state == IC_REFILL_AR)                   && !rst;
  assign icache_wait_ar    = (state == IC_REFILL_AR)                   && !rst;
  assign icache_wait_r     = (state == IC_REFILL_R)                    && !rst;

endmodule
