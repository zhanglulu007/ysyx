//------------------------------------------------------------------------------
// ICache: 直接映射指令缓存 + 流式填充（early restart）
//
// 设计要点：
//   * 组合读：if_pc -> tag compare -> data mux，命中当拍即可送出指令；
//     这样 IF 级可以做到 1 指令/周期。
//   * 行填充：一次 AXI 突发把整行读入；填充过程中只要请求字已经到达
//     （或正在 beat 上），就允许 IF 继续取指，从而把顺序取指的缺失
//     代价摊薄到接近 2 个周期/行。
//   * 填充期间不允许发起新的 AR；遇到分支跳到别的行时短暂停顿，
//     等当前突发收完再处理，保证 AXI 协议简单可靠。
//
// 默认参数：4 组 x 8 字 x 4B = 128B，行大小 32B。
// 可通过 SETS/WORDS 参数改成 64B（SETS=2）等配置。
//------------------------------------------------------------------------------
module ICache #(
  parameter integer SETS = 4,
  parameter integer WORDS = 8
)(
  input  clk,
  input  rst,
  input  flush,

  // IF side (combinational lookup)
  input  [31:0] if_pc,
  output [31:0] if_inst,
  output        if_valid,       // instruction available this cycle
  output        if_hit,         // lookup hit (for perf)
  output        if_stall_ar,    // waiting for AR acceptance
  output        if_stall_mem,   // waiting for R beats

  // AXI4 AR
  output        arvalid,
  input         arready,
  output [31:0] araddr,
  output [ 7:0] arlen,

  // AXI4 R
  input         rvalid,
  output        rready,
  input  [31:0] rdata,
  input         rlast
);

  function integer clog2;
    input integer value;
    integer j;
    begin
      clog2 = 0;
      for (j = value - 1; j > 0; j = j >> 1) clog2 = clog2 + 1;
    end
  endfunction

  localparam integer INDEX_BITS = (SETS == 1) ? 1 : clog2(SETS);
  localparam integer WORD_BITS  = (WORDS == 1) ? 1 : clog2(WORDS);
  localparam integer TAG_BITS   = 32 - WORD_BITS - INDEX_BITS - 2;
  localparam [WORD_BITS-1:0] LAST_WORD = {WORD_BITS{1'b1}};

  reg [31:0] cache_data [0:SETS*WORDS-1];
  reg [TAG_BITS-1:0] cache_tag [0:SETS-1];
  reg [SETS-1:0] cache_valid;

  // 当前请求的地址分解
  wire [WORD_BITS-1:0]  look_word  = if_pc[WORD_BITS+1:2];
  wire [INDEX_BITS-1:0] look_index = if_pc[WORD_BITS+INDEX_BITS+1:WORD_BITS+2];
  wire [TAG_BITS-1:0]   look_tag   = if_pc[31:WORD_BITS+INDEX_BITS+2];

  wire look_hit = cache_valid[look_index] && (cache_tag[look_index] == look_tag);
  wire [31:0] look_data = cache_data[{look_index, look_word}];

  // 填充状态
  reg                    fill_active;
  reg                    fill_discard;
  reg [TAG_BITS-1:0]     fill_tag;
  reg [INDEX_BITS-1:0]   fill_index;
  reg [WORD_BITS-1:0]    fill_word;
  reg                    req_pending;
  reg [TAG_BITS-1:0]     req_tag;
  reg [INDEX_BITS-1:0]   req_index;

  wire fill_line_match = fill_active &&
                         (fill_tag == look_tag) &&
                         (fill_index == look_index);
  // 当前 beat 正好是请求字时，可以直接 bypass 正在返回的 rdata
  wire fill_word_now = fill_line_match && (fill_word == look_word) && rvalid;
  wire fill_word_past = fill_line_match && (fill_word > look_word);
  wire fill_can_serve = fill_word_now || fill_word_past;

  assign if_hit      = look_hit;
  assign if_valid    = look_hit || fill_can_serve;
  assign if_inst     = look_hit ? look_data :
                       (fill_word_now ? rdata : look_data);
  assign if_stall_ar  = !if_valid && !fill_active;
  assign if_stall_mem = !if_valid &&  fill_active;

  // 缺失请求：命中/可服务时不需要；填充别的行时也要排队
  wire new_miss = !look_hit && !fill_line_match && !req_pending;

  wire        req_valid = req_pending || (new_miss && !fill_active);
  wire [TAG_BITS-1:0]   req_tag_now   = req_pending ? req_tag   : look_tag;
  wire [INDEX_BITS-1:0] req_index_now = req_pending ? req_index : look_index;

  assign arvalid = !rst && !fill_active && req_valid;
  assign araddr  = {req_tag_now, req_index_now, {(WORD_BITS+2){1'b0}}};
  assign arlen   = WORDS[7:0] - 8'd1;

  assign rready  = !rst && fill_active;

  integer i;
  always @(posedge clk) begin
    if (rst) begin
      cache_valid <= {SETS{1'b0}};
      fill_active <= 1'b0;
      fill_discard <= 1'b0;
      fill_word   <= {WORD_BITS{1'b0}};
      req_pending <= 1'b0;
    end else if (flush) begin
      cache_valid <= {SETS{1'b0}};
      req_pending <= 1'b0;
      // 正在进行的突发不能中途取消：置 discard，收完后不写 valid
      if (fill_active) fill_discard <= 1'b1;
    end else begin
      // 记录缺失请求（AR 未握手时保持）
      if (new_miss && !fill_active) begin
        req_pending <= 1'b1;
        req_tag     <= look_tag;
        req_index   <= look_index;
      end

      // AR 握手：开始填充（先失效旧行，避免填充期间旧数据被命中）
      if (arvalid && arready) begin
        fill_active  <= 1'b1;
        fill_discard <= 1'b0;
        fill_word    <= {WORD_BITS{1'b0}};
        fill_tag     <= req_tag_now;
        fill_index   <= req_index_now;
        req_pending  <= 1'b0;
        cache_valid[req_index_now] <= 1'b0;
      end

      // R beat：写数据、推进 beat 计数
      if (fill_active && rvalid && rready) begin
        cache_data[{fill_index, fill_word}] <= rdata;
        if (fill_word == LAST_WORD || rlast) begin
          fill_active <= 1'b0;
          if (!fill_discard) begin
            cache_tag[fill_index]   <= fill_tag;
            cache_valid[fill_index] <= 1'b1;
          end
          fill_discard <= 1'b0;
        end else begin
          fill_word <= fill_word + 1'b1;
        end
      end
    end
  end

`ifdef SIMULATION_ASSERT
  always @(posedge clk) begin
    if (!rst && arvalid && arready && fill_active)
      $display("ASSERT: ICache issued AR while fill_active");
  end
`endif

endmodule
