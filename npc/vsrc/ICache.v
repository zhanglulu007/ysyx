module ICache (
  input clk,
  input rst,

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
  localparam TAG_BITS = 26;
  localparam OFFSET_BITS = 4;
  localparam BEATS = 4;              // 16B 块 / 4B 总线字

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
  reg [1:0] req_word;                // 请求落在块内第几个 32 位字（4 个字）
  reg [1:0] beat_cnt;                // 缺失填充的节拍计数

  wire [INDEX_BITS-1:0] req_index_in = ifu_araddr[5:4];
  wire [TAG_BITS-1:0] req_tag_in = ifu_araddr[31:6];
  wire [1:0] req_word_in = ifu_araddr[3:2];
  wire hit = cache_valid[req_index_in] &&
             (cache_tag[req_index_in] == req_tag_in);

  wire [31:0] hit_rdata = cache_data[req_index * BEATS + req_word];

  assign ifu_arready = !rst && (state == IDLE);
  assign ifu_rvalid  = !rst && (state == RETURN);
  assign ifu_rdata   = hit_rdata;

  assign arvalid = !rst && (state == MISS_AR);
  assign araddr  = {req_tag, req_index, {OFFSET_BITS{1'b0}}};
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
    end else begin
      case (state)
        IDLE: begin
          if (ifu_arvalid && ifu_arready) begin
            req_tag   <= req_tag_in;
            req_index <= req_index_in;
            req_word  <= req_word_in;
            beat_cnt  <= 2'b0;
            if (hit) begin
              state <= RETURN;
            end else begin
              state <= MISS_AR;
            end
          end
        end

        MISS_AR: begin
          if (arvalid && arready) begin
            state <= MISS_R;
          end
        end

        MISS_R: begin
          if (rvalid && rready) begin
            cache_data[req_index * BEATS + beat_cnt] <= rdata;
            beat_cnt <= beat_cnt + 2'd1;
            if (rlast) begin
              cache_tag[req_index]   <= req_tag;
              cache_valid[req_index] <= 1'b1;
              state <= RETURN;
            end
          end
        end

        RETURN: begin
          if (ifu_rvalid && ifu_rready) begin
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
