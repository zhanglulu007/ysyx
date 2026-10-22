// ============================================================================
//  ICache - 8 组 x 16B 直接映射指令缓存 + 顺序流式取指
//
//  与 npc/vsrc/ICache.v 的区别:
//   * 容量 64B -> 128B (实测 microbench train 命中率 90.5% -> 95.5%);
//   * 命中后按 32-bit 字连续流出整行, 每个周期一条指令, 不再每字一次 AR/R;
//   * 行边界命中时在最后一条指令输出的同一拍完成下一行查表, 无气泡;
//   * 缺失时 4-beat 突发填充; 重定向时若已有未完成读事务则进入 DRAIN
//     (保持 AXI VALID 不撤销), 否则立即按新地址查表.
//
//  地址划分 (16B 行, 8 组):  tag=addr[31:7], index=addr[6:4],
//                            word=addr[3:2], byte=addr[1:0]
// ============================================================================
module ICache #(
  parameter [31:0] BOOT_PC = 32'h8000_0000
)(
  input  clk,
  input  rst,

  input         flush,          // fence.i: 清空整个 cache
  input         redirect,       // 分支/跳转重定向
  input  [31:0] redirect_addr,

  output [31:0] fetch_addr,     // 当前取指地址 (供 imem_addr 观察)

  output        out_valid,
  output [31:0] out_data,
  input         out_ready,
  output        line_miss,      // 当前流出指令所在行是否来自一次填充

  // AXI4 AR
  output        arvalid,
  input         arready,
  output [31:0] araddr,
  output [7:0]  arlen,

  // AXI4 R
  input         rvalid,
  output        rready,
  input  [31:0] rdata,
  input         rlast
);

  localparam SETS      = 8;
  localparam WORDS     = 4;                 // 每行 4 个 32-bit 字
  localparam TAG_BITS  = 25;
  localparam IDX_BITS  = 3;
  localparam WORD_BITS = 2;

  localparam S_LOOKUP = 3'd0;
  localparam S_MISS_AR= 3'd1;
  localparam S_MISS_R = 3'd2;
  localparam S_STREAM = 3'd3;
  localparam S_DRAIN  = 3'd4;

  reg [31:0] data [0:SETS*WORDS-1];
  reg [TAG_BITS-1:0] tag [0:SETS-1];
  reg [SETS-1:0] valid;

  reg [2:0] state;

  reg [31:0] ra;                 // 当前/下一个要输出的字地址
  reg [TAG_BITS-1:0] req_tag;
  reg [IDX_BITS-1:0] req_index;
  reg [WORD_BITS-1:0] req_word;
  reg [1:0] beat_cnt;
  reg [IDX_BITS-1:0] cur_index;
  reg [WORD_BITS-1:0] cur_word;
  reg pend_redirect;
  reg line_miss_r;

  // ---------------------------------------------------------- 地址分解
  wire [IDX_BITS-1:0] ra_index  = ra[6:4];
  wire [WORD_BITS-1:0] ra_word  = ra[3:2];
  wire [TAG_BITS-1:0] ra_tag    = ra[31:7];
  wire ra_hit = valid[ra_index] && (tag[ra_index] == ra_tag);

  wire [IDX_BITS-1:0] ri_index  = redirect_addr[6:4];
  wire [WORD_BITS-1:0] ri_word  = redirect_addr[3:2];
  wire [TAG_BITS-1:0] ri_tag    = redirect_addr[31:7];
  wire ri_hit = valid[ri_index] && (tag[ri_index] == ri_tag);

  wire [31:0] next_addr = ra + 32'd4;
  wire [IDX_BITS-1:0] nx_index = next_addr[6:4];
  wire [WORD_BITS-1:0] nx_word = next_addr[3:2];
  wire [TAG_BITS-1:0] nx_tag   = next_addr[31:7];
  wire nx_hit = valid[nx_index] && (tag[nx_index] == nx_tag);

  wire [4:0] out_sel = {cur_index, cur_word};

  assign fetch_addr = ra;
  assign out_valid  = (state == S_STREAM);
  assign out_data   = data[out_sel];
  assign line_miss  = line_miss_r;

  assign arvalid = (state == S_MISS_AR);
  assign araddr  = {req_tag, req_index, 4'b0000};
  assign arlen   = 8'd3;
  assign rready  = (state == S_MISS_R) || (state == S_DRAIN);

  wire ar_fire = arvalid && arready;
  wire r_fire  = rvalid && rready;

  // 当前是否有尚未收完的读事务 (决定重定向时能否立即重新查表)
  wire miss_r_last = (state == S_MISS_R) && r_fire && rlast;
  wire outstanding = (state == S_DRAIN) ||
                     ((state == S_MISS_R) && !miss_r_last) ||
                     ((state == S_MISS_AR) && ar_fire);

  integer i;

  always @(posedge clk) begin
    if (rst) begin
      state       <= S_LOOKUP;
      ra          <= BOOT_PC;
      req_tag     <= {TAG_BITS{1'b0}};
      req_index   <= {IDX_BITS{1'b0}};
      req_word    <= {WORD_BITS{1'b0}};
      beat_cnt    <= 2'b0;
      cur_index   <= {IDX_BITS{1'b0}};
      cur_word    <= {WORD_BITS{1'b0}};
      pend_redirect <= 1'b0;
      line_miss_r <= 1'b0;
      valid       <= {SETS{1'b0}};
    end else if (flush) begin
      valid <= {SETS{1'b0}};
      ra    <= redirect_addr;
      if (outstanding) begin
        state       <= S_DRAIN;
        pend_redirect <= 1'b1;
      end else begin
        // 全部行已失效, 新地址必然是 miss, 直接发起填充
        req_tag     <= ri_tag;
        req_index   <= ri_index;
        req_word    <= ri_word;
        beat_cnt    <= 2'b0;
        pend_redirect <= 1'b0;
        state       <= S_MISS_AR;
        line_miss_r <= 1'b1;
      end
    end else begin
      case (state)
        // ------------------------------------------------------ 查表
        S_LOOKUP: begin
          pend_redirect <= 1'b0;
          if (redirect && ri_hit) begin
            ra        <= redirect_addr;
            cur_index <= ri_index;
            cur_word  <= ri_word;
            line_miss_r <= 1'b0;
            state     <= S_STREAM;
          end else if (redirect) begin
            ra        <= redirect_addr;
            req_tag   <= ri_tag;
            req_index <= ri_index;
            req_word  <= ri_word;
            beat_cnt  <= 2'b0;
            line_miss_r <= 1'b1;
            valid[ri_index] <= 1'b0;   // 填充期间该行不可命中
            state     <= S_MISS_AR;
          end else if (ra_hit) begin
            cur_index <= ra_index;
            cur_word  <= ra_word;
            line_miss_r <= 1'b0;
            state     <= S_STREAM;
          end else begin
            req_tag   <= ra_tag;
            req_index <= ra_index;
            req_word  <= ra_word;
            beat_cnt  <= 2'b0;
            line_miss_r <= 1'b1;
            valid[ra_index] <= 1'b0;   // 填充期间该行不可命中
            state     <= S_MISS_AR;
          end
        end

        // ------------------------------------------------------ 发 AR
        S_MISS_AR: begin
          if (ar_fire) begin
            state <= ((redirect || pend_redirect) ? S_DRAIN : S_MISS_R);
            if (redirect) ra <= redirect_addr;
            if (redirect) pend_redirect <= 1'b1;
          end else if (redirect) begin
            ra <= redirect_addr;
            pend_redirect <= 1'b1;
          end
        end

        // ------------------------------------------------------ 收 R (填充)
        S_MISS_R: begin
          if (r_fire) begin
            data[{req_index, beat_cnt}] <= rdata;
            if (rlast) begin
              valid[req_index] <= 1'b1;
              tag[req_index]   <= req_tag;
              pend_redirect    <= 1'b0;
              if (redirect) begin
                // 事务刚好结束; 下一拍查表
                ra        <= redirect_addr;
                line_miss_r <= 1'b1;
                state     <= S_LOOKUP;
              end else begin
                cur_index <= req_index;
                cur_word  <= req_word;
                line_miss_r <= 1'b1;
                state     <= S_STREAM;
              end
            end else begin
              beat_cnt <= beat_cnt + 2'd1;
              if (redirect) begin
                ra <= redirect_addr;
                pend_redirect <= 1'b1;
                state <= S_DRAIN;
              end
            end
          end else if (redirect) begin
            ra <= redirect_addr;
            pend_redirect <= 1'b1;
            state <= S_DRAIN;
          end
        end

        // ------------------------------------------------------ 流式输出
        S_STREAM: begin
          if (redirect) begin
            ra <= redirect_addr;
            if (ri_hit) begin
              cur_index <= ri_index;
              cur_word  <= ri_word;
              line_miss_r <= 1'b0;
              state     <= S_STREAM;
            end else begin
              req_tag   <= ri_tag;
              req_index <= ri_index;
              req_word  <= ri_word;
              beat_cnt  <= 2'b0;
              line_miss_r <= 1'b1;
              valid[ri_index] <= 1'b0;   // 填充期间该行不可命中
              state     <= S_MISS_AR;
            end
          end else if (out_ready) begin
            if (cur_word == 2'd3) begin
              // 当前行最后一个字已送出, 同一拍决策下一行
              ra <= next_addr;
              if (nx_hit) begin
                cur_index <= nx_index;
                cur_word  <= nx_word;
                line_miss_r <= 1'b0;
                state     <= S_STREAM;
              end else begin
                req_tag   <= nx_tag;
                req_index <= nx_index;
                req_word  <= nx_word;
                beat_cnt  <= 2'b0;
                line_miss_r <= 1'b1;
                valid[nx_index] <= 1'b0;   // 填充期间该行不可命中
                state     <= S_MISS_AR;
              end
            end else begin
              cur_word <= cur_word + 2'd1;
              ra       <= next_addr;
              state    <= S_STREAM;
            end
          end
        end

        // ------------------------------------------------------ 丢弃旧读响应
        S_DRAIN: begin
          if (r_fire && rlast) begin
            pend_redirect <= 1'b0;
            state <= S_LOOKUP;
          end
          if (redirect) ra <= redirect_addr;
        end

        default: state <= S_LOOKUP;
      endcase
    end
  end

endmodule
