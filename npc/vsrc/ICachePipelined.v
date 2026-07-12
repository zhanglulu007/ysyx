// ===================================================================
// ICachePipelined - 流水化 ICache
// ===================================================================
// 目标：将 ICache 访问流水化，命中时吞吐接近 1 条指令/周期。
//
// 流水线阶段划分（3 级）：
//   S1 (REQ)   : 接收 CPU AR 请求，锁存地址，组合逻辑查 Tag
//   S2 (HIT)   : 读 cache 数据，命中判定，缺失时启动 refill
//   S3 (RESP)  : 寄存输出，向 CPU 返回 rdata/rvalid
//
// 命中路径时空图：
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
  // S1 阶段：接收请求，锁存地址，组合逻辑查 Tag
  // ===================================================================
  reg         s1_valid;       // S1 有有效请求
  reg  [31:0] s1_addr;
  reg  [ 3:0] s1_arid;

  // S1 地址拆解（组合逻辑，用于命中判定）
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

  // S1 组合逻辑命中判定（基于 s1_addr）
  wire s1_hit_raw = cache_valid[s1_index] && (cache_tag[s1_index] == s1_tag);
  wire s1_is_cacheable = (s1_addr[31:28] == 4'h3) ||  // Flash
                         (s1_addr[31:28] == 4'h8) ||  // PSRAM
                         (s1_addr[31:28] == 4'ha);     // SDRAM
  wire s1_hit     = s1_valid && s1_is_cacheable && s1_hit_raw;
  wire s1_cacheable = s1_is_cacheable;

  // ===================================================================
  // S2 阶段：读 cache 数据 + 缺失时启动 refill
  // ===================================================================
  reg         s2_valid;       // S2 有有效请求
  reg  [31:0] s2_addr;
  reg  [ 3:0] s2_arid;
  reg         s2_cacheable;

  // S2 地址拆解
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

  // S2 命中判定
  wire s2_hit_raw = cache_valid[s2_index] && (cache_tag[s2_index] == s2_tag);
  wire s2_hit     = s2_valid && s2_cacheable && s2_hit_raw;
  wire s2_is_sdram = s2_valid && (s2_addr[31:28] == 4'ha);
  wire s2_is_burst = s2_valid && s2_cacheable && s2_is_sdram && (NR_WORDS > 1);

  // S2 从 cache_data 中读取数据（组合逻辑）
  wire [31:0] s2_hit_word = cache_data[s2_index][(s2_word_idx * 32) +: 32];

  // ===================================================================
  // S3 阶段：输出到 CPU
  // ===================================================================
  reg  [31:0] s3_rdata;
  reg  [ 1:0] s3_rresp;
  reg         s3_rlast;
  reg  [ 3:0] s3_rid;
  reg         s3_valid;       // S3 有有效数据可输出

  // ===================================================================
  // Refill FSM（缺失时启动，独立于流水线）
  // ===================================================================
  localparam RF_IDLE      = 2'b00;
  localparam RF_REFILL_AR = 2'b01;
  localparam RF_REFILL_R  = 2'b10;

  reg [1:0] rf_state;
  reg [1:0] rf_prev_state;
  reg [REFILL_CNT_BITS-1:0] rf_word;
  reg [31:0] rf_addr;
  reg  [3:0] rf_arid;
  reg        rf_is_burst;
  reg        rf_cacheable;

  // 块对齐地址
  wire [31:0] rf_block_aligned = {rf_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
  wire [31:0] rf_word_offset   = {{REFILL_ADDR_PAD{1'b0}}, rf_word, 2'b0};

  // 总线 AR 通道
  assign bus_arvalid = (rf_state == RF_REFILL_AR);
  assign bus_araddr  = rf_cacheable ?
    (rf_is_burst ? rf_block_aligned : (rf_block_aligned + rf_word_offset)) : rf_addr;
  assign bus_arid    = rf_arid;
  assign bus_arlen   = rf_is_burst ? BURST_LEN : 8'b0;
  assign bus_arsize  = 3'b010;
  assign bus_arburst = 2'b01;

  // 总线 R 通道
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
  wire rf_done    = (rf_state == RF_REFILL_R) && bus_rvalid && bus_rready && rf_is_last;

  // Refill 完成时写 Tag + Valid
  wire rf_update_tag = rf_done && rf_cacheable && !bus_rresp[1];
  always @(posedge clk) begin
    if (rf_update_tag) begin
      cache_tag  [s2_index] <= s2_tag;
      cache_valid[s2_index] <= 1'b1;
    end
  end

  // Refill 完成时的数据
  wire [31:0] rf_final_data = rf_cacheable ?
    ((rf_word == s2_word_idx) ? bus_rdata : cache_data[s2_index][(s2_word_idx * 32) +: 32]) :
    bus_rdata;

  wire rf_resp_valid = rf_done;
  wire [31:0] rf_resp_data = rf_final_data;
  wire [1:0] rf_resp_resp = bus_rresp;
  wire [3:0] rf_resp_id = rf_arid;

  // ===================================================================
  // Refill FSM 状态机
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
          if (s2_valid && !s2_hit) begin
            rf_addr      <= s2_addr;
            rf_arid      <= s2_arid;
            rf_is_burst  <= s2_is_burst;
            rf_cacheable <= s2_cacheable;
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
  wire rf_busy     = (rf_state != RF_IDLE);

  // S2 命中时推进到 S3
  wire s2_advance  = s2_valid && s2_hit && !rst;
  wire s3_load_hit = s2_advance;          // 命中：S2 数据加载到 S3
  wire s3_load_rf  = rf_resp_valid && !rst; // 缺失：refill 完成加载到 S3

  // S1 接收新请求的条件：不在 refill 中 且 S1 空闲
  wire s1_can_accept = !rf_busy && !s1_valid;
  assign cpu_arready = s1_can_accept && !rst;

  // S1 推进到 S2：S1 有数据 且不在 refill
  wire s1_to_s2 = s1_valid && !rf_busy;

  // S3 输出到 CPU
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
      s1_valid     <= 1'b0;
      s1_addr      <= 32'b0;
      s1_arid      <= 4'b0;
      s2_valid     <= 1'b0;
      s2_addr      <= 32'b0;
      s2_arid      <= 4'b0;
      s2_cacheable <= 1'b0;
      s3_valid     <= 1'b0;
      s3_rdata     <= 32'b0;
      s3_rresp     <= 2'b0;
      s3_rlast     <= 1'b0;
      s3_rid       <= 4'b0;
    end else begin
      // ---- S1: 接收新请求 ----
      if (cpu_arvalid && cpu_arready) begin
        s1_addr  <= cpu_araddr;
        s1_arid  <= cpu_arid;
        s1_valid <= 1'b1;
      end else if (s1_to_s2) begin
        s1_valid <= 1'b0;
      end

      // ---- S2: 从 S1 推进 / 命中后清空 ----
      if (s1_to_s2) begin
        s2_addr      <= s1_addr;
        s2_arid      <= s1_arid;
        s2_cacheable <= s1_is_cacheable;
        s2_valid     <= 1'b1;
      end else if (s2_advance) begin
        // 命中后清空 S2，为下一条指令腾出空间
        s2_valid <= 1'b0;
      end
      // 缺失时 s2_valid 保持为 1，refill FSM 使用 s2_addr/s2_index/s2_tag

      // ---- S3: 从 S2（命中）或 Refill（缺失完成）加载 ----
      if (s3_load_hit) begin
        s3_valid <= 1'b1;
        s3_rdata <= s2_hit_word;
        s3_rresp <= 2'b00;
        s3_rlast <= 1'b1;
        s3_rid   <= s2_arid;
      end else if (s3_load_rf) begin
        s3_valid <= 1'b1;
        s3_rdata <= rf_resp_data;
        s3_rresp <= rf_resp_resp;
        s3_rlast <= 1'b1;
        s3_rid   <= rf_resp_id;
      end else if (cpu_rvalid && cpu_rready) begin
        // CPU 已取走数据
        s3_valid <= 1'b0;
      end
    end
  end

  // ===================================================================
  // 性能计数器（与原 ICache 接口兼容）
  // ===================================================================
  // 基于 S1 的组合逻辑判定，保证计数器准确
  assign icache_access           = s1_valid && !rst;
  assign icache_hit              = s1_valid && s1_is_cacheable && s1_hit_raw && !rst;
  assign icache_miss             = s1_valid && s1_is_cacheable && !s1_hit_raw && !rst;
  assign icache_uncache          = s1_valid && !s1_is_cacheable && !rst;
  assign icache_refill_req       = (rf_state == RF_REFILL_AR) && !rst;
  assign icache_refill_req_pulse = (rf_state == RF_REFILL_AR) && (rf_prev_state != RF_REFILL_AR) && !rst;
  assign icache_wait_ar          = (rf_state == RF_REFILL_AR) && !rst;
  assign icache_wait_r           = (rf_state == RF_REFILL_R) && !rst;

endmodule
