// ============================================================================
// ICache - 4 块 x 16B 直接映射, 行内流式填充
//
// 缺失时发起 4 拍突发; 本行目标字所在 beat 一到就立即输出指令, 后续 beat
// 在后台继续填本行。顺序流因此可以把"填充"和"执行"重叠起来:
//   阻塞式: AR + 4 beats + 逐字服务 = 约 9 拍 / 4 条
//   流式:   AR + beat0..3 连续服务 = 约 5 拍 / 4 条
//
// 注意: 填充期间只服务正在填充的这一行，不允许命中其它行 (否则 F 会跑到
// 别的行、重定向取消填充，丢掉正在填的行 — 上一版流式实现就是这样把
// miss 数从 19.5M 推高到 28.8M 的)。
//
// 取消/重定向: 已写 beat 的多行必须作废 (数据已被部分覆盖)；未写 beat 的
// 保留原行；rlast 同拍取消则数据已完整, 仍然提交。
// ============================================================================
module ICache (
  input clk,
  input rst,
  input flush,
  input cancel,

  input         fetch_req_valid,
  output        fetch_req_ready,
  input  [31:0] fetch_pc,
  output        fetch_inst_valid,
  output [31:0] fetch_inst,
  input         fetch_inst_ready,

  output perf_access,
  output perf_hit,
  output perf_miss,
  output perf_refill,
  output perf_compulsory,
  output perf_replace,

  output        arvalid,
  input         arready,
  output [31:0] araddr,
  output [7:0]  arlen,

  input         rvalid,
  output        rready,
  input  [31:0] rdata,
  input         rlast
);

  localparam BLOCKS = 4;
  localparam BEATS  = 4;
  localparam TAG_BITS = 26;

  localparam IDLE   = 2'b00;
  localparam MISS_AR= 2'b01;
  localparam MISS_R = 2'b10;
  localparam DRAIN  = 2'b11;

  reg [31:0] cache_data [0:BLOCKS*BEATS-1];
  reg [TAG_BITS-1:0] cache_tag [0:BLOCKS-1];
  reg [BLOCKS-1:0] cache_valid;
  reg [1:0] state;

  reg [TAG_BITS-1:0] req_tag;
  reg [1:0] req_index;
  reg [1:0] beat_cnt;             // 已填充字数

  wire [1:0] idx_in = fetch_pc[5:4];
  wire [TAG_BITS-1:0] tag_in = fetch_pc[31:6];
  wire [1:0] word_in = fetch_pc[3:2];

  wire hit = cache_valid[idx_in] && (cache_tag[idx_in] == tag_in);
  wire [31:0] hit_data = cache_data[{idx_in, word_in}];

  // 行内流式服务
  wire fill_line_match = ({tag_in, idx_in} == {req_tag, req_index});
  wire partial_hit = (state == MISS_R) && fill_line_match && (word_in < beat_cnt);
  wire beat_is_word = (state == MISS_R) && fill_line_match && rvalid &&
                      (word_in == beat_cnt);
  wire serve = partial_hit || beat_is_word;

  wire [31:0] fill_data = beat_is_word ? rdata : cache_data[{req_index, word_in}];

  assign fetch_req_ready  = (state == IDLE) ? hit : serve;
  assign fetch_inst_valid = (state == IDLE) ? (fetch_req_valid && hit)
                                            : (state == MISS_R && serve);
  assign fetch_inst       = (state == IDLE) ? hit_data : fill_data;

  assign perf_access = fetch_req_valid && (state == IDLE);
  assign perf_hit    = perf_access && hit;
  assign perf_miss   = perf_access && !hit;
  assign perf_compulsory = perf_miss && !cache_valid[idx_in];
  assign perf_replace    = perf_miss && cache_valid[idx_in];

  // 缺失检测同拍发 AR
  wire miss_idle = (state == IDLE) && fetch_req_valid && !hit;
  assign arvalid = (state == MISS_AR) || miss_idle;
  assign araddr  = (state == MISS_AR) ? {req_tag, req_index, 4'b0000}
                                      : {tag_in, idx_in, 4'b0000};
  assign arlen   = BEATS - 1;

  assign rready  = (state == MISS_R) || (state == DRAIN);
  assign perf_refill = arvalid && arready;

  wire ar_fire = arvalid && arready;
  wire r_fire  = rvalid && rready;
  wire last_beat_now = (state == MISS_R) && rvalid && rlast;

  // 取消时: 已写入 beat 的被替换行必须作废；未写入则保留原行
  wire partial_dirty = (beat_cnt != 2'd0);

  always @(posedge clk) begin
    if (rst) begin
      cache_valid <= {BLOCKS{1'b0}};
      state       <= IDLE;
      req_tag     <= {TAG_BITS{1'b0}};
      req_index   <= 2'b0;
      beat_cnt    <= 2'b0;
    end else if (flush) begin
      cache_valid <= {BLOCKS{1'b0}};
      if (last_beat_now) begin
        state <= IDLE;
      end else if (state == DRAIN) begin
        state <= (r_fire && rlast) ? IDLE : DRAIN;
      end else if (state == MISS_R || (state == MISS_AR && ar_fire)) begin
        state <= DRAIN;
      end else begin
        state <= IDLE;
      end
    end else if (cancel) begin
      if (last_beat_now) begin
        // 最后一拍同拍取消: 数据已完整, 必须把这一拍也写进去再提交
        cache_data[{req_index, beat_cnt}] <= rdata;
        cache_tag[req_index]   <= req_tag;
        cache_valid[req_index] <= 1'b1;
        state <= IDLE;
      end else if (state == DRAIN) begin
        state <= (r_fire && rlast) ? IDLE : DRAIN;
      end else if (state == MISS_R || (state == MISS_AR && ar_fire)) begin
        if (partial_dirty) cache_valid[req_index] <= 1'b0;
        state <= DRAIN;
      end else if (state == MISS_AR) begin
        if (partial_dirty) cache_valid[req_index] <= 1'b0;
        state <= IDLE;
      end else begin
        state <= IDLE;
      end
    end else begin
      case (state)
        IDLE: begin
          if (fetch_req_valid && !hit) begin
            req_tag   <= tag_in;
            req_index <= idx_in;
            beat_cnt  <= 2'b0;
            state     <= ar_fire ? MISS_R : MISS_AR;
          end
        end

        MISS_AR: begin
          if (ar_fire) state <= MISS_R;
        end

        MISS_R: begin
          if (r_fire) begin
            cache_data[{req_index, beat_cnt}] <= rdata;
            beat_cnt <= beat_cnt + 2'd1;
            if (rlast) begin
              cache_tag[req_index]   <= req_tag;
              cache_valid[req_index] <= 1'b1;
              state <= IDLE;
            end
          end
        end

        DRAIN: begin
          if (r_fire && rlast) state <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
