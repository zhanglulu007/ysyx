module UART(
  input clk,
  input rst,

  // ===== AXI4-Lite AR 通道 (读地址) =====
  input         uart_arvalid,
  output        uart_arready,
  input  [31:0] uart_araddr,

  // ===== AXI4-Lite R 通道 (读数据) =====
  output        uart_rvalid,
  input         uart_rready,
  output [31:0] uart_rdata,
  output [ 1:0] uart_rresp,

  // ===== AXI4-Lite AW 通道 (写地址) =====
  input         uart_awvalid,
  output        uart_awready,
  input  [31:0] uart_awaddr,

  // ===== AXI4-Lite W 通道 (写数据) =====
  input         uart_wvalid,
  output        uart_wready,
  input  [31:0] uart_wdata,
  input  [ 3:0] uart_wstrb,

  // ===== AXI4-Lite B 通道 (写回复) =====
  output        uart_bvalid,
  input         uart_bready,
  output [ 1:0] uart_bresp
);

  // DPI-C 函数: 复用 C++ 仿真层的 pmem_read/pmem_write
  // 这两个函数内部已处理设备地址 (SERIAL_PORT 等) 的读写
  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

  // ========== 状态机 ==========
  localparam IDLE   = 2'b00;  // 等待请求
  localparam R_BUSY = 2'b01;  // 读事务: DPI-C 已调用, 等待 R 握手
  localparam W_BUSY = 2'b10;  // 写事务: DPI-C 已调用, 等待 B 握手

  reg [1:0] state;

  // 写通道握手追踪 (AW 和 W 可独立完成)
  reg aw_done;
  reg w_done;
  reg [31:0] latched_awaddr;
  reg [31:0] latched_wdata;
  reg [ 3:0] latched_wstrb;

  // 读数据锁存 (DPI-C 调用后保存)
  reg [31:0] latched_rdata;

  // 读地址锁存 (用于日志输出)
  reg [31:0] logged_araddr;

  // ========== 组合逻辑: 检测 AW/W 是否在本周期完成 ==========
  wire aw_completing = (state == IDLE) && uart_awvalid && uart_awready && !aw_done;
  wire w_completing  = (state == IDLE) && uart_wvalid  && uart_wready  && !w_done;

  // AW/W 是否已就绪 (包括本周期完成)
  wire aw_ready_c = aw_done || aw_completing;
  wire w_ready_c  = w_done  || w_completing;

  // ========== 通道就绪信号 ==========
  assign uart_arready = (state == IDLE) && !rst;
  assign uart_awready = (state == IDLE) && !aw_done && !rst;
  assign uart_wready  = (state == IDLE) && !w_done && !rst;

  // ========== 响应信号 ==========
  assign uart_rvalid = (state == R_BUSY);
  assign uart_rdata  = latched_rdata;
  assign uart_rresp  = 2'b00;         // OKAY

  assign uart_bvalid = (state == W_BUSY);
  assign uart_bresp  = 2'b00;         // OKAY

  // ========== 状态机 ==========
  always @(posedge clk) begin
    if (rst) begin
      state          <= IDLE;
      aw_done        <= 1'b0;
      w_done         <= 1'b0;
      latched_awaddr <= 32'b0;
      latched_wdata  <= 32'b0;
      latched_wstrb  <= 4'b0;
      latched_rdata  <= 32'b0;
      logged_araddr  <= 32'b0;
    end else begin
      case (state)
        IDLE: begin
          // ----- 读事务: AR 握手 -----
          if (uart_arvalid && uart_arready) begin
            // 握手成功, 通过 DPI-C 读取数据
            latched_rdata <= pmem_read(uart_araddr);
            logged_araddr <= uart_araddr;
            state <= R_BUSY;
          end
          // ----- 写事务: AW 和 W 握手追踪 -----
          else begin
            // 当 AW 和 W 均完成 (包括本周期) 时, 调用 DPI-C 写入
            if (aw_ready_c && w_ready_c) begin
              // 先锁存本周期完成的值 (用于日志和 DPI-C 调用)
              if (aw_completing) begin
                latched_awaddr <= uart_awaddr;
              end
              if (w_completing) begin
                latched_wdata <= uart_wdata;
                latched_wstrb <= uart_wstrb;
              end

              // 调用 DPI-C: 使用锁存值或当前值
              if (aw_completing && w_completing) begin
                //$write("[UART] write char='%c' (0x%02x) addr=0x%08x\n",
                 //      uart_wdata[7:0], uart_wdata[7:0], uart_awaddr);
                pmem_write(uart_awaddr, uart_wdata, {4'b0, uart_wstrb});
              end else if (aw_completing) begin
                //$write("[UART] write char='%c' (0x%02x) addr=0x%08x\n",
                 //      latched_wdata[7:0], latched_wdata[7:0], uart_awaddr);
                pmem_write(uart_awaddr, latched_wdata, {4'b0, latched_wstrb});
              end else if (w_completing) begin
                //$write("[UART] write char='%c' (0x%02x) addr=0x%08x\n",
                 //      uart_wdata[7:0], uart_wdata[7:0], latched_awaddr);
                pmem_write(latched_awaddr, uart_wdata, {4'b0, uart_wstrb});
              end else begin
                //$write("[UART] write char='%c' (0x%02x) addr=0x%08x\n",
                 //      latched_wdata[7:0], latched_wdata[7:0], latched_awaddr);
                pmem_write(latched_awaddr, latched_wdata, {4'b0, latched_wstrb});
              end

              state   <= W_BUSY;
              aw_done <= 1'b0;
              w_done  <= 1'b0;
            end else begin
              // 各自独立追踪
              if (aw_completing) begin
                aw_done        <= 1'b1;
                latched_awaddr <= uart_awaddr;
              end

              if (w_completing) begin
                w_done        <= 1'b1;
                latched_wdata <= uart_wdata;
                latched_wstrb <= uart_wstrb;
              end
            end
          end
        end

        R_BUSY: begin
          // R 握手: rvalid && rready
          if (uart_rvalid && uart_rready) begin
            //$write("[UART] read  done  addr=0x%08x data=0x%08x\n", logged_araddr, latched_rdata);
            state <= IDLE;
          end
        end

        W_BUSY: begin
          // B 握手: bvalid && bready
          if (uart_bvalid && uart_bready) begin
            //$write("[UART] write done  addr=0x%08x data=0x%08x strb=%b\n",
             //      latched_awaddr, latched_wdata, latched_wstrb);
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
