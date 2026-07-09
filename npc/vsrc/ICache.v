// ICache — 指令缓存 (支持可配置块大小 + 突发传输)
//
// 参考: 讲义 B4.md "支持更大的块大小(2)" (813-814行) 及 "让icache支持突发传输" (839-840行)
//
// 可配置参数 (通过 localparam, 便于后续设计空间探索):
//   BLOCK_SIZE:   缓存块大小 (字节), 须为 4 的整数倍且是 2 的幂 (≥4)
//   NR_CACHE_BLK: 缓存块总数, 须为 2 的幂
//
// 地址划分 (组相联, 默认 ways=1 → 直接映射):
//   [31 : OFFSET_BITS+INDEX_BITS] = tag
//   [OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS] = index
//   [OFFSET_BITS-1 : 0] = offset (字节偏移, 低2位恒为0)
//     offset 的高位 [OFFSET_BITS-1:2] 选择块内 word

module ICache #(
  parameter BLOCK_SIZE   = 16,   // 块大小 (字节), 默认 16B (= 4×总线位宽)
  parameter NR_CACHE_BLK = 16    // 缓存块数, 默认 16
)(
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

  // ===== 性能计数器观测端口 =====
  output icache_access,
  output icache_hit,
  output icache_miss,
  output icache_uncache,
  output icache_refill_req,
  output icache_wait_ar,
  output icache_wait_r
);

  // ===================================================================
  // 可配置参数推导
  // ===================================================================
  localparam ADDR_WIDTH      = 32;
  localparam BUS_WIDTH       = 4;       // 总线数据位宽 4 字节 (32-bit AXI)
  localparam NR_WORDS        = BLOCK_SIZE / BUS_WIDTH;   // 每块包含 word 数
  localparam OFFSET_BITS     = $clog2(BLOCK_SIZE);       // 块内偏移位宽
  localparam WORD_IDX_BITS   = (OFFSET_BITS > 2) ? (OFFSET_BITS - 2) : 1;  // 块内 word 索引位宽
  localparam INDEX_BITS      = $clog2(NR_CACHE_BLK);    // 索引位宽
  localparam TAG_BITS        = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS;
  localparam BEAT_CNT_BITS   = (NR_WORDS > 1) ? $clog2(NR_WORDS) : 1;  // beat 计数器位宽
  localparam BURST_LEN       = NR_WORDS - 1;  // AXI arlen = 节拍数 - 1

  // ===================================================================
  // 状态机
  //   IC_IDLE:      等待 IFU 取指请求 (AR 阶段), 与 IFU 的 arready 握手
  //   IC_LOOKUP:    IFU 已进入 WAIT, 本周期查命中/缺失, 决定应答方式
  //   IC_REFILL_AR: 缺失/不可缓存 -> 向 Arbiter 发 AR, 等握手
  //   IC_REFILL_R:  等 Arbiter R 握手; 缺失则逐 beat 回填 cache; 完成后应答 IFU
  // ===================================================================
  localparam IC_IDLE      = 2'b00;
  localparam IC_LOOKUP    = 2'b01;
  localparam IC_REFILL_AR = 2'b10;
  localparam IC_REFILL_R  = 2'b11;

  reg [1:0] state;

  // ===================================================================
  // 存储阵列 (触发器实现, 复位全部无效)
  // 每个 cache 块存储 BLOCK_SIZE 字节 (BLOCK_SIZE*8 位宽)
  // ===================================================================
  reg [(BLOCK_SIZE*8)-1:0] cache_data [0:NR_CACHE_BLK-1];
  reg [TAG_BITS-1:0]       cache_tag  [0:NR_CACHE_BLK-1];
  reg                      cache_valid[0:NR_CACHE_BLK-1];

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
  wire [OFFSET_BITS-1:0]    req_offset    = req_addr[OFFSET_BITS-1:0];
  wire [INDEX_BITS-1:0]     req_index     = req_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  wire [TAG_BITS-1:0]       req_tag       = req_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];
  wire [WORD_IDX_BITS-1:0]  req_word_idx  = (OFFSET_BITS > 2) ? req_addr[OFFSET_BITS-1:2] : {WORD_IDX_BITS{1'b0}};

  // 可缓存地址判定 (高 4 位): Flash=0x3, PSRAM=0x8, SDRAM=0xa
  wire req_cacheable = (req_addr[31:28] == 4'h3) ||
                       (req_addr[31:28] == 4'h8) ||
                       (req_addr[31:28] == 4'ha);

  // 命中判定 (IC_LOOKUP 阶段对锁存地址计算)
  wire hit = cache_valid[req_index] && (cache_tag[req_index] == req_tag);

  // ===================================================================
  // 块对齐地址 (用于突发传输: 将地址低 OFFSET_BITS 位清零)
  // ===================================================================
  wire [31:0] block_aligned_addr;
  assign block_aligned_addr = {req_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};

  // ===================================================================
  // 总线侧 AR 通道
  //   - 缓存型缺失: 突发传输, arlen = BURST_LEN, 地址 = 块对齐地址
  //   - 不可缓存:   单 beat,   arlen = 0,         地址 = 原始请求地址
  // ===================================================================
  wire is_burst = req_cacheable && (NR_WORDS > 1);

  assign bus_arvalid = (state == IC_REFILL_AR) ? 1'b1 : 1'b0;
  assign bus_araddr  = is_burst ? block_aligned_addr : req_addr;
  assign bus_arid    = req_arid;
  assign bus_arlen   = is_burst ? (BURST_LEN) : 8'b0;
  assign bus_arsize  = 3'b010;       // 4 字节/beat
  assign bus_arburst = 2'b01;        // INCR

  // ===================================================================
  // 总线侧 R 通道 (接收 Arbiter 返回数据)
  //   - 缓存型: 逐 beat 回填, 在最后一个 beat 完成时统一写 tag/valid
  //   - 不可缓存: 单 beat 透传, 不写 cache
  // ===================================================================
  assign bus_rready = (state == IC_REFILL_R);

  // beat 计数器 (仅缓存型 + 多 beat 时使用)
  reg [BEAT_CNT_BITS-1:0] beat_cnt;

  // 逐 beat 写入数据: 在 IC_REFILL_R 每个 R 握手时, 将 bus_rdata 写入对应 word 位置
  wire do_refill_beat = (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                        req_cacheable && !bus_rresp[1];

  always @(posedge clk) begin
    if (rst) begin
      beat_cnt <= {BEAT_CNT_BITS{1'b0}};
    end else if (state == IC_REFILL_AR && bus_arready) begin
      // 进入 REFILL_R 前清零 beat 计数器
      beat_cnt <= {BEAT_CNT_BITS{1'b0}};
    end else if (do_refill_beat) begin
      // 每个 beat 写入对应 word, 递增计数器
      cache_data[req_index][(beat_cnt * 32) +: 32] <= bus_rdata;
      beat_cnt <= beat_cnt + 1'b1;
    end
  end

  // 回填完成: 缓存型请求在最后一个 R beat 握手时, 写 tag 和 valid
  wire do_refill_done = (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                        req_cacheable && !bus_rresp[1] && bus_rlast;

  always @(posedge clk) begin
    if (do_refill_done) begin
      cache_tag  [req_index] <= req_tag;
      cache_valid[req_index] <= 1'b1;
    end
  end

  // ===================================================================
  // CPU 侧 (IFU) AR 通道应答
  // ===================================================================
  assign cpu_arready = (state == IC_IDLE) ? 1'b1 : 1'b0;

  // ===================================================================
  // CPU 侧 (IFU) R 通道应答
  //   命中:      IC_LOOKUP 当拍直出 cache 数据 + OK resp + last;
  //   缺失/不可缓存: IC_REFILL_R 最后一个 beat 握手当拍应答.
  // ===================================================================
  wire lookup_hit  = (state == IC_LOOKUP)   && req_cacheable &&  hit;
  // refill_done: 不可缓存时单 beat 即完成; 缓存型缺失时最后一个 beat 完成
  wire refill_done = (state == IC_REFILL_R) && bus_rvalid && bus_rready && bus_rlast;

  // 命中时从 cache_data 中选取对应 word
  wire [31:0] hit_word;
  assign hit_word = cache_data[req_index][(req_word_idx * 32) +: 32];

  assign cpu_rvalid = lookup_hit || refill_done;
  assign cpu_rdata  = lookup_hit ? hit_word : bus_rdata;
  assign cpu_rresp  = refill_done ? bus_rresp : 2'b00;
  assign cpu_rlast  = 1'b1;    // CPU 侧始终单 beat 应答
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
          if (cpu_arvalid && cpu_arready) begin
            req_addr <= cpu_araddr;
            req_arid <= cpu_arid;
            state    <= IC_LOOKUP;
          end
        end

        IC_LOOKUP: begin
          if (req_cacheable && hit) begin
            // 命中: 本拍已组合逻辑应答 IFU, 次拍回 IDLE
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
          // 等待总线侧最后一个 R beat 握手: 当拍回填/透传 + 应答 IFU, 次拍回 IDLE
          if (bus_rvalid && bus_rready && bus_rlast) state <= IC_IDLE;
        end

        default: state <= IC_IDLE;
      endcase
    end
  end

  // ===================================================================
  // 性能计数器观测信号
  // ===================================================================
  assign icache_access     = (state == IC_LOOKUP) && !rst;
  assign icache_hit        = (state == IC_LOOKUP) && req_cacheable &&  hit && !rst;
  assign icache_miss       = (state == IC_LOOKUP) && req_cacheable && !hit && !rst;
  assign icache_uncache    = (state == IC_LOOKUP) && !req_cacheable    && !rst;
  assign icache_refill_req = (state == IC_REFILL_AR)                   && !rst;
  assign icache_wait_ar    = (state == IC_REFILL_AR)                   && !rst;
  assign icache_wait_r     = (state == IC_REFILL_R)                    && !rst;

endmodule
