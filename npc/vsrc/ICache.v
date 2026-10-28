//============================================================================
// ICache.v - pipelined I-cache: 1 instruction/cycle on hit, burst refill
// with streaming delivery and uncached bypass.
//
// Critical-word-first: the refill burst starts at the requested word and wraps
// around the cache line (AXI4 WRAP, burst type 2'b10) instead of always
// starting at word 0.  The requested instruction therefore arrives on the
// first beat, cutting miss latency from up to WORDS beats down to 1.
//
// Only the SoC memory side splits a burst into beats (SDRAM hangs directly off
// the AXI4Xbar and its controller implements WRAP); the standalone PMEM model
// always increments by 4 and ignores the burst type, so non-SoC builds bypass
// the cache entirely and never issue a refill.
//============================================================================
`ifndef IC_SETS
`define IC_SETS 4
`endif
`ifndef IC_WORDS
`define IC_WORDS 8
`endif

module ICache(
  input clk,
  input rst,
  input flush,

  input  [31:0] cpu_addr,
  input         cpu_req,
  output        cpu_ready,
  output [31:0] cpu_inst,
  output        cpu_cacheable,
  output        cpu_was_miss,
  output        cpu_stall,

  output        arvalid,
  input         arready,
  output [31:0] araddr,
  output [7:0]  arlen,
  output [1:0]  arburst,
  output        ar_prefetch,

  input         rvalid,
  output        rready,
  input  [31:0] rdata,
  input         rlast,

  output        idle,
  output        miss_replace_pulse,
  output        miss_compulsory_pulse
);

  localparam SETS  = `IC_SETS;
  localparam WORDS = `IC_WORDS;
  localparam IDX_BITS  = $clog2(SETS);
  localparam WORD_BITS = $clog2(WORDS);
  localparam OFF_BITS  = 2 + WORD_BITS;
  localparam TAG_BITS  = 32 - OFF_BITS - IDX_BITS;

  localparam [1:0] BURST_INCR = 2'b01;
  localparam [1:0] BURST_WRAP = 2'b10;

  localparam S_IDLE    = 3'd0;
  localparam S_FILL_AR = 3'd1;
  localparam S_FILL_R  = 3'd2;
  localparam S_BYP_AR  = 3'd3;
  localparam S_BYP_R   = 3'd4;

  reg [31:0] data [0:SETS*WORDS-1];
  reg [TAG_BITS-1:0] tag [0:SETS-1];
  reg [SETS-1:0] valid;

  reg [2:0] state;
  reg [31:0] fill_line;
  reg [IDX_BITS-1:0] fill_idx;
  reg [TAG_BITS-1:0] fill_tag;
  reg [WORD_BITS-1:0] fill_cnt;
  reg [WORD_BITS-1:0] fill_start;   // word offset the wrap burst begins at
  reg [31:0] byp_addr;
  reg req_was_miss;

  wire [WORD_BITS-1:0] req_word = cpu_addr[2 +: WORD_BITS];
  wire [IDX_BITS-1:0]  req_idx  = cpu_addr[OFF_BITS +: IDX_BITS];
  wire [TAG_BITS-1:0]  req_tag  = cpu_addr[OFF_BITS+IDX_BITS +: TAG_BITS];
  wire [31:0] req_line = {cpu_addr[31:OFF_BITS], {OFF_BITS{1'b0}}};

  // Address handed to the bus for a refill: with critical-word-first this is
  // the requested word inside the line, not the line base.
  wire [31:0] fill_addr = fill_line + {27'b0, fill_start, 2'b00};

  // Word slot a returning beat belongs to.  A WRAP burst walks the line in
  // wrap order, so the write-back index is (fill_start + fill_cnt) mod WORDS.
  wire [WORD_BITS-1:0] fill_wr_word = fill_start + fill_cnt;

  wire is_flash = (cpu_addr >= 32'h3000_0000) && (cpu_addr < 32'h3100_0000);
  wire is_sdram = (cpu_addr >= 32'ha000_0000) && (cpu_addr < 32'ha200_0000);
`ifdef SOC_MODE
  // SoC mode: only the SDRAM / XIP-flash windows are cacheable.  SDRAM hangs
  // directly off the AXI4Xbar and its controller implements WRAP, so a
  // critical-word-first refill is honoured there.
  wire cacheable = is_flash || is_sdram;
`else
  // Standalone mode: the PMEM model walks a burst by adding 4 every beat and
  // ignores the AXI burst type, so it cannot serve a WRAP line.  Bypass the
  // cache entirely -- every access goes straight to PMEM.
  wire cacheable = 1'b0;
`endif
  assign cpu_cacheable = cacheable;

  wire hit = valid[req_idx] && (tag[req_idx] == req_tag);
  wire [31:0] hit_data = data[req_idx*WORDS + req_word];

  // Streaming fill: hand the instruction to the core as soon as its own word
  // has landed, without waiting for the rest of the line.  With a WRAP burst
  // the beats arrive in wrap order, so "already landed" must be expressed as a
  // modular distance from the burst start rather than req_word < fill_cnt.
  wire fill_line_match = (state == S_FILL_R) && (req_line == fill_line);
  wire [WORD_BITS-1:0] req_dist = req_word - fill_start;  // beats until req_word
  wire fill_has_word   = fill_line_match &&
                         ((req_dist < fill_cnt) ||
                          (rvalid && (req_dist == fill_cnt)));
  wire [31:0] fill_stream_data = (req_dist == fill_cnt) ? rdata
                                                         : data[req_idx*WORDS + req_word];

  assign cpu_ready = !rst && (cacheable ? (hit || fill_has_word)
                                        : ((state == S_BYP_R) && rvalid &&
                                           (cpu_addr == byp_addr)));
  // Bypass reads drive the instruction straight from the bus; cached reads come
  // from the array on a hit, or from the streaming fill while the line lands.
  assign cpu_inst  = cacheable ? (hit ? hit_data : fill_stream_data) : rdata;
  assign cpu_was_miss = req_was_miss;
  assign cpu_stall = cpu_req && !cpu_ready;

  wire demand_miss = cpu_req && cacheable && !hit;

  assign arvalid = !rst && ((state == S_FILL_AR) || (state == S_BYP_AR));
  assign araddr  = (state == S_BYP_AR) ? byp_addr : fill_addr;
  assign arlen   = (state == S_BYP_AR) ? 8'd0 : (WORDS - 1);
  assign arburst = (state == S_BYP_AR) ? BURST_INCR : BURST_WRAP;
  assign ar_prefetch = 1'b0;
  assign rready  = !rst && ((state == S_FILL_R) || (state == S_BYP_R));
  assign idle    = (state == S_IDLE);

  wire ar_fire = arvalid && arready;

  always @(posedge clk) begin
    if (rst) begin
      state <= S_IDLE;
      valid <= {SETS{1'b0}};
      fill_cnt <= {WORD_BITS{1'b0}};
      fill_start <= {WORD_BITS{1'b0}};
      req_was_miss <= 1'b0;
    end else if (flush) begin
      valid <= {SETS{1'b0}};
      state <= S_IDLE;
      fill_cnt <= {WORD_BITS{1'b0}};
      fill_start <= {WORD_BITS{1'b0}};
      req_was_miss <= 1'b0;
    end else begin
      case (state)
        S_IDLE: begin
          if (cpu_req && !cacheable) begin
            state <= S_BYP_AR;
            byp_addr <= cpu_addr;
            req_was_miss <= 1'b0;
          end else if (demand_miss) begin
            state <= S_FILL_AR;
            fill_line  <= req_line;
            fill_idx   <= req_idx;
            fill_tag   <= req_tag;
            fill_start <= req_word;   // critical word first
            fill_cnt   <= {WORD_BITS{1'b0}};
            valid[req_idx] <= 1'b0;
            req_was_miss <= 1'b1;
          end
        end

        S_FILL_AR: begin
          if (ar_fire) begin
            state <= S_FILL_R;
            fill_cnt <= {WORD_BITS{1'b0}};
          end
        end

        S_FILL_R: begin
          if (rvalid && rready) begin
            data[fill_idx*WORDS + fill_wr_word] <= rdata;
            if (rlast) begin
              tag[fill_idx]   <= fill_tag;
              valid[fill_idx] <= 1'b1;
              state <= S_IDLE;
            end else begin
              fill_cnt <= fill_cnt + 1'b1;
            end
          end
        end

        S_BYP_AR: begin
          if (arvalid && arready) state <= S_BYP_R;
        end

        S_BYP_R: begin
          if (rvalid && rready) state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase

      if (cpu_req && cpu_ready && cacheable && req_was_miss)
        req_was_miss <= 1'b0;
    end
  end

  reg miss_replace_pulse_r, miss_compulsory_pulse_r;
  always @(posedge clk) begin
    if (rst) begin
      miss_replace_pulse_r <= 1'b0;
      miss_compulsory_pulse_r <= 1'b0;
    end else begin
      miss_replace_pulse_r <= 1'b0;
      miss_compulsory_pulse_r <= 1'b0;
      if ((state == S_IDLE) && demand_miss) begin
        if (valid[req_idx]) miss_replace_pulse_r <= 1'b1;
        else                miss_compulsory_pulse_r <= 1'b1;
      end
    end
  end
  assign miss_replace_pulse = miss_replace_pulse_r;
  assign miss_compulsory_pulse = miss_compulsory_pulse_r;

endmodule
