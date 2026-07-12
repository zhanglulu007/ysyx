// ===================================================================
// ICachePipelined - 流水化 ICache
// ===================================================================
// 目标：将 ICache 访问流水化，命中时吞吐接近 1 条指令/周期。
//
// 流水线阶段划分（3 级）：
//   S1 (REQ)   : 接收 CPU AR 请求，锁存地址，计算 tag/index/offset
//   S2 (HIT)   : 组合逻辑查 tag + 读 cache 数据，判断命中/缺失
//   S3 (RESP)  : 寄存输出，向 CPU 返回 rdata/rvalid
//
// 命中路径流水线时空图：
//       T1   T2   T3   T4   T5
// I1  | S1 | S2 | S3 |    |
// I2       | S1 | S2 | S3 |
// I3            | S1 | S2 | S3|
//
// 缺失路径：S2 检测到缺失后暂停 S1，启动 refill FSM，
//           refill 完成后重启流水线。
// ===================================================================

module ICachePipelined #(
  parameter BLOCK_SIZE   = 16,   // 块大小 (字节)
  parameter NR_CACHE_BLK = 4     // 缓存块数
)(
  input         clk,
  input         rst,

  // ===== CPU 侧 (IFU) =====
  input         cpu_arvalid,
  output        cpu_arready,
  input  [31:0] cpu_araddr,
  input  [ 3:0] cpu_arid,
  input  [ 7:0] cpu_arlen,
  input  [ 2:0] cpu_arsize,
  input  [ 1:0] cpu_arburst,

  output        cpu_rvalid,
  input         cpu_rready,
  output [31:0] cpu_rdata,
  output [ 1:0] cpu_rresp,
  output        cpu_rlast,
  output [ 3:0] cpu_rid,

  // ===== 总线侧 (AXIArbiter) =====
  output        bus_arvalid,
  input         bus_arready,
  output [31:0] bus_araddr,
  output [ 3:0] bus_arid,
  output [ 7:0] bus_arlen,
  output [ 2:0] bus_arsize,
  output [ 1:0] bus_arburst,

  input         bus_rvalid,
  output        bus_rready,
  input  [31:0] bus_rdata,
  input  [ 1:0] bus_rresp,
  input         bus_rlast,
  input  [ 3:0] bus_rid,

  // ===== 性能计数器观测 =====
  output        icache_access,
  output        icache_hit,
  output        icache_miss,
  output        icache_uncache,
  output        icache_refill_req,
  output        icache_refill_req_pulse,
  output        icache_wait_ar,
  output        icache_wait_r,

  // ===== fence.i =====
  input         flush
);
  // ===================================================================
  // 参数推导
  // ===================================================================
  localparam ADDR_WIDTH      = 32;
  localparam BUS_WIDTH       = 4;
  localparam NR_WORDS        = BLOCK_SIZE / BUS_WIDTH;
  localparam OFFSET_BITS     = $clog2(BLOCK_SIZE);
  localparam WORD_IDX_BITS   = (OFFSET_BITS > 2) ? (OFFSET_BITS - 2) : 1;
  localparam INDEX_BITS      = $clog2(NR_CACHE_BLK);
  localparam TAG_BITS        = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS;
  localparam REFILL_CNT_BITS = (NR_WORDS > 1) ? $clog2(NR_WORDS) : 1;
  localparam REFILL_ADDR_PAD = 32 - REFILL_CNT_BITS - 2;
  localparam BURST_LEN       = NR_WORDS - 1;

  // ===================================================================
  // Cache 存储阵列
  // ===================================================================
  reg [(BLOCK_SIZE*8)-1:0] cache_data [0:NR_CACHE_BLK-1];
  reg [TAG_BITS-1:0]       cache_tag  [0:NR_CACHE_BLK-1];
  reg                      cache_valid[0:NR_CACHE_BLK-1];

  integer ci;
  always @(posedge clk) begin
    if (rst || flush) begin
      for (ci = 0; ci < NR_CACHE_BLK; ci = ci + 1) begin
        cache_valid[ci] <= 1'b0;
      end
    end
  end

  // ===================================================================
  // S1 阶段：接收请求，锁存地址
  // ===================================================================
  reg         s1_valid;       // S1 有有效请求
  reg  [31:0] s1_addr;
  reg  [ 3:0] s1_arid;

  // S1 地址拆解（组合逻辑）
  wire [OFFSET_BITS-1:0]    s1_offset    = s1_addr[OFFSET_BITS-1:0];
  wire [INDEX_BITS-1:0]     s1_index     = s1_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  wire [TAG_BITS-1:0]       s1_tag       = s1_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];
  wire [WORD_IDX_BITS-1:0]  s1_word_idx;
  generate
    if (OFFSET_BITS > 2) begin
      assign s1_word_idx = s1_addr[OFFSET_BITS-1:2];
    end else begin
      assign s1_word_idx = {WORD_IDX_BITS{1'b0}};
    end
  endgenerate

  // 可缓存判定
  wire s1_is_cacheable = (s1_addr[31:28] == 4'h3) ||  // Flash
                         (s1_addr[31:28] == 4'h8) ||  // PSRAM
                         (s1_addr[31:28] == 4'ha);     // SDRAM

  // ===================================================================
  // S2 阶段：查 Tag + 读数据 + 命中判定（组合逻辑）
  // ===================================================================
  reg         s2_valid;       // S2 有有效请求
  reg  [31:0] s2_addr;
  reg  [ 3:0] s2_arid;
  reg         s2_cacheable;   // S2 缓存此标志

  // S2 地址拆解（从锁存的 s2_addr 计算）
  wire [INDEX_BITS-1:0]     s2_index     = s2_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  wire [TAG_BITS-1:0]       s2_tag       = s2_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];
  wire [WORD_IDX_BITS-1:0]  s2_word_idx;
  generate
    if (OFFSET_BITS > 2) begin
      assign s2_word_idx = s2_addr[OFFSET_BITS-1:2];
    end else begin
      assign s2_word_idx = {WORD_IDX_BITS{1'b0}};
    end
  endgenerate

  // S2 组合逻辑命中判定
  wire s2_hit_raw = cache_valid[s2_index] && (cache_tag[s2_index] == s2_tag);
  wire s2_hit     = s2_cacheable && s2_hit_raw;

  // S2 从 cache_data 中读取数据（组合逻辑）
  wire [31:0] s2_hit_word = cache_data[s2_index][(s2_word_idx * 32) +: 32];

  // S2 判定是否可突发
  wire s2_is_cacheable  = s2_cacheable;
  wire s2_is_sdram      = (s2_addr[31:28] == 4'ha);
  wire s2_is_burst      = s2_is_cacheable && s2_is_sdram && (NR_WORDS > 1);

  // ===================================================================
  // S3 阶段：输出到 CPU
  // ===================================================================
  reg  [31:0] s3_rdata;
  reg  [ 1:0] s3_rresp;
  reg         s3_rlast;
  reg  [ 3:0] s3_rid;
  reg         s3_valid;       // S3 有有效数据可输出

  // ===================================================================
  // Refill FSM（独立于流水线，缺失时启动）
  // ===================================================================
  localparam RF_IDLE      = 2'b00;
  localparam RF_REFILL_AR = 2'b01;
  localparam RF_REFILL_R  = 2'b10;

  reg [1:0] rf_state;
  reg [1:0] rf_prev_state;
  reg [REFILL_CNT_BITS-1:0] rf_word;
  reg [31:0] rf_addr;    // 当前 refill 请求地址（从 S2 复制）
  reg  [3:0] rf_arid;
  reg        rf_is_burst;
  reg        rf_cacheable;

  // 块对齐地址
  wire [31:0] rf_block_aligned = {rf_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
  wire [31:0] rf_word_offset   = {{REFILL_ADDR_PAD{1'b0}}, rf_word, 2'b0};

  assign bus_arvalid = (rf_state == RF_REFILL_AR);
  assign bus_araddr  = rf_cacheable ?
    (rf_is_burst ? rf_block_aligned : (rf_block_aligned + rf_word_offset)) : rf_addr;
  assign bus_arid    = rf_arid;
  assign bus_arlen   = rf_is_burst ? BURST_LEN : 8'b0;
  assign bus_arsize  = 3'b010;
  assign bus_arburst = 2'b01;

  assign bus_rready  = (rf_state == RF_REFILL_R);

  // Refill 写入 cache
  wire rf_store_beat = (rf_state == RF_REFILL_R) && bus_rvalid && bus_rready &&
                       rf_cacheable && !bus_rresp[1];
  always @(posedge clk) begin
    if (rf_store_beat) begin
      cache_data[s2_index][(rf_word * 32) +: 32] <= bus_rdata;
    end
  end

  wire rf_is_last = rf_is_burst ? bus_rlast :
                    rf_cacheable ? (rf_word == REFILL_CNT_BITS'(NR_WORDS-1)) : 1'b1;

  wire rf_done = (rf_state == RF_REFILL_R) && bus_rvalid && bus_rready && rf_is_last;

  // Refill 完成时写 Tag + Valid
  wire rf_update_tag = rf_done && rf_cacheable && !bus_rresp[1];
  always @(posedge clk) begin
    if (rf_update_tag) begin
      cache_tag  [s2_index] <= s2_tag;
      cache_valid[s2_index] <= 1'b1;
    end
  end

  // Refill 完成时的数据（可能是最后一个 word 的数据，也可能是已写入 cache 的数据）
  wire [31:0] rf_final_data = rf_cacheable ?
    ((rf_word == s2_word_idx) ? bus_rdata : cache_data[s2_index][(s2_word_idx * 32) +: 32]) :
    bus_rdata;

  // Compose S3 response from refill
  wire rf_resp_valid = rf_done;
  wire [31:0] rf_resp_data = rf_final_data;
  wire [1:0] rf_resp_resp = bus_rresp;
  wire [3:0] rf_resp_id = rf_arid;

  // ===================================================================
  // Refill FSM
  // ===================================================================
  always @(posedge clk) begin
    if (rst || flush) begin
      rf_state      <= RF_IDLE;
      rf_prev_state <= RF_IDLE;
      rf_word       <= {REFILL_CNT_BITS{1'b0}};
      rf_addr       <= 32'b0;
      rf_arid       <= 4'b0;
      rf_is_burst   <= 1'b0;
      rf_cacheable  <= 1'b0;
    end else begin
      rf_prev_state <= rf_state;
      case (rf_state)
        RF_IDLE: begin
          // S2 检测到缺失（可缓存缺失 或 不可缓存），启动 refill
          if (s2_valid && !s2_hit) begin
            rf_addr      <= s2_addr;
            rf_arid      <= s2_arid;
            rf_is_burst  <= s2_is_burst;
            rf_cacheable <= s2_is_cacheable;
            rf_word      <= {REFILL_CNT_BITS{1'b0}};
            rf_state     <= RF_REFILL_AR;
          end
        end

        RF_REFILL_AR: begin
          if (bus_arready) begin
            rf_state <= RF_REFILL_R;
          end
        end

        RF_REFILL_R: begin
          if (bus_rvalid && bus_rready) begin
            if (rf_is_burst) begin
              if (bus_rlast) begin
                rf_state <= RF_IDLE;
              end else begin
                rf_word <= rf_word + 1'b1;
              end
            end else begin
              if (!rf_cacheable || rf_word == REFILL_CNT_BITS'(NR_WORDS-1)) begin
                rf_state <= RF_IDLE;
              end else begin
                rf_word <= rf_word + 1'b1;
                rf_state <= RF_REFILL_AR;
              end
            end
          end
        end

        default: rf_state <= RF_IDLE;
      endcase
    end
  end

  // ===================================================================
  // 流水线控制信号
  // ===================================================================
  // Refill 进行中（流水线需要暂停）
  wire rf_busy = (rf_state != RF_IDLE);

  // S3 是否在输出命中结果：S3 有效且不是来自 refill 的结果
  // 这里简化：S3 只从命中路径或 refill 路径来
  // 命中路径：s2_valid && s2_hit → s3_valid 次拍
  // 非命中路径：s2_valid && !s2_hit → refill → s3_valid

  // S2 → S3 推进条件（命中时）
  wire s2_advance = s2_valid && s2_hit && !rst;
  // S3 数据寄存器加载（来自命中）
  wire s3_load_hit = s2_advance;
  // S3 数据寄存器加载（来自 refill 完成）
  wire s3_load_rf  = rf_resp_valid && !rst;

  // S1 是否可以接收新请求
  // 条件：不在 refill 中，且 S1 为空（或者 S1→S2 可以推进）
  wire s1_can_accept = !rf_busy && !s1_valid;

  // CPU AR ready
  assign cpu_arready = s1_can_accept && !rst;

  // ===================================================================
  // S1 → S2 推进
  // ===================================================================
  wire s1_to_s2 = s1_valid && !rf_busy;

  // ===================================================================
  // S3 输出到 CPU
  // ===================================================================
  assign cpu_rvalid = s3_valid;
  assign cpu_rdata  = s3_rdata;
  assign cpu_rresp  = s3_rresp;
  assign cpu_rlast  = s3_rlast;
  assign cpu_rid    = s3_rid;

  // ===================================================================
  // 主时序逻辑
  // ===================================================================
  always @(posedge clk) begin
    if (rst || flush) begin
      s1_valid    <= 1'b0;
      s1_addr     <= 32'b0;
      s1_arid     <= 4'b0;
      s2_valid    <= 1'b0;
      s2_addr     <= 32'b0;
      s2_arid     <= 4'b0;
      s2_cacheable <= 1'b0;
      s3_valid    <= 1'b0;
      s3_rdata    <= 32'b0;
      s3_rresp    <= 2'b0;
      s3_rlast    <= 1'b0;
      s3_rid      <= 4'b0;
    end else begin
      // ---- S1: 接收新请求 ----
      if (cpu_arvalid && cpu_arready) begin
        s1_addr  <= cpu_araddr;
        s1_arid  <= cpu_arid;
        s1_valid <= 1'b1;
      end else if (s1_to_s2) begin
        // S1 推进到 S2，S1 清空
        s1_valid <= 1'b0;
      end

      // ---- S2: 从 S1 推进 ----
      if (s1_to_s2) begin
        s2_addr      <= s1_addr;
        s2_arid      <= s1_arid;
        s2_cacheable <= s1_is_cacheable;
        s2_valid     <= 1'b1;
      end else if (s2_advance) begin
        // S2 推进到 S3，清空 S2
        s2_valid <= 1'b0;
      end else if (rf_busy && s2_valid && !s2_hit) begin
        // Refill 进行中，但 S2 地址已传给 refill FSM
        // Refill 完成后 S2 不再需要（数据直接进 S3）
        // 但为了简单，让 S2 保持直到 refill 完成
        // 实际上 S2 的地址一直用于 rf_addr，refill 完成后 S2 数据不进 S3
        // 保持 s2_valid 直到 refill 完成
      end

      // ---- S3: 从 S2 或 Refill 加载 ----
      if (s3_load_hit) begin
        // 命中路径：S2 数据加载到 S3
        s3_valid <= 1'b1;
        s3_rdata <= s2_hit_word;
        s3_rresp <= 2'b00;
        s3_rlast <= 1'b1;
        s3_rid   <= s2_arid;
      end else if (s3_load_rf) begin
        // Refill 完成：数据加载到 S3
        s3_valid <= 1'b1;
        s3_rdata <= rf_resp_data;
        s3_rresp <= rf_resp_resp;
        s3_rlast <= 1'b1;
        s3_rid   <= rf_resp_id;
      end else if (cpu_rvalid && cpu_rready) begin
        // CPU 已取走数据，清空 S3
        s3_valid <= 1'b0;
      end
    end
  end

  // ===================================================================
  // 性能计数器（保持与原 ICache 兼容）
  // ===================================================================
  assign icache_access          = s1_valid && !rst;
  assign icache_hit             = s1_valid && s1_is_cacheable && s2_hit_raw && !rst;
  assign icache_miss            = s1_valid && s1_is_cacheable && !s2_hit_raw && !rst;
  assign icache_uncache         = s1_valid && !s1_is_cacheable && !rst;
  assign icache_refill_req      = (rf_state == RF_REFILL_AR) && !rst;
  assign icache_refill_req_pulse = (rf_state == RF_REFILL_AR) && (rf_prev_state != RF_REFILL_AR) && !rst;
  assign icache_wait_ar         = (rf_state == RF_REFILL_AR) && !rst;
  assign icache_wait_r          = (rf_state == RF_REFILL_R) && !rst;

endmodule
