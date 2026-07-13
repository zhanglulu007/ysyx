module ICache #(
  parameter BLOCK_SIZE   = 8,      // 块大小 (字节)
  parameter NR_CACHE_BLK = 16,     // 缓存块总数
  parameter WAYS          = 2      // 组相联路数 (1=直接映射)
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
  output icache_refill_req_pulse,
  output icache_wait_ar,
  output icache_wait_r,

  // ===== fence.i 控制 =====
  input flush
);

  // ===================================================================
  // Section 1: 参数推导 & 常量
  // ===================================================================
  localparam ADDR_WIDTH      = 32;
  localparam BUS_WIDTH       = 4;
  localparam NR_SETS         = NR_CACHE_BLK / WAYS;
  localparam NR_WORDS        = BLOCK_SIZE / BUS_WIDTH;
  localparam OFFSET_BITS     = $clog2(BLOCK_SIZE);
  localparam WORD_IDX_BITS   = (OFFSET_BITS > 2) ? (OFFSET_BITS - 2) : 1;
  localparam INDEX_BITS      = (NR_SETS <= 1) ? 1 : $clog2(NR_SETS);
  localparam TAG_BITS        = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS;
  localparam REFILL_CNT_BITS = (NR_WORDS > 1) ? $clog2(NR_WORDS) : 1;
  localparam REFILL_ADDR_PAD = 32 - REFILL_CNT_BITS - 2;
  localparam BURST_LEN       = NR_WORDS - 1;
  localparam WAY_BITS        = (WAYS <= 1) ? 1 : $clog2(WAYS);

  localparam IC_IDLE       = 3'd0;
  localparam IC_LOOKUP     = 3'd1;
  localparam IC_REFILL_AR  = 3'd2;
  localparam IC_REFILL_R   = 3'd3;
  localparam IC_RESP       = 3'd4;
  localparam IC_DISCARD_R  = 3'd5;
  localparam IC_DISCARD_AR = 3'd6;

  // ===================================================================
  // Section 2: 状态寄存器 & 存储阵列
  // ===================================================================
  reg [2:0] state;

  reg [(BLOCK_SIZE*8)-1:0] cache_data [0:NR_CACHE_BLK-1];
  reg [TAG_BITS-1:0]       cache_tag  [0:NR_CACHE_BLK-1];
  reg                      cache_valid[0:NR_CACHE_BLK-1];

  function [31:0] flat_idx;
    input [INDEX_BITS-1:0] set;
    input [WAY_BITS-1:0]   way;
    begin
      flat_idx = set * WAYS + {{32-WAY_BITS{1'b0}}, way};
    end
  endfunction

  integer i;
  always @(posedge clk) begin
    if (rst || flush) begin
      for (i = 0; i < NR_CACHE_BLK; i = i + 1) begin
        cache_valid[i] <= 1'b0;
      end
    end
  end

  // ===================================================================
  // Section 3: 请求信息寄存器
  // ===================================================================
  reg [31:0] req_addr;
  reg [ 3:0] req_arid;

  // ===================================================================
  // Section 4: 地址拆解
  // ===================================================================
  wire [INDEX_BITS-1:0] req_index_raw;
  assign req_index_raw = req_addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];

  // 对于 2 次幂 NR_SETS, req_index_raw 位宽恰好覆盖 0..NR_SETS-1, 无需 wrap.
  // 对于非 2 次幂 NR_SETS, req_index_raw 可能 >= NR_SETS, 需要 wrap 到 [0, NR_SETS-1].
  wire [INDEX_BITS-1:0] req_index;
  localparam NR_SETS_IS_POW2 = (NR_SETS & (NR_SETS - 1)) == 0;
  generate
    if (NR_SETS_IS_POW2) begin : g_idx
      assign req_index = req_index_raw;
    end else begin : g_idx
      assign req_index = (req_index_raw >= INDEX_BITS'(NR_SETS))
                         ? (req_index_raw - INDEX_BITS'(NR_SETS))
                         : req_index_raw;
    end
  endgenerate

  wire [OFFSET_BITS-1:0]   req_offset   = req_addr[OFFSET_BITS-1:0];
  wire [TAG_BITS-1:0]      req_tag      = req_addr[ADDR_WIDTH-1 : OFFSET_BITS + INDEX_BITS];

  wire [WORD_IDX_BITS-1:0] req_word_idx;
  generate
    if (OFFSET_BITS > 2) begin : g_widx
      assign req_word_idx = req_addr[OFFSET_BITS-1:2];
    end else begin : g_widx
      assign req_word_idx = {WORD_IDX_BITS{1'b0}};
    end
  endgenerate

  // ===================================================================
  // Section 5: 可缓存判定
  // ===================================================================
  wire req_flash  = (req_addr[31:28] == 4'h3);
  wire req_psram  = (req_addr[31:28] == 4'h8);
  wire req_sdram  = (req_addr[31:28] == 4'ha);
  wire req_cacheable = req_flash || req_psram || req_sdram;

  // ===================================================================
  // Section 6: 命中检测 (组合逻辑, 遍历所有路)
  // ===================================================================
  wire [WAYS-1:0] way_hit;
  generate
    for (genvar w = 0; w < WAYS; w = w + 1) begin : g_wh
      assign way_hit[w] = cache_valid[flat_idx(req_index, w)] &&
                          (cache_tag[flat_idx(req_index, w)] == req_tag);
    end
  endgenerate

  wire hit;
  assign hit = |way_hit;

  // 命中路优先编码器
  wire [WAY_BITS-1:0] hit_way;
  generate
    if (WAYS == 1) begin : g_hw
      assign hit_way = 1'b0;
    end else begin : g_hw
      reg [WAY_BITS-1:0] hw;
      integer hwi;
      always @(*) begin
        hw = {WAY_BITS{1'b0}};
        for (hwi = WAYS-1; hwi >= 0; hwi = hwi - 1)
          if (way_hit[hwi]) hw = hwi[WAY_BITS-1:0];
      end
      assign hit_way = hw;
    end
  endgenerate

  // ===================================================================
  // Section 7: Burst / 块对齐 / Refill word 计数器
  // ===================================================================
  wire is_burst = req_cacheable && req_sdram && (NR_WORDS > 1);

  wire [31:0] block_aligned_addr;
  assign block_aligned_addr = {req_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};

  reg [REFILL_CNT_BITS-1:0] refill_word;

  // ===================================================================
  // Section 8: 总线侧 AR 通道
  // ===================================================================
  wire [31:0] refill_word_addr;
  assign refill_word_addr = {{REFILL_ADDR_PAD{1'b0}}, refill_word, 2'b0};
  wire [31:0] refill_araddr;
  assign refill_araddr = req_cacheable ?
    (is_burst ? block_aligned_addr : (block_aligned_addr + refill_word_addr)) :
    req_addr;

  assign bus_arvalid = (state == IC_REFILL_AR) || (state == IC_DISCARD_AR);
  assign bus_araddr  = refill_araddr;
  assign bus_arid    = req_arid;
  assign bus_arlen   = is_burst ? (BURST_LEN) : 8'b0;
  assign bus_arsize  = 3'b010;
  assign bus_arburst = 2'b01;

  // ===================================================================
  // Section 9: 总线侧 R 通道 — 写入逻辑 (依赖于 victim_way)
  // ===================================================================
  assign bus_rready = (state == IC_REFILL_R) || (state == IC_DISCARD_R);

  // victim_way 声明 (由 Section 10 的 generate 块驱动)
  wire [WAY_BITS-1:0] victim_way;

  // 锁存 victim (IC_LOOKUP 缺失时记录)
  reg [WAY_BITS-1:0] latched_victim;
  always @(posedge clk) begin
    if (rst) begin
      latched_victim <= {WAY_BITS{1'b0}};
    end else if (state == IC_LOOKUP && req_cacheable && !hit) begin
      latched_victim <= victim_way;
    end
  end

  wire do_store_beat = !flush && (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                       req_cacheable && !bus_rresp[1];

  always @(posedge clk) begin
    if (do_store_beat) begin
      cache_data[flat_idx(req_index, latched_victim)][(refill_word * 32) +: 32] <= bus_rdata;
    end
  end

  wire is_last_word = is_burst ? bus_rlast :
                      req_cacheable ? (refill_word == REFILL_CNT_BITS'(NR_WORDS-1)) : 1'b1;

  wire do_refill_done = !flush && (state == IC_REFILL_R) && bus_rvalid && bus_rready &&
                        req_cacheable && !bus_rresp[1] && is_last_word;

  always @(posedge clk) begin
    if (do_refill_done) begin
      cache_tag  [flat_idx(req_index, latched_victim)] <= req_tag;
      cache_valid[flat_idx(req_index, latched_victim)] <= 1'b1;
    end
  end

  // ===================================================================
  // Section 10: LRU 替换策略 & victim_way 驱动
  //   WAYS=1: 无 (victim_way=0)
  //   WAYS=2: 每 set 1 bit MRU
  //   WAYS=4: 树型 PLRU (3 bit/set)
  //   WAYS>4: 轮转 (round-robin)
  // ===================================================================
  generate
    if (WAYS == 2) begin : g_lru
      reg [NR_SETS-1:0] mru;

      always @(posedge clk) begin
        if (rst || flush) begin
          mru <= {NR_SETS{1'b0}};
        end else if (state == IC_LOOKUP && req_cacheable && hit) begin
          mru[req_index] <= hit_way[0];
        end else if (do_refill_done) begin
          mru[req_index] <= victim_way[0];
        end
      end

      assign victim_way = ~mru[req_index];

    end else if (WAYS == 4) begin : g_lru
      reg [NR_SETS-1:0] p_root, p_left, p_right;

      always @(posedge clk) begin
        if (rst || flush) begin
          p_root  <= {NR_SETS{1'b0}};
          p_left  <= {NR_SETS{1'b0}};
          p_right <= {NR_SETS{1'b0}};
        end else if (state == IC_LOOKUP && req_cacheable && hit) begin
          case (hit_way[1:0])
            2'd0: begin p_root[req_index] <= 1'b1; p_left[req_index]  <= 1'b1; end
            2'd1: begin p_root[req_index] <= 1'b1; p_left[req_index]  <= 1'b0; end
            2'd2: begin p_root[req_index] <= 1'b0; p_right[req_index] <= 1'b1; end
            2'd3: begin p_root[req_index] <= 1'b0; p_right[req_index] <= 1'b0; end
          endcase
        end else if (do_refill_done) begin
          case (victim_way[1:0])
            2'd0: begin p_root[req_index] <= 1'b1; p_left[req_index]  <= 1'b1; end
            2'd1: begin p_root[req_index] <= 1'b1; p_left[req_index]  <= 1'b0; end
            2'd2: begin p_root[req_index] <= 1'b0; p_right[req_index] <= 1'b1; end
            2'd3: begin p_root[req_index] <= 1'b0; p_right[req_index] <= 1'b0; end
          endcase
        end
      end

      assign victim_way = p_root[req_index] ?
             (p_right[req_index] ? 2'd3 : 2'd2) :
             (p_left[req_index]  ? 2'd1 : 2'd0);

    end else if (WAYS > 1) begin : g_lru
      reg [WAY_BITS-1:0] rr [0:NR_SETS-1];
      integer ri;

      always @(posedge clk) begin
        if (rst || flush) begin
          for (ri = 0; ri < NR_SETS; ri = ri + 1)
            rr[ri] <= {WAY_BITS{1'b0}};
        end else if (do_refill_done) begin
          rr[req_index] <= rr[req_index] + 1'b1;
        end
      end

      assign victim_way = rr[req_index];

    end else begin : g_lru
      assign victim_way = {WAY_BITS{1'b0}};
    end
  endgenerate

  // ===================================================================
  // Section 11: CPU 侧接口
  // ===================================================================
  assign cpu_arready = !flush && (state == IC_IDLE);

  wire lookup_hit  = (state == IC_LOOKUP)   && req_cacheable &&  hit;
  wire refill_done = (state == IC_REFILL_R) && bus_rvalid && bus_rready && is_last_word;

  wire [31:0] hit_word;
  assign hit_word = cache_data[flat_idx(req_index, hit_way)][(req_word_idx * 32) +: 32];

  wire [31:0] refill_word_data;
  assign refill_word_data = req_cacheable ?
      ((refill_word == req_word_idx) ? bus_rdata
                                     : cache_data[flat_idx(req_index, latched_victim)][(req_word_idx * 32) +: 32]) :
      bus_rdata;

  reg [31:0] resp_data;
  reg [ 1:0] resp_resp;
  reg [ 3:0] resp_id;
  reg [37:0] cpu_response;

  assign cpu_rvalid = !flush && (lookup_hit || refill_done || (state == IC_RESP));
  always @(*) begin
    case ({lookup_hit, refill_done})
      2'b10,
      2'b11: cpu_response = {hit_word, 2'b00, req_arid};
      2'b01: cpu_response = {refill_word_data, bus_rresp, req_arid};
      default: cpu_response = {resp_data, resp_resp, resp_id};
    endcase
  end
  assign cpu_rdata  = cpu_response[37:6];
  assign cpu_rresp  = cpu_response[5:4];
  assign cpu_rlast  = 1'b1;
  assign cpu_rid    = cpu_response[3:0];

  // ===================================================================
  // Section 12: 状态机
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
      if ((state == IC_REFILL_AR || state == IC_DISCARD_AR) && !bus_arready) begin
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
            if (cpu_rready) state <= IC_IDLE;
          end else begin
            refill_word <= {REFILL_CNT_BITS{1'b0}};
            state       <= IC_REFILL_AR;
          end
        end

        IC_REFILL_AR: begin
          if (bus_arready) state <= IC_REFILL_R;
        end

        IC_DISCARD_AR: begin
          if (bus_arready) state <= IC_DISCARD_R;
        end

        IC_REFILL_R: begin
          if (bus_rvalid && bus_rready) begin
            if (is_burst) begin
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
              if (!req_cacheable || refill_word == REFILL_CNT_BITS'(NR_WORDS-1)) begin
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
  // Section 13: 性能计数器
  // ===================================================================
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
