module ICache(
  input clk,
  input rst,

  // ===== CPU 侧 (IFU) =====
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

  // ===== 总线侧 (AXIArbiter) =====
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
  // 可配置参数
  // ===================================================================
  localparam ADDR_WIDTH   = 32;
  localparam BLOCK_SIZE   = 16;           // 字节 (须为 2 的幂, >=4)
  localparam NR_CACHE_BLK = 4;          // cache 块总数 (须为 2 的幂)

  // ===================================================================
  // 派生参数 (取决于 BLOCK_SIZE, NR_CACHE_BLK, NR_WAYS)
  // ===================================================================
  localparam OFFSET_BITS  = $clog2(BLOCK_SIZE);          // log2(BLOCK_SIZE)
  localparam INDEX_BITS   = $clog2(NR_CACHE_BLK);        // log2(NR_CACHE_BLK)
  localparam TAG_BITS     = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS;
  localparam BLOCK_WORDS  = BLOCK_SIZE / 4;              // 每块 32 位字数

  // ===================================================================
  // 状态机
  // ===================================================================
  localparam IC_IDLE      = 2'b00;
  localparam IC_LOOKUP    = 2'b01;
  localparam IC_REFILL_AR = 2'b10;
  localparam IC_REFILL_R  = 2'b11;

  reg [1:0] state;

  // ===================================================================
  // 存储阵列 (触发器实现)
  // ===================================================================
  reg [31:0]         cache_data    [0:NR_CACHE_BLK-1][0:BLOCK_WORDS-1];
  reg [TAG_BITS-1:0] cache_tag     [0:NR_CACHE_BLK-1];
  reg                cache_valid   [0:NR_CACHE_BLK-1];

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

  // 地址拆解
  wire [OFFSET_BITS-1:0] req_offset = req_addr[OFFSET_BITS-1:0];
  wire [INDEX_BITS-1:0]  req_index  = req_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
  wire [TAG_BITS-1:0]    req_tag    = req_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];

  /* verilator lint_off WIDTHEXPAND */
  wire [31:0] req_word_idx = req_offset >> 2;   // 0 ~ BLOCK_WORDS-1
  /* verilator lint_on WIDTHEXPAND */

  // 可缓存地址判定
  wire req_cacheable = (req_addr[31:28] == 4'h3) ||
                       (req_addr[31:28] == 4'h8) ||
                       (req_addr[31:28] == 4'ha);

  // 命中判定
  wire hit = cache_valid[req_index] && (cache_tag[req_index] == req_tag);

  // ===================================================================
  // 总线侧 AR 通道 (独立读事务, 每事务 1 beat)
  // ===================================================================
  reg [31:0] beat_addr_r;       // 当前事务的读地址 (对齐到字)
  reg [7:0]  beat_cnt_r;        // 已完成的 beat 计数 (0..BLOCK_WORDS-1)
  reg        ar_pending;        // 总线 AR 通道等待中

  assign bus_arvalid = ar_pending;
  assign bus_araddr  = beat_addr_r;
  assign bus_arid    = req_arid;
  assign bus_arlen   = 8'b0;            // 1 beat
  assign bus_arsize  = 3'b010;          // 4 字节
  assign bus_arburst = 2'b01;           // INCR

  // ===================================================================
  // 总线侧 R 通道
  // ===================================================================
  assign bus_rready = (state == IC_REFILL_R);

  // 可缓存型缺失的回填
  wire refill_beat = (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                     req_cacheable && !bus_rresp[1];

  always @(posedge clk) begin
    if (refill_beat) begin
      cache_data[req_index][beat_cnt_r[BLOCK_WORDS_BITS-1:0]] <= bus_rdata;
      if (beat_cnt_r == BLOCK_WORDS - 1) begin
        cache_tag  [req_index] <= req_tag;
        cache_valid[req_index] <= 1'b1;
      end
    end
  end

  // ===================================================================
  // CPU 侧 AR 通道: IC_IDLE 时接受 IFU 的请求
  // ===================================================================
  assign cpu_arready = (state == IC_IDLE);

  // ===================================================================
  // CPU 侧 R 通道
  //   命中: 当拍组合逻辑输出 cache_data 中对应字
  //   缺失/不可缓存: 等最后 beat 到达后应答
  // ===================================================================
  wire lookup_hit  = (state == IC_LOOKUP) && req_cacheable && hit;
  wire miss_done   = (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                     (beat_cnt_r == BLOCK_WORDS - 1);
  wire uncache_done= (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                     !req_cacheable;

  assign cpu_rvalid = lookup_hit || miss_done || uncache_done;
  assign cpu_rdata  = lookup_hit ? cache_data[req_index][req_word_idx] : bus_rdata;
  assign cpu_rresp  = (miss_done || uncache_done) ? bus_rresp : 2'b00;
  assign cpu_rlast  = 1'b1;
  assign cpu_rid    = req_arid;

  // ===================================================================
  // 状态机 (组合 next + 时序)
  // ===================================================================
  always @(posedge clk) begin
    if (rst) begin
      state       <= IC_IDLE;
      req_addr    <= 32'b0;
      req_arid    <= 4'b0;
      beat_addr_r <= 32'b0;
      beat_cnt_r  <= 8'b0;
      ar_pending  <= 1'b0;
    end else begin
      case (state)
        IC_IDLE: begin
          if (cpu_arvalid) begin
            req_addr <= cpu_araddr;
            req_arid <= cpu_arid;
            state <= IC_LOOKUP;
          end
        end

        IC_LOOKUP: begin
          if (req_cacheable && hit) begin
            state <= IC_IDLE;
          end else begin
            beat_addr_r <= {req_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
            beat_cnt_r  <= 8'b0;
            ar_pending  <= 1'b1;
            state       <= IC_REFILL_AR;
          end
        end

        IC_REFILL_AR: begin
          if (bus_arready) begin
            ar_pending <= 1'b0;
            state      <= IC_REFILL_R;
          end
        end

        IC_REFILL_R: begin
          if (bus_rvalid && bus_rready) begin
            if (beat_cnt_r == BLOCK_WORDS - 1) begin
              state <= IC_IDLE;
            end else begin
              beat_addr_r <= beat_addr_r + 32'd4;
              beat_cnt_r  <= beat_cnt_r + 8'd1;
              ar_pending  <= 1'b1;
              state       <= IC_REFILL_AR;
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
  assign icache_refill_req = (state == IC_REFILL_AR) && ar_pending     && !rst;
  assign icache_wait_ar    = (state == IC_REFILL_AR)                   && !rst;
  assign icache_wait_r     = (state == IC_REFILL_R)                    && !rst;

endmodule
