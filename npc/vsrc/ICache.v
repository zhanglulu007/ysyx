// ICache - Instruction Cache
//
// 可配置参数:
//   BLOCK_SIZE   = 4/8/16/32/64 字节 (2 的幂)
//   NR_CACHE_BLK = cache 块总数 (2 的幂)
//
// 块大小 > 4B 时, 总线侧采用 AXI 突发传输 (arlen = BLOCK_SIZE/4 - 1)
// 读回多 beat 数据后按 beat 序号写入存储阵列对应 word 位置.
// CPU 侧 (IFU): 仍然只发单 beat 读请求 (一次性读出所需指令),
//               ICache 在内部将多 beat 对应为正确的 word 返回.
//
// 地址划分 (块大小>4B 且组数>1):
//   [31:tag_bits+index_bits]  tag
//   [tag_bits+index_bits-1:offset_bits]  index
//   [offset_bits-1:0]  offset
//   其中 offset 的高位指示 word 索引: word_idx = offset[offset_bits-1:2]

module ICache #(
  parameter ADDR_WIDTH   = 32,
  parameter BLOCK_SIZE   = 16,          // 字节 (2^OFFSET_BITS)
  parameter OFFSET_BITS  = 2,          // log2(BLOCK_SIZE)
  parameter NR_CACHE_BLK = 16,
  parameter INDEX_BITS   = 4,          // log2(NR_CACHE_BLK)
  parameter TAG_BITS     = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS,
  parameter BUS_DATA_BYTES = 4         // AXI 数据位宽 (字节)
) (
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

  // ===== 性能计数器观测端口 (仅仿真用) =====
  output icache_access,      // 一次取指访问 (IC_LOOKUP)
  output icache_hit,         // 命中 (IC_LOOKUP: 可缓存且命中)
  output icache_miss,        // 缺失 (IC_LOOKUP: 可缓存但未命中)
  output icache_uncache,     // 不可缓存访问 (IC_LOOKUP)
  output icache_refill_req,  // 向总线发起一次回填/直通读请求 (IC_REFILL_AR)
  output icache_wait_ar,     // 处于等待总线 AR 握手状态 (IC_REFILL_AR)
  output icache_wait_r       // 处于等待总线 R  握手状态 (IC_REFILL_R)
);

  // ===================================================================
  // 派生参数
  // ===================================================================
  // 每 cache 块所含的 32 位字数
  localparam WORDS_PER_BLOCK = BLOCK_SIZE / 4;

  // word 索引位数: 指示 ICache 块内第几个 32 位字
  localparam WORD_IDX_BITS =
    (WORDS_PER_BLOCK <= 1) ? 0 :
    (WORDS_PER_BLOCK == 2) ? 1 :
    (WORDS_PER_BLOCK == 4) ? 2 :
    (WORDS_PER_BLOCK == 8) ? 3 : 4;

  // beat 计数器位宽: 与 WORD_IDX_BITS 保持一致
  localparam BEAT_CNT_WIDTH = (WORD_IDX_BITS > 0) ? WORD_IDX_BITS : 1;

  localparam BEAT_CNT_ZERO  = {BEAT_CNT_WIDTH{1'b0}};

  // ===================================================================
  // 状态机
  //   IC_IDLE:      等待 IFU 取指请求 (AR 阶段), 与 IFU 的 arready 握手
  //   IC_LOOKUP:    IFU 已进入 WAIT, 本周期查命中/缺失, 决定应答方式
  //   IC_REFILL_AR: 缺失/不可缓存 -> 向 Arbiter 发 AR, 等握手
  //   IC_REFILL_R:  等 Arbiter R 握手, 多 beat 累计回填; 当 beat 命中 IFU 请求 word 时应答
  // ===================================================================
  localparam IC_IDLE      = 2'b00;
  localparam IC_LOOKUP    = 2'b01;
  localparam IC_REFILL_AR = 2'b10;
  localparam IC_REFILL_R  = 2'b11;

  reg [1:0] state;
  reg [BEAT_CNT_WIDTH-1:0] refill_beat_cnt;

  // ===================================================================
  // 存储阵列 (触发器实现, 复位全部无效)
  //   cache_data[NR_CACHE_BLK-1:0][WORDS_PER_BLOCK-1:0][31:0]
  // ===================================================================
  reg [31:0]         cache_data [0:NR_CACHE_BLK-1] [0:WORDS_PER_BLOCK-1];
  reg [TAG_BITS-1:0] cache_tag  [0:NR_CACHE_BLK-1];
  reg                cache_valid[0:NR_CACHE_BLK-1];

  integer i, j;
  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < NR_CACHE_BLK; i = i + 1) begin
        cache_valid[i] <= 1'b0;
`ifndef SYNTHESIS
        for (j = 0; j < WORDS_PER_BLOCK; j = j + 1) begin
          cache_data[i][j] <= 32'b0;
        end
`endif
      end
    end
  end

  // ===================================================================
  // 请求信息 (锁存 IFU 的请求, 跨阶段稳定使用)
  // ===================================================================
  reg [31:0] req_addr;
  reg [ 3:0] req_arid;

  // 地址拆解 (基于锁存的 req_addr)
  // req_offset: 块内字节偏移 (仅用于 debug)
  // req_index:  cache 索引
  // req_tag:    tag 比较
  wire [OFFSET_BITS-1:0]        req_offset = req_addr[OFFSET_BITS-1:0];
  wire [INDEX_BITS-1:0]         req_index  = req_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  wire [TAG_BITS-1:0]           req_tag    = req_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];

  // req_word_idx: 取指地址在 cache 块内的 word 索引 (0-based, 每个 word=4B)
  // BLOCK_SIZE=4 (WORDS_PER_BLOCK=1): word 索引恒为 0
  // BLOCK_SIZE>4: 从 addr[OFFSET_BITS-1:2] 提取 (OFFSET_BITS>=3, 故 OFFSET_BITS-1>=2, 范围始终正向)
  localparam REQ_WORD_HI = (WORDS_PER_BLOCK == 1) ? 2 : (OFFSET_BITS - 1);
  wire [BEAT_CNT_WIDTH-1:0] req_word_idx =
    (WORDS_PER_BLOCK == 1) ? {BEAT_CNT_WIDTH{1'b0}} : req_addr[REQ_WORD_HI:2];

  // 可缓存地址判定 (高 4 位): Flash=0x3, PSRAM=0x8, SDRAM=0xa
  wire req_cacheable = (req_addr[31:28] == 4'h3) ||
                        (req_addr[31:28] == 4'h8) ||
                        (req_addr[31:28] == 4'ha);

  // 命中判定 (IC_LOOKUP 阶段对锁存地址计算)
  wire hit = cache_valid[req_index] && (cache_tag[req_index] == req_tag);

  // ===================================================================
  // 总线侧 AR 通道 (向 Arbiter 发突发请求)
  // ===================================================================
  assign bus_arvalid = (state == IC_REFILL_AR) ? 1'b1 : 1'b0;
  assign bus_araddr  = {req_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};  // 块对齐
  assign bus_arid    = req_arid;
  assign bus_arlen   = WORDS_PER_BLOCK[7:0] - 8'd1;  // 突发长度 = 字数 - 1
  assign bus_arsize  = 3'b010;                        // 4 字节
  assign bus_arburst = 2'b01;                         // INCR

  // ===================================================================
  // 总线侧 R 通道 (接收 Arbiter 返回数据)
  // ===================================================================
  assign bus_rready = (state == IC_REFILL_R);

  // 缺失回填: 缓存型请求在 R 握手当拍按 beat_cnt 写入
  wire do_refill = (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                   req_cacheable && !bus_rresp[1];

  always @(posedge clk) begin
    if (do_refill) begin
      cache_data[req_index][refill_beat_cnt] <= bus_rdata;
      cache_tag  [req_index]                  <= req_tag;
      cache_valid[req_index]                  <= 1'b1;
    end
  end

  // ===================================================================
  // CPU 侧 (IFU) AR 通道应答
  //   IC_IDLE 时 arready=1, 与 IFU 的 arvalid 握手并锁存请求.
  // ===================================================================
  assign cpu_arready = (state == IC_IDLE) ? 1'b1 : 1'b0;

  // ===================================================================
  // CPU 侧 (IFU) R 通道应答
  //   命中: IC_LOOKUP 当拍直出 cache 数据 + OK resp + last;
  //   缺失: IC_REFILL_R 中当 beat_cnt 匹配 req_word_idx 时, 用该 beat 的数据应答 IFU
  //         即使 req_word 不在最后一个 beat, 也先放通 (IFU 可继续执行)
  //        refill_done (rlast 握手的最后一拍) 也应答 IFU (兜底, 确保不会丢失响应)
  // ===================================================================
  wire lookup_hit      = (state == IC_LOOKUP)   && req_cacheable &&  hit;
  wire refill_hit_req  = (state == IC_REFILL_R) && bus_rvalid && (refill_beat_cnt == req_word_idx);
  wire refill_done     = (state == IC_REFILL_R) && bus_rvalid && bus_rready && bus_rlast;

  assign cpu_rvalid = lookup_hit || refill_hit_req || refill_done;
  assign cpu_rdata  = lookup_hit ? cache_data[req_index][req_word_idx] :
                      (refill_hit_req || refill_done) ? bus_rdata : 32'b0;
  assign cpu_rresp  = refill_done ? bus_rresp :  // 透传下游错误标志
                      2'b00;                       // 命中: 无错误
  assign cpu_rlast  = 1'b1;                       // CPU 侧始终单 beat
  assign cpu_rid    = req_arid;

  // ===================================================================
  // beat 计数器 (IC_REFILL_R 期间递增)
  // ===================================================================
  wire beat_tick = (state == IC_REFILL_R) && bus_rvalid && bus_rready;

  always @(posedge clk) begin
    if (rst || (state == IC_IDLE) || (state == IC_LOOKUP)) begin
      refill_beat_cnt <= BEAT_CNT_ZERO;
    end else if (beat_tick && !bus_rlast) begin
      refill_beat_cnt <= refill_beat_cnt + 1'b1;
    end else if (beat_tick && bus_rlast) begin
      refill_beat_cnt <= BEAT_CNT_ZERO;
    end
  end

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
            state <= IC_IDLE;
          end else begin
            state <= IC_REFILL_AR;
          end
        end

        IC_REFILL_AR: begin
          if (bus_arready) state <= IC_REFILL_R;
        end

        IC_REFILL_R: begin
          if (bus_rvalid && bus_rready && bus_rlast) begin
            state <= IC_IDLE;
          end
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