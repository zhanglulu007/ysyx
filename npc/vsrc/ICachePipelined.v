// ===================================================================
// ICachePipelined - 流水化 ICache (v2 - 修复版)
// ===================================================================
// 目标：将 ICache 访问流水化，命中时吞吐接近 1 条指令/周期。
//
// 流水线阶段划分（3 级）：
//   S1 (REQ)   : 接收 CPU AR 请求，锁存地址
//   S2 (LOOKUP): 查 Tag + 读 cache 数据 + 命中判定（组合逻辑）
//   S3 (RESP)  : 寄存输出，向 CPU 返回 rdata/rvalid
//
// 命中路径：
//   S1→S2→S3 各 1 拍，连续请求可每个周期返回 1 条指令。
//
// 缺失路径：S2 检测到缺失后暂停 S1，启动独立 refill FSM，
//           refill 完成后重启流水线。
// ===================================================================

module ICachePipelined #(
  parameter BLOCK_SIZE   = 16,
  parameter NR_CACHE_BLK = 4
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

  // ===== 总线侧 =====
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

  // ===== 性能计数器 =====
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
  // 参数
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
  // S1 阶段寄存器
  // ===================================================================
  reg         s1_valid;
  reg  [31:0] s1_addr;
  reg  [ 3:0] s1_arid;

  // ===================================================================
  // S2 阶段寄存器
  // ===================================================================
  reg         s2_valid;
  reg  [31:0] s2_addr;
  reg  [ 3:0] s2_arid;
  reg         s2_cacheable;

  // ===================================================================
  // S3 阶段寄存器
  // ===================================================================
  reg         s3_valid;
  reg  [31:0] s3_rdata;
  reg  [ 1:0] s3_rresp;
  reg         s3_rlast;
  reg  [ 3:0] s3_rid;

  // ===================================================================
  // Refill FSM
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
  // 注意：s2_index 必须在 refill 期间保持有效
  wire rf_store_beat = (rf_state == RF_REFILL_R) && bus_rvalid && bus_rready &&
                       rf_cacheable && !bus_rresp[1];
  always @(posedge clk) begin
    if (rf_store_beat) begin
      // 使用 rf_addr 计算 index（因为 s2_addr 可能已改变）
      cache_data[rf_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS]][(rf_word * 32) +: 32] <= bus_rdata;
    end
  end

  wire rf_is_last = rf_is_burst ? bus_rlast :
                    rf_cacheable ? (rf_word == REFILL_CNT_BITS'(NR_WORDS-1)) : 1'b1;
  wire rf_done    = (rf_state == RF_REFILL_R) && bus_rvalid && bus_rready && rf_is_last;

  // Refill 完成时写 Tag + Valid
  wire rf_update_tag = rf_done && rf_cacheable && !bus_rresp[1];
  always @(posedge clk) begin
    if (rf_update_tag) begin
      cache_tag  [rf_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS]] <= rf_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];
      cache_valid[rf_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS]] <= 1'b1;
    end
  end

  // Refill 完成时的数据
  // 用 rf_addr 计算 index 和 word_idx 来读取 cache 数据
  wire [INDEX_BITS-1:0]    rf_idx = rf_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  wire [WORD_IDX_BITS-1:0] rf_widx;
  generate
    if (OFFSET_BITS > 2) begin
      assign rf_widx = rf_addr[OFFSET_BITS-1:2];
    end else begin
      assign rf_widx = {WORD_IDX_BITS{1'b0}};
    end
  endgenerate
  wire [31:0] rf_final_data = rf_cacheable ?
    ((rf_word == rf_widx) ? bus_rdata : cache_data[rf_idx][(rf_widx * 32) +: 32]) :
    bus_rdata;

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
          // S2 检测到缺失，启动 refill
          // 必须在 S2 有有效数据且确实 miss 时才启动
          if (s2_valid && s2_cacheable && !s2_hit) begin
            rf_addr      <= s2_addr;
            rf_arid      <= s2_arid;
            rf_is_burst  <= s2_addr[31:28] == 4'ha && (NR_WORDS > 1);
            rf_cacheable <= s2_cacheable;
            rf_word      <= {REFILL_CNT_BITS{1'b0}};
            rf_state     <= RF_REFILL_AR;
          end else if (s2_valid && !s2_cacheable) begin
            // 不可缓存：单 word
            rf_addr      <= s2_addr;
            rf_arid      <= s2_arid;
            rf_is_burst  <= 1'b0;
            rf_cacheable <= 1'b0;
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
  // 命中判定（组合逻辑，用于 S1/S2）
  // ===================================================================
  function [INDEX_BITS-1:0] get_index;
    input [31:0] addr;
    begin
      get_index = addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    end
  endfunction

  function [TAG_BITS-1:0] get_tag;
    input [31:0] addr;
    begin
      get_tag = addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];
    end
  endfunction

  function is_cacheable;
    input [31:0] addr;
    begin
      is_cacheable = (addr[31:28] == 4'h3) || (addr[31:28] == 4'h8) || (addr[31:28] == 4'ha);
    end
  endfunction

  // S1 组合逻辑：基于 s1_addr 判定命中
  wire s1_hit_raw = cache_valid[get_index(s1_addr)] && (cache_tag[get_index(s1_addr)] == get_tag(s1_addr));
  wire s1_cacheable = is_cacheable(s1_addr);
  wire s1_hit = s1_valid && s1_cacheable && s1_hit_raw;

  // S2 组合逻辑：基于 s2_addr 判定命中
  wire s2_hit_raw = cache_valid[get_index(s2_addr)] && (cache_tag[get_index(s2_addr)] == get_tag(s2_addr));
  wire s2_hit = s2_valid && s2_cacheable && s2_hit_raw;

  // ===================================================================
  // 流水线控制
  // ===================================================================
  wire rf_busy    = (rf_state != RF_IDLE);

  // S2 命中时推进到 S3
  wire s2_advance = s2_valid && s2_hit && !rst;
  wire s3_load_hit = s2_advance;

  // S3 从 refill 完成时加载
  wire [31:0] rf_resp_data = rf_final_data;
  wire [1:0] rf_resp_resp = bus_rresp;
  wire [3:0] rf_resp_id   = rf_arid;
  wire s3_load_rf = rf_done && !rst;

  // S1 接收新请求的条件
  wire s1_can_accept = !rf_busy && !s1_valid;
  assign cpu_arready = s1_can_accept && !rst;

  // S1 推进到 S2
  wire s1_to_s2 = s1_valid && !rf_busy;

  // S3 输出
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
        s2_cacheable <= s1_cacheable;
        s2_valid     <= 1'b1;
      end else if (s2_advance) begin
        s2_valid <= 1'b0;
      end
      // 缺失时 s2_valid 保持为 1，等待 refill 完成

      // ---- S3: 命中或 refill 完成时加载 ----
      if (s3_load_hit) begin
        // 命中路径：从 s2_addr 计算 index/word_idx 读取数据
        s3_valid <= 1'b1;
        s3_rdata <= cache_data[get_index(s2_addr)][(get_word_idx(s2_addr) * 32) +: 32];
        s3_rresp <= 2'b00;
        s3_rlast <= 1'b1;
        s3_rid   <= s2_arid;
      end else if (s3_load_rf) begin
        // 缺失路径：refill 完成
        s3_valid <= 1'b1;
        s3_rdata <= rf_resp_data;
        s3_rresp <= rf_resp_resp;
        s3_rlast <= 1'b1;
        s3_rid   <= rf_resp_id;
      end else if (cpu_rvalid && cpu_rready) begin
        s3_valid <= 1'b0;
      end
    end
  end

  // 辅助函数：计算 word_idx
  function [WORD_IDX_BITS-1:0] get_word_idx;
    input [31:0] addr;
    begin
      if (OFFSET_BITS > 2)
        get_word_idx = addr[OFFSET_BITS-1:2];
      else
        get_word_idx = {WORD_IDX_BITS{1'b0}};
    end
  endfunction

  // ===================================================================
  // 性能计数器
  // ===================================================================
  assign icache_access           = s1_valid && !rst;
  assign icache_hit              = s1_valid && s1_cacheable && s1_hit_raw && !rst;
  assign icache_miss             = s1_valid && s1_cacheable && !s1_hit_raw && !rst;
  assign icache_uncache          = s1_valid && !s1_cacheable && !rst;
  assign icache_refill_req       = (rf_state == RF_REFILL_AR) && !rst;
  assign icache_refill_req_pulse = (rf_state == RF_REFILL_AR) && (rf_prev_state != RF_REFILL_AR) && !rst;
  assign icache_wait_ar          = (rf_state == RF_REFILL_AR) && !rst;
  assign icache_wait_r           = (rf_state == RF_REFILL_R) && !rst;

endmodule
