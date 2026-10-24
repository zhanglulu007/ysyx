module ICache #(
  parameter ADDR_W      = 32,
  parameter BLOCKS      = 4,    // 必须是 2 的幂且 >= 2
  parameter BLOCK_BYTES = 32,   // 2 的幂; 8 <= x <= 1024 (受 arlen 8bit 限制)
  parameter BUS_BYTES   = 4
)(
  input  clk,
  input  rst,
  input  flush,

  input                  ifu_arvalid,
  output                 ifu_arready,
  input  [ADDR_W-1:0]    ifu_araddr,

  output                 ifu_rvalid,
  input                  ifu_rready,
  output [BUS_BYTES*8-1:0] ifu_rdata,

  output                 arvalid,
  input                  arready,
  output [ADDR_W-1:0]    araddr,
  output [7:0]           arlen,

  input                  rvalid,
  output                 rready,
  input  [BUS_BYTES*8-1:0] rdata,
  input                  rlast
);

  localparam DATA_W      = BUS_BYTES * 8;
  localparam BEATS       = BLOCK_BYTES / BUS_BYTES;
  localparam OFFSET_BITS = $clog2(BLOCK_BYTES);
  localparam INDEX_BITS  = $clog2(BLOCKS);
  localparam WORD_BITS   = $clog2(BEATS);          // BEATS>=2 时 == CNT_BITS
  localparam BYTE_BITS   = OFFSET_BITS - WORD_BITS;
  localparam TAG_BITS    = ADDR_W - INDEX_BITS - OFFSET_BITS;
  localparam ENTRIES     = BLOCKS * BEATS;

  // ---- 派生位宽自检 ----
  // synopsys translate_off
  initial begin
    if (BEATS > 256)        $fatal(1, "arlen 只有 8bit, BLOCK_BYTES 最大 1024");
    if (BLOCK_BYTES > 4096) $fatal(1, "AXI 突发不得跨 4KB 边界");
    if (BLOCK_BYTES < 2*BUS_BYTES) $fatal(1, "BEATS 必须 >= 2");
  end
  // synopsys translate_on

  localparam IDLE = 2'b00, MISS_AR = 2'b01, MISS_R = 2'b10, RETURN = 2'b11;

  reg [DATA_W-1:0]   cache_data [0:ENTRIES-1];
  reg [TAG_BITS-1:0] cache_tag  [0:BLOCKS-1];
  reg [BLOCKS-1:0]   cache_valid;
  reg [1:0]          state;

  reg [TAG_BITS-1:0]   req_tag;
  reg [INDEX_BITS-1:0] req_index;
  reg [WORD_BITS-1:0]  req_word;
  reg [WORD_BITS-1:0]  beat_cnt;

  // ---- 地址切分：全部由参数推导，不再有魔法数字 ----
  wire [BYTE_BITS-1:0]  byte_off = ifu_araddr[BYTE_BITS-1:0];
  wire [WORD_BITS-1:0]  word_off = ifu_araddr[OFFSET_BITS-1 -: WORD_BITS];
  wire [INDEX_BITS-1:0] index_in = ifu_araddr[OFFSET_BITS +: INDEX_BITS];
  wire [TAG_BITS-1:0]   tag_in   = ifu_araddr[ADDR_W-1 -: TAG_BITS];

  wire hit = cache_valid[index_in] && (cache_tag[index_in] == tag_in);

  // BEATS 为 2 的幂时，{index, beat} 等价于 index*BEATS+beat，避免乘法器
  wire [DATA_W-1:0] hit_rdata = cache_data[{req_index, req_word}];

  assign ifu_arready = !rst && (state == IDLE);
  assign ifu_rvalid  = !rst && (state == RETURN);
  assign ifu_rdata   = hit_rdata;

  assign arvalid = !rst && (state == MISS_AR);
  assign araddr  = {req_tag, req_index, {OFFSET_BITS{1'b0}}};
  assign arlen   = BEATS[7:0] - 8'd1;      // BEATS<=256 已自检
  assign rready  = !rst && (state == MISS_R);

  always @(posedge clk) begin
    if (rst) begin
      cache_valid <= {BLOCKS{1'b0}};
      state     <= IDLE;
      req_tag   <= {TAG_BITS{1'b0}};
      req_index <= {INDEX_BITS{1'b0}};
      req_word  <= {WORD_BITS{1'b0}};
      beat_cnt  <= {WORD_BITS{1'b0}};
    end else if (flush) begin
      // 建议：只清 valid，不打断在途 AXI 突发（见下文"坑 4"）
      cache_valid <= {BLOCKS{1'b0}};
      state     <= IDLE;
    end else begin
      case (state)
        IDLE: if (ifu_arvalid && ifu_arready) begin
          req_tag   <= tag_in;
          req_index <= index_in;
          req_word  <= word_off;
          beat_cnt  <= {WORD_BITS{1'b0}};
          state     <= hit ? RETURN : MISS_AR;
        end

        MISS_AR: if (arvalid && arready) state <= MISS_R;

        MISS_R: if (rvalid && rready) begin
          cache_data[{req_index, beat_cnt}] <= rdata;
          beat_cnt <= beat_cnt + 1'b1;
          if (rlast) begin
            cache_tag[req_index]   <= req_tag;
            cache_valid[req_index] <= 1'b1;
            state <= RETURN;
          end
        end

        RETURN: if (ifu_rvalid && ifu_rready) state <= IDLE;

        default: state <= IDLE;
      endcase
    end
  end
endmodule
