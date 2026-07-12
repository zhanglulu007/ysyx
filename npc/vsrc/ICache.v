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
  // 流水化 icache 状态机
  //   IC_IDLE:      S1 流水段 - 接收 IFU 的 AR 请求 (锁存到 s1_req)
  //   IC_LOOKUP:    S2 流水段 - 命中/缺失判定; 命中时本拍应答, 同时可接收下个 AR
  //   IC_REFILL_AR: 缺失/不可缓存 - 向 Arbiter 发 AR, 等握手
  //   IC_REFILL_R:  等 Arbiter R 握手; 逐 word 回填
  //
  // 流水化关键点:
  //   1. IC_LOOKUP 命中应答的同一拍, IC_IDLE 仍可接收下个 AR 请求,
  //      实现 S1(AR接收) / S2(LOOKUP+RESP) 两级流水, 命中吞吐 ≈ 1 条/周期
  //   2. IFU 侧 R 通道 rready 由 PipelineCore 提供, 仅在它能消化该指令时才置 1,
  //      故 IC_LOOKUP 命中后若 IFU不 rready, 需保持 resp 直到 R 握手完成
  //   3. 缺失时阻塞 S1 (cpu_arready=0), 直到 refill 完成
  // ===================================================================
  localparam IC_IDLE      = 2'b00;
  localparam IC_LOOKUP    = 2'b01;
  localparam IC_REFILL_AR = 2'b10;
  localparam IC_REFILL_R  = 2'b11;

  reg [1:0] state;
  reg [1:0] prev_state;

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
  // S1 流水段寄存器: 锁存 IFU 的 AR 请求 (在 IC_IDLE 握手时捕获)
  // ===================================================================
  reg [31:0] req_addr;
  reg [ 3:0] req_arid;

  // 地址拆解 (基于锁存的 req_addr)
  wire [OFFSET_BITS-1:0]    req_offset    = req_addr[OFFSET_BITS-1:0];
  wire [INDEX_BITS-1:0]     req_index     = req_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  wire [TAG_BITS-1:0]       req_tag       = req_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];

  // 块内 word 索引
  wire [WORD_IDX_BITS-1:0]  req_word_idx;
  generate
    if (OFFSET_BITS > 2) begin : gen_word_idx
      assign req_word_idx = req_addr[OFFSET_BITS-1:2];
    end else begin : gen_word_idx
      assign req_word_idx = {WORD_IDX_BITS{1'b0}};
    end
  endgenerate

  // 可缓存地址判定 (高 4 位): Flash=0x3, PSRAM=0x8, SDRAM=0xa
  wire req_flash  = (req_addr[31:28] == 4'h3);
  wire req_psram  = (req_addr[31:28] == 4'h8);
  wire req_sdram  = (req_addr[31:28] == 4'ha);
  wire req_cacheable = req_flash || req_psram || req_sdram;

  // 命中判定 (IC_LOOKUP 阶段对锁存地址计算)
  wire hit = cache_valid[req_index] && (cache_tag[req_index] == req_tag);

  // ===================================================================
  // Burst 传输判定: 仅 SDRAM 支持 AXI Burst
  // ===================================================================
  wire is_burst = req_cacheable && req_sdram && (NR_WORDS > 1);

  // ===================================================================
  // 块对齐地址 (将地址低 OFFSET_BITS 位清零)
  // ===================================================================
  wire [31:0] block_aligned_addr;
  assign block_aligned_addr = {req_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};

  // ===================================================================
  // Refill word 计数器
  // ===================================================================
  reg [REFILL_CNT_BITS-1:0] refill_word;

  // ===================================================================
  // 总线侧 AR 通道
  // ===================================================================
  wire [31:0] refill_word_addr;
  assign refill_word_addr = {{REFILL_ADDR_PAD{1'b0}}, refill_word, 2'b0};
  wire [31:0] refill_araddr;
  assign refill_araddr = req_cacheable ?
    (is_burst ? block_aligned_addr : (block_aligned_addr + refill_word_addr)) :
    req_addr;

  assign bus_arvalid = (state == IC_REFILL_AR) ? 1'b1 : 1'b0;
  assign bus_araddr  = refill_araddr;
  assign bus_arid    = req_arid;
  assign bus_arlen   = is_burst ? (BURST_LEN) : 8'b0;
  assign bus_arsize  = 3'b010;       // 4 字节/beat
  assign bus_arburst = 2'b01;        // INCR

  // ===================================================================
  // 总线侧 R 通道 (接收 Arbiter 返回数据)
  // ===================================================================
  assign bus_rready = (state == IC_REFILL_R);

  // 逐 word 写入数据
  wire do_store_beat = (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                       req_cacheable && !bus_rresp[1];

  always @(posedge clk) begin
    if (do_store_beat) begin
      cache_data[req_index][(refill_word * 32) +: 32] <= bus_rdata;
    end
  end

  // 当前传输是否为最后一个 word
  wire is_last_word = is_burst ? bus_rlast :
                      req_cacheable ? (refill_word == REFILL_CNT_BITS'(NR_WORDS-1)) : 1'b1;

  // 回填完成: 最后一个 word 的 R 握手时, 写 tag 和 valid
  wire do_refill_done = (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                        req_cacheable && !bus_rresp[1] && is_last_word;

  always @(posedge clk) begin
    if (do_refill_done) begin
      cache_tag  [req_index] <= req_tag;
      cache_valid[req_index] <= 1'b1;
    end
  end

  // ===================================================================
  // CPU 侧 (IFU) AR 通道应答 -- S1 流水段
  //   IC_IDLE:        接收新的 AR (S1)
  //   IC_LOOKUP:      若上一拍命中且本拍能应答(R握手), 则同时接收下个 AR (流水化关键)
  //   IC_REFILL_*:    缺失/不可缓存期间, 阻塞接收新 AR
  // ===================================================================
  wire lookup_hit_can_resp = (state == IC_LOOKUP) && req_cacheable && hit;
  wire lookup_hit_resp_hs  = lookup_hit_can_resp && cpu_rready;

  // 流水化: IC_LOOKUP 命中且 R 握手完成时, 同拍接收下一 AR
  wire s1_take_next_ar = (state == IC_IDLE) ||
                         (lookup_hit_resp_hs && cpu_arvalid);

  assign cpu_arready = s1_take_next_ar && !rst;

  // ===================================================================
  // CPU 侧 (IFU) R 通道应答 -- S2 流水段
  //   命中:
  //     - IC_LOOKUP 当拍直出 cache 数据
  //     - 若 IFU rready=0, 保持 lookup_hit 状态直到 R 握手 (停顿 S2)
  //     - 若 IFU rready=1, 同拍可接收下个 AR (流水化)
  //   缺失: IC_REFILL_R 最后一个 word 的 R 握手当拍应答
  // ===================================================================
  wire refill_done = (state == IC_REFILL_R) && bus_rvalid && bus_rready && is_last_word;

  // 命中时从 cache_data 中选取对应 word
  wire [31:0] hit_word;
  assign hit_word = cache_data[req_index][(req_word_idx * 32) +: 32];

  // refill_done 时, 最后一个 word 可能不是 CPU 请求的 word (当 BLOCK_SIZE>4).
  wire [31:0] refill_word_data;
  assign refill_word_data = req_cacheable ?
      ((refill_word == req_word_idx) ? bus_rdata
                                     : cache_data[req_index][(req_word_idx * 32) +: 32]) :
      bus_rdata;

  assign cpu_rvalid = lookup_hit_can_resp || refill_done;
  assign cpu_rdata  = lookup_hit_can_resp ? hit_word : refill_word_data;
  assign cpu_rresp  = refill_done ? bus_rresp : 2'b00;
  assign cpu_rlast  = 1'b1;    // CPU 侧始终单 beat 应答
  assign cpu_rid    = req_arid;

  // ===================================================================
  // 状态机
  // ===================================================================
  always @(posedge clk) begin
    if (rst || flush) begin
      state       <= IC_IDLE;
      prev_state  <= IC_IDLE;
      req_addr    <= 32'b0;
      req_arid    <= 4'b0;
      refill_word <= {REFILL_CNT_BITS{1'b0}};
    end else begin
      prev_state <= state;
      case (state)
        IC_IDLE: begin
          // S1: 接收 IFU 的 AR 请求
          if (cpu_arvalid && cpu_arready) begin
            req_addr <= cpu_araddr;
            req_arid <= cpu_arid;
            state    <= IC_LOOKUP;
          end
        end

        IC_LOOKUP: begin
          // S2: 命中/缺失判定
          if (req_cacheable && hit) begin
            // 命中: 若 IFU rready=1, 当拍应答并完成 R 握手
            // 流水化关键: 若同拍 IFU 又送来新 AR, 直接接收并保持 IC_LOOKUP
            // - 这样下一周期 S2 仍对新 req_addr 做 lookup, 形成 1拍/指令的命中流
            // - 若 rready=0: 暂停 S2 (保持 IC_LOOKUP, 不动 state), 等到 rready=1
            if (cpu_rready) begin
              if (cpu_arvalid) begin
                // 同拍接收新 AR: 流水段 S1 与 S2 重叠在 IC_LOOKUP 中
                req_addr <= cpu_araddr;
                req_arid <= cpu_arid;
                state    <= IC_LOOKUP;  // 保持 S2 (下周期对新地址做 lookup)
              end else begin
                // 无新 AR: 回 S1 等待
                state <= IC_IDLE;
              end
            end
            // else: 等 cpu_rready, 保持 IC_LOOKUP 不动
          end else begin
            // 缺失或不可缓存: 进入 refill 流程, 复位 word 计数器
            refill_word <= {REFILL_CNT_BITS{1'b0}};
            state       <= IC_REFILL_AR;
          end
        end

        IC_REFILL_AR: begin
          // 等待总线侧 AR 握手
          if (bus_arready) state <= IC_REFILL_R;
        end

        IC_REFILL_R: begin
          if (bus_rvalid && bus_rready) begin
            if (is_burst) begin
              // Burst 模式
              if (bus_rlast) begin
                state <= IC_IDLE;
              end else begin
                refill_word <= refill_word + 1'b1;
              end
            end else begin
              // 非 Burst 模式 (单 beat)
              if (!req_cacheable || refill_word == REFILL_CNT_BITS'(NR_WORDS-1)) begin
                state <= IC_IDLE;
              end else begin
                refill_word <= refill_word + 1'b1;
                state       <= IC_REFILL_AR;
              end
            end
          end
        end

        default: state <= IC_IDLE;
      endcase
    end
  end

  // ===================================================================
  // 性能计数器观测信号
  //   - icache_access: 在 IC_LOOKUP 完成判定时计 (命中+缺失+uncache)
  //   - icache_hit:    IC_LOOKUP 拍且命中
  //   - icache_miss:   IC_LOOKUP 拍且可缓存但缺失
  //   - icache_uncache:IC_LOOKUP 拍且不可缓存
  //   - 流水化后: 同一拍 IC_LOOKUP 命中应答 + 接收下个 AR, 仍只算 1 次访问
  // ===================================================================
  assign icache_access     = (state == IC_LOOKUP) && !rst;
  assign icache_hit        = (state == IC_LOOKUP) && req_cacheable &&  hit && !rst;
  assign icache_miss       = (state == IC_LOOKUP) && req_cacheable && !hit && !rst;
  assign icache_uncache    = (state == IC_LOOKUP) && !req_cacheable    && !rst;
  assign icache_refill_req       = (state == IC_REFILL_AR)                   && !rst;
  assign icache_refill_req_pulse = (state == IC_REFILL_AR) && (prev_state != IC_REFILL_AR) && !rst;
  assign icache_wait_ar          = (state == IC_REFILL_AR)                   && !rst;
  assign icache_wait_r           = (state == IC_REFILL_R)                    && !rst;

endmodule
