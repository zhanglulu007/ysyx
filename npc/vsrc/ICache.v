module ICache #(
  parameter BLOCK_SIZE   = 16,   // 块大小 (字节), 默认 16B (= 4×总线位宽)
  parameter NR_CACHE_BLK = 4     // 缓存块数, 默认 4
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
  output icache_refill_req,        // 电平信号: IC_REFILL_AR 状态 (周期计数)
  output icache_refill_req_pulse,  // 脉冲信号: 进入 IC_REFILL_AR 的当拍 (事件计数)
  output icache_wait_ar,
  output icache_wait_r,

  // ===== fence.i 控制 =====
  input flush                      // 冲刷整个 ICache (所有 valid 位清零)
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
  localparam REFILL_CNT_BITS = (NR_WORDS > 1) ? $clog2(NR_WORDS) : 1;  // refill word 计数器位宽
  localparam REFILL_ADDR_PAD = 32 - REFILL_CNT_BITS - 2;  // refill_word 扩展至 32-bit 地址的零填充位数
  localparam BURST_LEN       = NR_WORDS - 1;  // AXI arlen = 节拍数 - 1

  // ===================================================================
  // 流水化 icache 设计:
  //   将命中路径划分为 3 个流水段, 在命中时每周期可接受一条新请求
  //     S1 (AR_RECV):  接收 IFU AR 请求, 锁存地址/ID
  //     S2 (LOOKUP):   用锁存地址读 cache 阵列, 判定命中/缺失/uncache
  //     S3 (HIT_RESP): 命中时输出对应 word; 缺失时进入 refill, 完成后
  //                    在本段输出对应 word
  //   缺失会阻塞 S2/S3, 此时 S1 也不能再接收新请求 (因 S2 不能流动).
  //   flush 时清空所有 valid 位和流水段 valid.
  // ===================================================================

  // 流水段 valid
  reg s1_valid, s2_valid, s3_valid;

  // 流水段寄存器 (S1 -> S2 -> S3)
  reg [31:0] s1_addr;
  reg [ 3:0] s1_arid;
  reg [31:0] s2_addr;
  reg [ 3:0] s2_arid;
  reg [31:0] s3_addr;
  reg [ 3:0] s3_arid;
  reg        s3_hit_resp;       // 1 = 命中直出, 0 = refill 完成
  reg [31:0] s3_resp_data;      // S3 阶段输出的最终数据
  reg [ 1:0] s3_resp_status;     // 0 = OKAY, 否则 = bus_rresp
  reg        s3_cacheable;       // S3 处理的是不是可缓存请求

  // ===================================================================
  // 存储阵列 (触发器实现, 复位全部无效)
  // ===================================================================
  reg [(BLOCK_SIZE*8)-1:0] cache_data [0:NR_CACHE_BLK-1];
  reg [TAG_BITS-1:0]       cache_tag  [0:NR_CACHE_BLK-1];
  reg                      cache_valid[0:NR_CACHE_BLK-1];

  integer i;
  always @(posedge clk) begin
    if (rst || flush) begin
      for (i = 0; i < NR_CACHE_BLK; i = i + 1) begin
        cache_valid[i] <= 1'b0;
      end
    end
  end

  // ===================================================================
  // 地址拆解工具函数 (输入地址 -> tag/index/word_idx/offset)
  // ===================================================================
  function [TAG_BITS-1:0]      addr_tag   (input [31:0] a);
    addr_tag = a[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];
  endfunction
  function [INDEX_BITS-1:0]    addr_index (input [31:0] a);
    addr_index = a[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  endfunction
  function [WORD_IDX_BITS-1:0] addr_widx  (input [31:0] a);
    if (OFFSET_BITS > 2) addr_widx = a[OFFSET_BITS-1:2];
    else                 addr_widx = {WORD_IDX_BITS{1'b0}};
  endfunction
  function [OFFSET_BITS-1:0]   addr_offset(input [31:0] a);
    addr_offset = a[OFFSET_BITS-1:0];
  endfunction

  // S1 地址拆解 (用于 S2 查命中)
  wire [TAG_BITS-1:0]       s1_tag    = addr_tag(s1_addr);
  wire [INDEX_BITS-1:0]     s1_index  = addr_index(s1_addr);
  wire [WORD_IDX_BITS-1:0]  s1_widx   = addr_widx(s1_addr);
  wire [OFFSET_BITS-1:0]     s1_offset = addr_offset(s1_addr);

  // 可缓存地址判定 (高 4 位): Flash=0x3, PSRAM=0x8, SDRAM=0xa
  function cacheable_addr (input [31:0] a);
    cacheable_addr = (a[31:28] == 4'h3) || (a[31:28] == 4'h8) || (a[31:28] == 4'ha);
  endfunction

  wire s1_cacheable = cacheable_addr(s1_addr);

  // ===================================================================
  // Burst 传输判定: 仅 SDRAM 支持 AXI Burst
  // ===================================================================
  function is_burst_addr (input [31:0] a);
    is_burst_addr = cacheable_addr(a) && (a[31:28] == 4'ha) && (NR_WORDS > 1);
  endfunction

  // ===================================================================
  // Refill word 计数器
  // ===================================================================
  reg [REFILL_CNT_BITS-1:0] refill_word;

  // 块对齐地址 (将地址低 OFFSET_BITS 位清零)
  function [31:0] block_aligned (input [31:0] a);
    block_aligned = {a[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
  endfunction

  // refill_word * 4, 扩展至 32 位
  wire [31:0] refill_word_addr = {{REFILL_ADDR_PAD{1'b0}}, refill_word, 2'b0};

  // 总线侧 refill AR 地址
  wire [31:0] refill_araddr = s3_cacheable ?
    (is_burst_addr(s3_addr) ? block_aligned(s3_addr) :
                              (block_aligned(s3_addr) + refill_word_addr)) :
    s3_addr;

  // ===================================================================
  // S1 -> S2 流控:
  //   S1 可以推进的条件 = S2 空闲 或 S2 上次已推进 (即 S2 当前拍不再持有数据)
  //   缺失处理在 S3, 但 S2 一旦命中并推进后, 即可接收 S1 的下一条
  //   若 S3 处于 refill 等待状态, 则 S2/S1 都要阻塞
  // ===================================================================
  // S3 是否正在忙于 refill (不需要响应输出时也 Busy)
  reg [1:0] refill_state;
  localparam RF_IDLE     = 2'b00;
  localparam RF_AR       = 2'b01;
  localparam RF_R        = 2'b10;
  localparam RF_DONE     = 2'b11;   // refill 完成, 待输出响应
  wire s3_refilling = (refill_state != RF_IDLE);

  // S2 是否能接受 S1 的数据 (S2 推进到 S3)
  // 只要 S3 不在 refill 中, S2 就可以推进 (即使是命中响应输出也只占 1 拍)
  wire s2_can_advance = s2_valid && !s3_refilling;
  wire s1_can_advance = s1_valid && (!s2_valid || s2_can_advance);

  // S2 推进时: 将 s2 数据传到 s3, 并根据命中/缺失决定 s3 行为
  wire s2_hit     = s2_valid && cacheable_addr(s2_addr) &&
                    cache_valid[addr_index(s2_addr)] &&
                    (cache_tag[addr_index(s2_addr)] == addr_tag(s2_addr));
  wire s2_uncache = s2_valid && !cacheable_addr(s2_addr);
  wire s2_miss    = s2_valid && cacheable_addr(s2_addr) && !s2_hit;

  // S2 命中时的输出数据 (从 cache_data 取对应 word)
  wire [31:0] s2_hit_word = cache_data[addr_index(s2_addr)][(addr_widx(s2_addr) * 32) +: 32];

  // 但需要确保 addr_widx 的位宽与之前一致 (cache_data 是 BLOCK_SIZE*8 位宽)
  // 若 BLOCK_SIZE < 4, 则该表达式不可用, 此时 NR_CACHE_BLK 仍为 1, 不会用到

  // ===================================================================
  // Refill 路径: 进入条件 = S2 推进 且 (s2_miss || s2_uncache)
  //   缺失:   完整 refill 一个块
  //   uncache: 仅取一个 word
  // ===================================================================
  wire enter_refill = s2_can_advance && (s2_miss || s2_uncache);

  // refill 是否是 burst 模式 (取决于 s3_addr)
  wire refill_is_burst = is_burst_addr(s3_addr);

  // 当前传输是否为最后一个 word
  wire is_last_word = refill_is_burst ? bus_rlast :
                      s3_cacheable ? (refill_word == REFILL_CNT_BITS'(NR_WORDS-1)) : 1'b1;

  // 回填写: 在 RF_R 每个 R 握手时, 将 bus_rdata 写入对应 word
  wire do_store_beat = (refill_state == RF_R) && bus_rvalid && bus_rready &&
                       s3_cacheable && !bus_rresp[1];

  always @(posedge clk) begin
    if (do_store_beat) begin
      cache_data[addr_index(s3_addr)][(refill_word * 32) +: 32] <= bus_rdata;
    end
  end

  // 回填完成: 最后一个 word 的 R 握手时, 写 tag 和 valid
  wire do_refill_done = (refill_state == RF_R) && bus_rvalid && bus_rready &&
                        s3_cacheable && !bus_rresp[1] && is_last_word;

  always @(posedge clk) begin
    if (do_refill_done) begin
      cache_tag  [addr_index(s3_addr)] <= addr_tag(s3_addr);
      cache_valid[addr_index(s3_addr)] <= 1'b1;
    end
  end

  // ===================================================================
  // 总线侧 AR 通道
  // ===================================================================
  assign bus_arvalid = (refill_state == RF_AR) ? 1'b1 : 1'b0;
  assign bus_araddr  = refill_araddr;
  assign bus_arid    = s3_arid;
  assign bus_arlen   = refill_is_burst ? (BURST_LEN) : 8'b0;
  assign bus_arsize  = 3'b010;       // 4 字节/beat
  assign bus_arburst = 2'b01;        // INCR

  // ===================================================================
  // 总线侧 R 通道
  // ===================================================================
  assign bus_rready = (refill_state == RF_R);

  // ===================================================================
  // CPU 侧 AR 通道: 仅在 S1 接收新请求
  // ===================================================================
  assign cpu_arready = !s1_valid || s1_can_advance;

  // ===================================================================
  // CPU 侧 R 通道
  //   命中或 refill 完成时, 通过 S3 输出一次响应
  // ===================================================================
  // 命中路径: S2 推进到 S3 时, S3 直接输出命中的 word
  // refill 路径: refill 完成时, S3 输出最终数据
  wire [31:0] refill_word_data = s3_cacheable ?
      ((refill_word == addr_widx(s3_addr)) ? bus_rdata :
                                            cache_data[addr_index(s3_addr)][(addr_widx(s3_addr) * 32) +: 32]) :
      bus_rdata;

  // S3 响应有效: S3 中是命中响应 或 refill 完成
  // 两种情形均为单拍输出, 然后清空 s3
  wire s3_hit_valid   = s3_valid &&  s3_hit_resp && !cpu_rready;  // 保持直到握手
  wire s3_resp_active = s3_valid && (s3_hit_resp || refill_state == RF_DONE);

  assign cpu_rvalid = s3_resp_active;
  assign cpu_rdata  = s3_resp_data;
  assign cpu_rresp  = s3_resp_status;
  assign cpu_rlast  = 1'b1;    // CPU 侧始终单 beat 应答
  assign cpu_rid    = s3_arid;

  // ===================================================================
  // 主状态机: 流水段寄存器更新 + refill 状态机
  // ===================================================================
  always @(posedge clk) begin
    if (rst || flush) begin
      s1_valid     <= 1'b0;
      s2_valid     <= 1'b0;
      s3_valid     <= 1'b0;
      s3_hit_resp  <= 1'b0;
      s3_resp_data <= 32'b0;
      s3_resp_status <= 2'b00;
      s3_cacheable <= 1'b0;
      s3_addr      <= 32'b0;
      s3_arid      <= 4'b0;
      refill_word  <= {REFILL_CNT_BITS{1'b0}};
      refill_state <= RF_IDLE;
    end else begin
      // ---- 默认 S3 响应握手后清空 ----
      // S3 响应有效且 IFU 握手成功 -> s3_valid 清零
      // refill 完成时同时清空 refill_state
      if (s3_resp_active && cpu_rready) begin
        s3_valid     <= 1'b0;
        s3_hit_resp  <= 1'b0;
        refill_state <= RF_IDLE;
      end

      // ---- S2 -> S3 推进 ----
      // 若 S2 有效且 S3 不在 refilling 状态 (即 S3 空或可清空), 将 S2 数据送入 S3
      if (s2_can_advance) begin
        if (s2_hit) begin
          // 命中: 直接进入 S3 并输出
          s3_valid     <= 1'b1;
          s3_hit_resp  <= 1'b1;
          s3_addr      <= s2_addr;
          s3_arid      <= s2_arid;
          s3_cacheable <= 1'b1;
          s3_resp_data <= s2_hit_word;
          s3_resp_status <= 2'b00;
          refill_state <= RF_IDLE;
        end else if (s2_miss || s2_uncache) begin
          // 缺失/不可缓存: 进入 refill, S3 占用直到 refill 完成
          s3_valid     <= 1'b1;
          s3_hit_resp  <= 1'b0;
          s3_addr      <= s2_addr;
          s3_arid      <= s2_arid;
          s3_cacheable <= cacheable_addr(s2_addr);
          s3_resp_data <= 32'b0;
          s3_resp_status <= 2'b00;
          refill_word  <= {REFILL_CNT_BITS{1'b0}};
          refill_state <= RF_AR;
        end else begin
          // S2 有效但既不命中也不缺失 (不应该发生, 但保留)
          s3_valid <= 1'b0;
        end
      end else if (s2_valid && !s3_refilling && !s3_resp_active) begin
        // S3 空且不 refilling, 但 S2 没推进 (上面 if 已覆盖)
        s3_valid <= 1'b0;
      end

      // ---- refill 状态机 ----
      if (refill_state == RF_AR) begin
        if (bus_arready) refill_state <= RF_R;
      end else if (refill_state == RF_R) begin
        if (bus_rvalid && bus_rready) begin
          if (refill_is_burst) begin
            if (bus_rlast) begin
              refill_state <= RF_DONE;
            end else begin
              refill_word <= refill_word + 1'b1;
            end
          end else begin
            if (!s3_cacheable || refill_word == REFILL_CNT_BITS'(NR_WORDS-1)) begin
              refill_state <= RF_DONE;
            end else begin
              refill_word  <= refill_word + 1'b1;
              refill_state <= RF_AR;
            end
          end
        end
      end

      // ---- refill 完成 -> 输出对应 word ----
      if (refill_state == RF_DONE && !s3_hit_resp) begin
        s3_resp_data <= refill_word_data;
        s3_resp_status <= bus_rresp;
        s3_hit_resp  <= 1'b1;  // 复用 hit_resp 路径生成单拍输出
      end

      // ---- S1 -> S2 推进 ----
      if (s1_can_advance) begin
        // S1 数据送入 S2
        s2_valid <= 1'b1;
        s2_addr  <= s1_addr;
        s2_arid  <= s1_arid;
      end else if (s2_can_advance || !s2_valid) begin
        // S2 即将被清空或本就无效
        s2_valid <= 1'b0;
      end

      // ---- S1 接收新请求 ----
      if (cpu_arvalid && cpu_arready && !s1_valid) begin
        // S1 空闲: 接收新请求
        s1_valid <= 1'b1;
        s1_addr  <= cpu_araddr;
        s1_arid  <= cpu_arid;
      end else if (s1_can_advance && !(cpu_arvalid && cpu_arready)) begin
        // S1 推进但没有新请求到来
        s1_valid <= 1'b0;
      end else if (s1_can_advance && cpu_arvalid && cpu_arready) begin
        // S1 推进且同时接收新请求 -> 用新数据填充 s1
        s1_addr  <= cpu_araddr;
        s1_arid  <= cpu_arid;
        // s1_valid 保持 1
      end
    end
  end

  // ===================================================================
  // 性能计数器观测信号
  //   icache_access: S2 阶段查命中/缺失的当拍 (一次 access 对应一次 lookup)
  //   icache_hit:    S2 命中
  //   icache_miss:   S2 缺失 (可缓存)
  //   icache_uncache: S2 不可缓存
  //   icache_refill_req: 处于 RF_AR 状态
  //   icache_refill_req_pulse: 进入 RF_AR 的当拍
  //   icache_wait_ar: 处于 RF_AR 状态
  //   icache_wait_r:  处于 RF_R 状态
  // ===================================================================
  assign icache_access     = s2_valid && !rst;
  assign icache_hit        = s2_valid && cacheable_addr(s2_addr) &&  cache_valid[addr_index(s2_addr)] && (cache_tag[addr_index(s2_addr)] == addr_tag(s2_addr)) && !rst;
  assign icache_miss       = s2_valid && cacheable_addr(s2_addr) && (!cache_valid[addr_index(s2_addr)] || (cache_tag[addr_index(s2_addr)] != addr_tag(s2_addr))) && !rst;
  assign icache_uncache    = s2_valid && !cacheable_addr(s2_addr) && !rst;
  assign icache_refill_req       = (refill_state == RF_AR) && !rst;
  assign icache_wait_ar          = (refill_state == RF_AR) && !rst;
  assign icache_wait_r           = (refill_state == RF_R)  && !rst;

  // 仅用于性能计数, 与历史行为保持一致的边沿检测
  reg [1:0] prev_refill_state;
  always @(posedge clk) begin
    if (rst || flush) prev_refill_state <= RF_IDLE;
    else              prev_refill_state <= refill_state;
  end
  assign icache_refill_req_pulse = (refill_state == RF_AR) && (prev_refill_state != RF_AR) && !rst;

endmodule
