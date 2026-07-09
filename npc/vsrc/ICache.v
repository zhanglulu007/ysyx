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

  // ===== 性能计数器观测端口 (仅仿真用, ENABLE_PERF 实例化的 PerfCounter 使用) =====
  output icache_access,      // IC_LOOKUP: 一次取指访问判定
  output icache_hit,         // 命中
  output icache_miss,        // 缺失 (可缓存但未命中)
  output icache_uncache,     // 不可缓存访问
  output icache_refill_req,  // 向总线发起一次读请求 (每 beat 一次)
  output icache_wait_ar,     // 等待总线 AR 握手
  output icache_wait_r       // 等待总线 R  握手
);

  // ===================================================================
  // 可配置参数 (B4.md 813-814: 支持更大的块大小, 参数可配置)
  //
  //   BLOCK_SIZE = BUS_WIDTH * 4 = 16B (总线数据位宽的 4 倍)
  //   采用独立总线传输事务方式: BEATS 次独立 AXI 读事务
  //   每次事务 arlen=0, 单 beat, 地址递增 BUS_WIDTH
  // ===================================================================
  localparam ADDR_WIDTH   = 32;
  localparam BUS_WIDTH    = 4;           // AXI 数据位宽 (字节)
  localparam BLOCK_SIZE   = 16;          // 块大小 (字节) = BUS_WIDTH * 4
  localparam OFFSET_BITS  = 4;           // log2(BLOCK_SIZE)
  localparam NR_CACHE_BLK = 16;          // cache 块总数 (2^INDEX_BITS)
  localparam INDEX_BITS   = 4;           // log2(NR_CACHE_BLK)
  localparam TAG_BITS     = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS;  // = 24
  localparam BEATS        = BLOCK_SIZE / BUS_WIDTH;  // = 4
  localparam BEAT_BITS    = 2;           // $clog2(BEATS), 用于 beat 计数器

  // ===================================================================
  // 状态机 (与原 ICache 一致)
  //   IC_IDLE:      等待 IFU 取指请求 (AR 阶段)
  //   IC_LOOKUP:    查命中/缺失, 决定应答方式
  //   IC_REFILL_AR: 缺失/不可缓存 -> 向总线发 AR (独立事务, 每次 arlen=0)
  //   IC_REFILL_R:  等总线 R 握手; 缺失则逐 beat 回填, 最后一 beat 应答 IFU
  // ===================================================================
  localparam IC_IDLE      = 2'b00;
  localparam IC_LOOKUP    = 2'b01;
  localparam IC_REFILL_AR = 2'b10;
  localparam IC_REFILL_R  = 2'b11;

  reg [1:0] state;

  // ===================================================================
  // 存储阵列 (触发器实现, 复位全部无效)
  //
  //   块大小 16B 时, 每 cache 块含 BEATS=4 个 32-bit 字.
  //   采用扁平数组: cache block i 占据 word index [i*BEATS .. i*BEATS+BEATS-1].
  //   tag/valid 按 block 粒度维护 (每 index 一组).
  // ===================================================================
  localparam TOTAL_WORDS = NR_CACHE_BLK * BEATS;  // = 64
  reg [31:0]         cache_data  [0:TOTAL_WORDS-1];
  reg [TAG_BITS-1:0] cache_tag   [0:NR_CACHE_BLK-1];
  reg                cache_valid [0:NR_CACHE_BLK-1];

  integer i;
  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < NR_CACHE_BLK; i = i + 1) begin
        cache_valid[i] <= 1'b0;
      end
    end
  end

  // ===================================================================
  // 请求信息锁存 (IC_IDLE AR 握手时捕获)
  // ===================================================================
  reg [31:0] req_addr;
  reg [ 3:0] req_arid;

  // 地址拆解 (基于锁存的 req_addr)
  //   31       m+n   m+n-1     m   m-1       0
  //  +----------+--------+--------+----------+
  //  |   tag    |  index |  word  |  byte    |
  //  +----------+--------+--------+----------+
  //   tag=24b    index=4b  word=2b  byte=2b  (BLOCK_SIZE=16 时)
  wire [OFFSET_BITS-1:0] req_offset = req_addr[OFFSET_BITS-1:0];
  wire [INDEX_BITS-1:0]  req_index  = req_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  wire [TAG_BITS-1:0]    req_tag    = req_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];
  wire [BEAT_BITS-1:0]   req_word   = req_offset[OFFSET_BITS-1:2];  // 块内第几个字

  // 块对齐基地址 (低 OFFSET_BITS 位清零)
  wire [31:0] block_base = {req_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};

  // 可缓存地址判定: Flash(0x3...), PSRAM(0x8...), SDRAM(0xa...) (B4.md 436 行)
  wire req_cacheable = (req_addr[31:28] == 4'h3) ||
                       (req_addr[31:28] == 4'h8) ||
                       (req_addr[31:28] == 4'ha);

  // 命中判定 (IC_LOOKUP 阶段对锁存地址计算)
  //   tag 按 block 粒度比较, index 选择 cache block
  wire hit = cache_valid[req_index] && (cache_tag[req_index] == req_tag);

  // ===================================================================
  // 独立总线传输事务 — Beat 计数器
  //
  //   每次缺失/不可缓存从 bus 读数据时:
  //   - 可缓存缺失: 需要 BEATS 次独立 AXI 读事务, beat_cnt 从 0 递增
  //   - 不可缓存:   只需 1 次, beat_cnt 恒为 0
  //   每完成一次 R 握手 beat_cnt+1; 回到 IC_IDLE 时清零.
  // ===================================================================
  reg [BEAT_BITS-1:0] beat_cnt;

  always @(posedge clk) begin
    if (rst) begin
      beat_cnt <= 0;
    end else if (state == IC_IDLE) begin
      beat_cnt <= 0;
    end else if (state == IC_REFILL_R && bus_rvalid && bus_rready) begin
      beat_cnt <= beat_cnt + 1'b1;
    end
  end

  // ===================================================================
  // 总线侧 AR 通道 (独立传输事务: 每次 arlen=0, 单 beat)
  //
  //   可缓存缺失: 发送 BEATS 次独立 AR, 地址为 block_base + beat_cnt*BUS_WIDTH
  //   不可缓存:   发送 1 次 AR, 地址为原始 req_addr
  // ===================================================================
  wire [31:0] beat_addr = block_base + (beat_cnt << 2);  // + beat_cnt * 4

  assign bus_arvalid = (state == IC_REFILL_AR) ? 1'b1 : 1'b0;
  assign bus_araddr  = req_cacheable ? beat_addr : req_addr;
  assign bus_arid    = req_arid;
  assign bus_arlen   = 8'b0;        // 独立事务: 每事务单 beat
  assign bus_arsize  = 3'b010;      // 4 字节
  assign bus_arburst = 2'b01;       // INCR

  // ===================================================================
  // 总线侧 R 通道 (逐 beat 接收, 回填 cache 或直通给 IFU)
  // ===================================================================
  assign bus_rready = (state == IC_REFILL_R);

  wire refill_beat_done = (state == IC_REFILL_R) && bus_rvalid && bus_rready;
  wire is_last_beat     = (beat_cnt == BEATS-1);  // 对不可缓存 beat_cnt=0==3? No, 0!=3

  // 回填: 仅在可缓存 + 无总线错误时, 将 bus_rdata 写入对应 word slot
  wire do_refill = refill_beat_done && req_cacheable && !bus_rresp[1];

  // word 索引: {index, beat_cnt} — 第 index 个 cache block 的第 beat_cnt 个字
  wire [INDEX_BITS+BEAT_BITS-1:0] refill_idx = {req_index, beat_cnt};

  always @(posedge clk) begin
    if (do_refill) begin
      cache_data[refill_idx] <= bus_rdata;
    end
  end

  // 最后一个 beat 回填完成时: 写入 tag 并置 valid
  wire do_finalize = refill_beat_done && req_cacheable && is_last_beat && !bus_rresp[1];

  always @(posedge clk) begin
    if (do_finalize) begin
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
  //
  //   命中:              IC_LOOKUP 当拍返回 block 中 req_word 对应字
  //   可缓存缺失(末beat): 返回 req_word 对应字 (存于 cache_data 或当前 bus_rdata)
  //   不可缓存(单beat):   直通 bus_rdata
  // ===================================================================
  wire lookup_hit   = (state == IC_LOOKUP)   && req_cacheable &&  hit;
  wire refill_done  = refill_beat_done       && req_cacheable &&  is_last_beat;
  wire uncache_done = refill_beat_done       && !req_cacheable;

  // 命中: 读 cache_data[{req_index, req_word}]
  wire [INDEX_BITS+BEAT_BITS-1:0] hit_idx = {req_index, req_word};

  assign cpu_rvalid = lookup_hit || refill_done || uncache_done;

  // refill_done 时若请求字恰为当前 beat, 直接取 bus_rdata (组合逻辑路径);
  // 否则取已写入 cache_data 的值 (来自先前 beat)
  assign cpu_rdata  = lookup_hit  ? cache_data[hit_idx] :
                      refill_done ? ((req_word == beat_cnt) ? bus_rdata : cache_data[{req_index, req_word}]) :
                      uncache_done? bus_rdata :
                      32'b0;

  assign cpu_rresp  = (refill_done || uncache_done) ? bus_rresp : 2'b00;
  assign cpu_rlast  = 1'b1;  // 向 IFU 总是单 beat 应答
  assign cpu_rid    = req_arid;

  // ===================================================================
  // 状态机
  //
  //   可缓存缺失时 IC_REFILL_AR <-> IC_REFILL_R 循环 BEATS 次:
  //     IC_REFILL_AR (发送第 beat_cnt 次 AR) -> IC_REFILL_R (收 R)
  //     -> 若 beat_cnt < BEATS-1: 回到 IC_REFILL_AR 发下一 AR
  //     -> 若 beat_cnt = BEATS-1: 末 beat, 回填 tag/valid, 应答 IFU, 回 IC_IDLE
  //
  //   不可缓存: IC_REFILL_AR -> IC_REFILL_R (单 beat) -> 直通应答 -> IC_IDLE
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
            // 命中: 本拍组合应答 IFU, 次拍回 IDLE
            state <= IC_IDLE;
          end else begin
            // 缺失或不可缓存: 通过独立总线事务读取
            state <= IC_REFILL_AR;
          end
        end

        IC_REFILL_AR: begin
          // 等待总线侧 AR 握手
          if (bus_arready) state <= IC_REFILL_R;
        end

        IC_REFILL_R: begin
          if (bus_rvalid && bus_rready) begin
            if (!req_cacheable) begin
              // 不可缓存: 单 beat 直通, 应答后回 IDLE
              state <= IC_IDLE;
            end else if (beat_cnt == BEATS-1) begin
              // 可缓存缺失, 最后一个 beat: tag/valid 本拍已更新, 应答 IFU, 回 IDLE
              state <= IC_IDLE;
            end else begin
              // 可缓存缺失, 非末 beat: 继续发下一个独立 AR
              state <= IC_REFILL_AR;
            end
          end
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