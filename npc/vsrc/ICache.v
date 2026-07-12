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
  // 状态机
  //   IC_IDLE:      等待 IFU 取指请求 (AR 阶段), 与 IFU 的 arready 握手
  //   IC_LOOKUP:    查命中/缺失并向 IFU 应答。命中且应答被接收时可同时
  //                 接收下一条请求，令该请求在下一拍进入查找阶段。
  //   IC_REFILL_AR: 向 Arbiter 发 AR, 等握手
  //   IC_REFILL_R:  等 Arbiter R 握手; 逐 word 回填;
  //                 Burst 模式一次读完; 非 Burst 模式循环回 IC_REFILL_AR 取下一个 word
  //   IC_RESP:      保存 refill 的 CPU 响应，等待 IFU 接收
  //   IC_DISCARD_AR: fence.i 后补全一个已被仲裁器授权的 AR 请求
  //   IC_DISCARD_R: fence.i 冲刷已发出的 AXI 读事务时，排空剩余 R beat
  // ===================================================================
  localparam IC_IDLE      = 3'd0;
  localparam IC_LOOKUP    = 3'd1;
  localparam IC_REFILL_AR = 3'd2;
  localparam IC_REFILL_R  = 3'd3;
  localparam IC_RESP      = 3'd4;
  localparam IC_DISCARD_R = 3'd5;
  localparam IC_DISCARD_AR = 3'd6;

  reg [2:0] state;

  // ===================================================================
  // 存储阵列 (触发器实现, 复位全部无效)
  // 每个 cache 块存储 BLOCK_SIZE 字节 (BLOCK_SIZE*8 位宽)
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
  // 请求信息 (锁存 IFU 的请求, 跨阶段稳定使用)
  // ===================================================================
  reg [31:0] req_addr;
  reg [ 3:0] req_arid;

  // 地址拆解 (基于锁存的 req_addr)
  wire [OFFSET_BITS-1:0]    req_offset    = req_addr[OFFSET_BITS-1:0];
  wire [INDEX_BITS-1:0]     req_index     = req_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  wire [TAG_BITS-1:0]       req_tag       = req_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];

  // 块内 word 索引 (通过 generate 避免 OFFSET_BITS≤2 时产生非法降序切片)
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
  // Burst 传输判定: 仅 SDRAM 支持 AXI Burst (讲义 B4.md 839行:
  //   "使icache支持突发传输...访问SDRAM中的数据块")
  // Flash/PSRAM 不支持 Burst, 需多次单 beat AR 逐 word 填充
  // ===================================================================
  wire is_burst = req_cacheable && req_sdram && (NR_WORDS > 1);

  // ===================================================================
  // 块对齐地址 (将地址低 OFFSET_BITS 位清零)
  // ===================================================================
  wire [31:0] block_aligned_addr;
  assign block_aligned_addr = {req_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};

  // ===================================================================
  // Refill word 计数器
  //   Burst 模式: 每次 R 握手递增, 用于确定写入位置
  //   非 Burst 模式: 每次完成一个 word 后在状态机中递增, 用于计算下个 AR 地址
  // ===================================================================
  reg [REFILL_CNT_BITS-1:0] refill_word;

  // ===================================================================
  // 总线侧 AR 通道
  //   Burst:   arlen = BURST_LEN,  addr = block_aligned_addr (所有 word 一次返回)
  //   非Burst: arlen = 0,          addr = block_aligned_addr + refill_word*4
  //   不可缓存: arlen = 0,          addr = req_addr
  // ===================================================================
  wire [31:0] refill_word_addr;
  assign refill_word_addr = {{REFILL_ADDR_PAD{1'b0}}, refill_word, 2'b0};  // refill_word * 4, 扩展至 32 位
  wire [31:0] refill_araddr;
  assign refill_araddr = req_cacheable ?
    (is_burst ? block_aligned_addr : (block_aligned_addr + refill_word_addr)) :
    req_addr;

  assign bus_arvalid = (state == IC_REFILL_AR) || (state == IC_DISCARD_AR);
  assign bus_araddr  = refill_araddr;
  assign bus_arid    = req_arid;
  assign bus_arlen   = is_burst ? (BURST_LEN) : 8'b0;
  assign bus_arsize  = 3'b010;       // 4 字节/beat
  assign bus_arburst = 2'b01;        // INCR

  // ===================================================================
  // 总线侧 R 通道 (接收 Arbiter 返回数据)
  // ===================================================================
  assign bus_rready = (state == IC_REFILL_R) || (state == IC_DISCARD_R);

  // 逐 word 写入数据: 在 IC_REFILL_R 每个 R 握手时, 将 bus_rdata 写入对应 word 位置
  // (Burst 模式: refill_word 由本块递增; 非 Burst 模式: refill_word 由状态机控制)
  wire do_store_beat = !flush && (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                       req_cacheable && !bus_rresp[1];

  always @(posedge clk) begin
    if (do_store_beat) begin
      cache_data[req_index][(refill_word * 32) +: 32] <= bus_rdata;
    end
  end

  // 当前传输是否为最后一个 word:
  //   Burst 模式: bus_rlast 指示
  //   非 Burst 可缓存: refill_word == NR_WORDS-1 时即为最后一个 word
  //   不可缓存: 单拍即最后一拍
  wire is_last_word = is_burst ? bus_rlast :
                      req_cacheable ? (refill_word == REFILL_CNT_BITS'(NR_WORDS-1)) : 1'b1;

  // 回填完成: 最后一个 word 的 R 握手时, 写 tag 和 valid
  wire do_refill_done = !flush && (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                        req_cacheable && !bus_rresp[1] && is_last_word;

  always @(posedge clk) begin
    if (do_refill_done) begin
      cache_tag  [req_index] <= req_tag;
      cache_valid[req_index] <= 1'b1;
    end
  end

  // ===================================================================
  // CPU 侧 (IFU) AR 通道应答
  // ===================================================================
  // A hit response consumes the lookup slot.  Allow the following request to
  // replace it in that same cycle, which is the ICache's hit-path pipeline.
  assign cpu_arready = !flush && ((state == IC_IDLE) ||
                                  ((state == IC_LOOKUP) && req_cacheable && hit && cpu_rready));

  // ===================================================================
  // CPU 侧 (IFU) R 通道应答
  //   命中:  IC_LOOKUP 当拍直出 cache 数据 + OK resp + last
  //   缺失:  IFU 就绪时由最后一个回填 beat 直通；否则保存至 IC_RESP
  // ===================================================================
  wire lookup_hit  = (state == IC_LOOKUP)   && req_cacheable &&  hit;
  wire refill_done = (state == IC_REFILL_R) && bus_rvalid && bus_rready && is_last_word;

  // 命中时从 cache_data 中选取对应 word
  wire [31:0] hit_word;
  assign hit_word = cache_data[req_index][(req_word_idx * 32) +: 32];

  // refill_done 时, 最后一个 word 可能不是 CPU 请求的 word (当 BLOCK_SIZE>4).
  // 若最后一个 word 恰好是请求 word, 直接用 bus_rdata; 否则从已写入的 cache 中读取.
  // 不可缓存 (req_cacheable=0) 时 refill 仅取一个 word, 直通 bus_rdata.
  wire [31:0] refill_word_data;
  assign refill_word_data = req_cacheable ?
      ((refill_word == req_word_idx) ? bus_rdata
                                     : cache_data[req_index][(req_word_idx * 32) +: 32]) :
      bus_rdata;

  reg [31:0] resp_data;
  reg [ 1:0] resp_resp;
  reg [ 3:0] resp_id;

  assign cpu_rvalid = !flush && (lookup_hit || refill_done || (state == IC_RESP));
  assign cpu_rdata  = lookup_hit ? hit_word :
                      refill_done ? refill_word_data : resp_data;
  assign cpu_rresp  = lookup_hit ? 2'b00 :
                      refill_done ? bus_rresp : resp_resp;
  assign cpu_rlast  = 1'b1;    // CPU 侧始终单 beat 应答
  assign cpu_rid    = (lookup_hit || refill_done) ? req_arid : resp_id;

  // ===================================================================
  // 状态机
  // ===================================================================
  reg [2:0] prev_state;
  always @(posedge clk) begin
    if (rst) begin
      state       <= IC_IDLE;
      prev_state  <= IC_IDLE;
      req_addr    <= 32'b0;
      req_arid    <= 4'b0;
      refill_word <= {REFILL_CNT_BITS{1'b0}};
      resp_data   <= 32'b0;
      resp_resp   <= 2'b0;
      resp_id     <= 4'b0;
    end else if (flush) begin
      // An already accepted AR must still be drained, otherwise AXIArbiter
      // remains busy and the first post-fence.i request can deadlock.
      if ((state == IC_REFILL_AR || state == IC_DISCARD_AR) && !bus_arready) begin
        // AXIArbiter may have granted this request before its slave raises
        // ARREADY. Keep ARVALID asserted so that granted transaction can
        // complete, then discard its response below.
        state <= IC_DISCARD_AR;
      end else if (((state == IC_REFILL_AR || state == IC_DISCARD_AR) && bus_arready) ||
                   ((state == IC_REFILL_R || state == IC_DISCARD_R) &&
                    !(bus_rvalid && bus_rready && bus_rlast))) begin
        state <= IC_DISCARD_R;
      end else begin
        state <= IC_IDLE;
      end
      prev_state  <= state;
      if (!((state == IC_REFILL_AR || state == IC_DISCARD_AR) && !bus_arready)) begin
        // Keep the address and ID stable while completing a discarded AR.
        req_addr    <= 32'b0;
        req_arid    <= 4'b0;
        refill_word <= {REFILL_CNT_BITS{1'b0}};
      end
    end else begin
      prev_state <= state;
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
            // 命中响应和下一条 AR 可在同一拍握手，查找槽直接换入新请求。
            if (cpu_rready) begin
              if (cpu_arvalid && cpu_arready) begin
                req_addr <= cpu_araddr;
                req_arid <= cpu_arid;
                state    <= IC_LOOKUP;
              end else begin
                state <= IC_IDLE;
              end
            end
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

        IC_DISCARD_AR: begin
          if (bus_arready) state <= IC_DISCARD_R;
        end

        IC_REFILL_R: begin
          if (bus_rvalid && bus_rready) begin
            if (is_burst) begin
              // Burst 模式: 每个 R beat 递增 refill_word, rlast 时完成
              if (bus_rlast) begin
                if (cpu_rready) begin
                  state <= IC_IDLE;
                end else begin
                  resp_data <= refill_word_data;
                  resp_resp <= bus_rresp;
                  resp_id   <= req_arid;
                  state     <= IC_RESP;
                end
              end else begin
                refill_word <= refill_word + 1'b1;
              end
            end else begin
              // 非 Burst 模式 (单 beat):
              //   不可缓存: 仅取一个 word (is_last_word=1), refill_done 触发, 回 IDLE
              //   可缓存:   逐 word 填充, 最后一个 word 完成回 IDLE
              if (!req_cacheable || refill_word == REFILL_CNT_BITS'(NR_WORDS-1)) begin
                if (cpu_rready) begin
                  state <= IC_IDLE;
                end else begin
                  // IFU 反压时，保存总线结果后再应答。
                  resp_data <= refill_word_data;
                  resp_resp <= bus_rresp;
                  resp_id   <= req_arid;
                  state     <= IC_RESP;
                end
              end else begin
                // 还有更多 word 需要取, 递增计数器, 发下一个 AR
                refill_word <= refill_word + 1'b1;
                state       <= IC_REFILL_AR;
              end
            end
          end
        end

        IC_RESP: begin
          if (cpu_rready) state <= IC_IDLE;
        end

        IC_DISCARD_R: begin
          if (bus_rvalid && bus_rready && bus_rlast) state <= IC_IDLE;
        end

        default: state <= IC_IDLE;
      endcase
    end
  end

  // ===================================================================
  // 性能计数器观测信号
  // ===================================================================
  // A hit can stay in IC_LOOKUP while CPU R is back-pressured.  Count the
  // lookup once, when its response is actually consumed; misses leave this
  // state immediately and therefore remain one-cycle events.
  wire lookup_event = (state == IC_LOOKUP) && (!req_cacheable || !hit || cpu_rready);
  assign icache_access     = lookup_event && !rst;
  assign icache_hit        = lookup_event && req_cacheable &&  hit && !rst;
  assign icache_miss       = lookup_event && req_cacheable && !hit && !rst;
  assign icache_uncache    = lookup_event && !req_cacheable    && !rst;
  assign icache_refill_req       = (state == IC_REFILL_AR)                   && !rst;
  assign icache_refill_req_pulse = (state == IC_REFILL_AR) && (prev_state != IC_REFILL_AR) && !rst;
  assign icache_wait_ar          = (state == IC_REFILL_AR)                   && !rst;
  assign icache_wait_r           = (state == IC_REFILL_R)                    && !rst;

endmodule
