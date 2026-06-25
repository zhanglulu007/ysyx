// MEM - Memory Module with LFSR Random Delay
// 模拟存储器，内部通过 DPI-C 实现访存，对外呈现单一 AXI4-Lite 接口
// 通过 LFSR 随机延迟 arready/awready/wready 和 rvalid/bvalid, 用于测试总线实现的鲁棒性
//
// 状态机:
//   IDLE:    等待 AR (读) 或 AW+W (写) 握手
//   R_BUSY:  DPI-C 读完成, LFSR 延迟后 rvalid 握手
//   W_BUSY:  DPI-C 写完成, LFSR 延迟后 bvalid 握手
//   写路径:  AW 和 W 可独立握手, 均完成后触发 DPI-C 写

module MEM(
  input clk,
  input rst,

  // ===== AXI4-Lite AR 通道 (读地址) =====
  input         mem_arvalid,
  output        mem_arready,
  input  [31:0] mem_araddr,

  // ===== AXI4-Lite R 通道 (读数据) =====
  output        mem_rvalid,
  input         mem_rready,
  output [31:0] mem_rdata,
  output [ 1:0] mem_rresp,

  // ===== AXI4-Lite AW 通道 (写地址) =====
  input         mem_awvalid,
  output        mem_awready,
  input  [31:0] mem_awaddr,

  // ===== AXI4-Lite W 通道 (写数据) =====
  input         mem_wvalid,
  output        mem_wready,
  input  [31:0] mem_wdata,
  input  [ 3:0] mem_wstrb,

  // ===== AXI4-Lite B 通道 (写回复) =====
  output        mem_bvalid,
  input         mem_bready,
  output [ 1:0] mem_bresp
);

  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

  // ===== LFSR 实例化 =====
  wire [7:0] lfsr_val;
  LFSR u_lfsr(
    .clk(clk),
    .rst(rst),
    .value(lfsr_val)
  );

  // ========== 状态机 ==========
  localparam IDLE    = 2'b00;  // 等待读/写请求
  localparam R_BUSY  = 2'b01;  // 读事务进行中
  localparam W_BUSY  = 2'b10;  // 写事务进行中

  reg [ 1:0] state;
  reg [31:0] rdata_latched;
  reg [ 3:0] req_ready_cnt;    // arready/awready/wready 延迟计数器 (0=就绪)
  reg [ 3:0] resp_delay_cnt;   // rvalid/bvalid 延迟计数器 (0=响应就绪)

  // 写路径追踪: AW 和 W 可独立握手
  reg        aw_done;
  reg        w_done;
  reg [31:0] aw_addr_latched;
  reg [31:0] w_data_latched;
  reg [ 3:0] w_strb_latched;

  // ========== 通道就绪信号 ==========
  // arready: IDLE 时计数器归零, 且无写事务进行中
  assign mem_arready = (state == IDLE) && (req_ready_cnt == 4'd0)
                       && !aw_done && !w_done && !rst;

  // awready: IDLE 时计数器归零 (或 W 已先完成), 且未完成
  assign mem_awready = (state == IDLE) && !aw_done && !rst
                       && ((req_ready_cnt == 4'd0) || w_done);

  // wready: IDLE 时计数器归零 (或 AW 已先完成), 且未完成
  assign mem_wready = (state == IDLE) && !w_done && !rst
                      && ((req_ready_cnt == 4'd0) || aw_done);

  // ========== 响应信号 ==========
  assign mem_rvalid = (state == R_BUSY) && (resp_delay_cnt == 4'd0);
  assign mem_bvalid = (state == W_BUSY) && (resp_delay_cnt == 4'd0);

  assign mem_rdata = rdata_latched;
  assign mem_rresp = 2'b00;  // OKAY
  assign mem_bresp = 2'b00;  // OKAY

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state           <= IDLE;
      rdata_latched   <= 32'b0;
      req_ready_cnt   <= 4'd0;
      resp_delay_cnt  <= 4'd0;
      aw_done         <= 1'b0;
      w_done          <= 1'b0;
      aw_addr_latched <= 32'b0;
      w_data_latched  <= 32'b0;
      w_strb_latched  <= 4'b0;
    end else begin
      // reqReady 延迟计数器: IDLE 时递减到 0
      if (state == IDLE && req_ready_cnt > 4'd0)
        req_ready_cnt <= req_ready_cnt - 4'd1;

      // 响应延迟计数器: BUSY 时递减到 0
      if ((state == R_BUSY || state == W_BUSY) && resp_delay_cnt > 4'd0)
        resp_delay_cnt <= resp_delay_cnt - 4'd1;

      case (state)
        IDLE: begin
          // ----- 读事务: AR 握手 -----
          if (mem_arvalid && mem_arready) begin
            rdata_latched <= pmem_read(mem_araddr);
            resp_delay_cnt <= {1'b0, lfsr_val[2:0]} + 4'd1;  // 1~8 周期
            state <= R_BUSY;
          end
          // ----- 写事务: AW 和 W 握手追踪 -----
          else begin
            // AW 握手
            if (mem_awvalid && mem_awready && !aw_done) begin
              aw_addr_latched <= mem_awaddr;
              aw_done <= 1'b1;
            end

            // W 握手
            if (mem_wvalid && mem_wready && !w_done) begin
              w_data_latched <= mem_wdata;
              w_strb_latched <= mem_wstrb;
              w_done <= 1'b1;
            end

            // AW 和 W 均完成时触发 DPI-C 写
            if (aw_done && w_done) begin
              pmem_write(aw_addr_latched, w_data_latched, {4'b0, w_strb_latched});
              resp_delay_cnt <= {1'b0, lfsr_val[2:0]} + 4'd1;  // 1~8 周期
              state    <= W_BUSY;
              aw_done  <= 1'b0;
              w_done   <= 1'b0;
            end
          end
        end

        R_BUSY: begin
          // R 握手: rvalid && rready
          if (mem_rvalid && mem_rready) begin
            req_ready_cnt <= {1'b0, lfsr_val[5:3]};  // 0~7 周期
            state <= IDLE;
          end
        end

        W_BUSY: begin
          // B 握手: bvalid && bready
          if (mem_bvalid && mem_bready) begin
            req_ready_cnt <= {1'b0, lfsr_val[5:3]};  // 0~7 周期
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
