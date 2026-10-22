module ICache (
  input clk,
  input rst,
  input flush,

  // IFU AXI4 AR
  input ifu_arvalid,
  output ifu_arready,
  input [31:0] ifu_araddr,

  // IFU AXI4 R
  output ifu_rvalid,
  input ifu_rready,
  output [31:0] ifu_rdata,

  // AXI4 AR to Arbiter
  output arvalid,
  input arready,
  output [31:0] araddr,
  output [7:0] arlen,

  // AXI4 R to Arbiter
  input rvalid,
  output rready,
  input [31:0] rdata,
  input rlast
);

  localparam BLOCKS = 4;
  localparam INDEX_BITS = 2;
  // 只缓存 0x3000_0000/0xa000_0000 两个区间: tag={addr[31],addr[24:6]}
  localparam TAG_BITS = 20;
  localparam OFFSET_BITS = 4;
  localparam BEATS = 4;

  localparam IDLE = 2'b00;
  localparam MISS_AR = 2'b01;
  localparam MISS_R = 2'b10;
  localparam RETURN = 2'b11;

  reg [31:0] cache_data [0:BLOCKS*BEATS-1];
  reg [TAG_BITS-1:0] cache_tag [0:BLOCKS-1];
  reg [BLOCKS-1:0] cache_valid;
  reg [1:0] state;

  reg [TAG_BITS-1:0] req_tag;
  reg [INDEX_BITS-1:0] req_index;
  reg [1:0] req_word;
  reg [1:0] beat_cnt;
  reg [31:0] rdata_q;

  wire [INDEX_BITS-1:0] req_index_in = ifu_araddr[5:4];
  wire [TAG_BITS-1:0] req_tag_in = {ifu_araddr[31], ifu_araddr[24:6]};
  wire [1:0] req_word_in = ifu_araddr[3:2];
  wire hit = cache_valid[req_index_in] &&
             (cache_tag[req_index_in] == req_tag_in);

  wire [31:0] hit_rdata = cache_data[req_index_in * BEATS + req_word_in];

  assign ifu_arready = !rst && (state == IDLE);
  assign ifu_rvalid  = !rst && ((state == IDLE && ifu_arvalid && hit) ||
                                (state == RETURN));
  assign ifu_rdata   = (state == IDLE) ? hit_rdata : rdata_q;

  wire [31:0] refill_base = req_tag[TAG_BITS-1] ? 32'hA000_0000 : 32'h3000_0000;
  wire [31:0] refill_tag  = {13'b0, req_tag[TAG_BITS-2:0]} << 6;
  wire [31:0] refill_idx  = {30'b0, req_index} << OFFSET_BITS;
  wire [31:0] refill_addr = refill_base | refill_tag | refill_idx;

  assign arvalid = !rst && (state == MISS_AR);
  assign araddr  = refill_addr;
  assign arlen   = BEATS - 1;

  assign rready  = !rst && (state == MISS_R);

  always @(posedge clk) begin
    if (rst) begin
      cache_valid <= {BLOCKS{1'b0}};
      state <= IDLE;
      req_tag <= {TAG_BITS{1'b0}};
      req_index <= {INDEX_BITS{1'b0}};
      req_word <= 2'b0;
      beat_cnt <= 2'b0;
      rdata_q <= 32'b0;
    end else if (flush) begin
      cache_valid <= {BLOCKS{1'b0}};
      state <= IDLE;
      beat_cnt <= 2'b0;
    end else begin
      case (state)
        IDLE: begin
          if (ifu_arvalid && ifu_arready && !hit) begin
            req_tag   <= req_tag_in;
            req_index <= req_index_in;
            req_word  <= req_word_in;
            beat_cnt  <= 2'b0;
            state <= MISS_AR;
          end
          // hit: stay in IDLE, data is consumed combinationally by IFU
        end

        MISS_AR: begin
          if (arvalid && arready) begin
            state <= MISS_R;
          end
        end

        MISS_R: begin
          if (rvalid && rready) begin
            cache_data[req_index * BEATS + beat_cnt] <= rdata;
            if (beat_cnt == req_word) rdata_q <= rdata;
            beat_cnt <= beat_cnt + 2'd1;
            if (rlast) begin
              cache_tag[req_index]   <= req_tag;
              cache_valid[req_index] <= 1'b1;
              state <= RETURN;
            end
          end
        end

        RETURN: begin
          if (ifu_rready) state <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
