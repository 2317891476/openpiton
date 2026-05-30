// p3_uart16550_ila_interact_top.v - Standalone P3 AXI UART16550 interaction test.
//
// This design excludes OpenPiton, Ariane, DDR, SD, and LEDs. It keeps the P3
// clock/reset/debug-hub style and validates the native Xilinx axi_uart16550 IP
// with an ideal AXI-Lite master.

module p3_uart16550_ila_interact_top (
    input  wire diff_sysclock_clk_p,
    input  wire diff_sysclock_clk_n,
    input  wire reset,
    output wire uart_tx,
    input  wire uart_rx
);
    wire        uart_clk;
    wire        uart_aresetn;
    wire [15:0] p3_uart_status;
    wire [63:0] p3_uart_txn;
    wire [31:0] p3_uart_counts;
    wire        p3_uart_rx_level;
    wire        p3_uart_rx_falling_seen;

    assign p3_uart_rx_level = p3_uart_status[14];
    assign p3_uart_rx_falling_seen = p3_uart_status[6];

    p3_uart16550_dbg_bd_wrapper u_bd (
        .diff_sysclock_clk_p (diff_sysclock_clk_p),
        .diff_sysclock_clk_n (diff_sysclock_clk_n),
        .reset               (reset),
        .uart_clk_o          (uart_clk),
        .uart_aresetn_o      (uart_aresetn),
        .p3_uart_status_i    (p3_uart_status),
        .p3_uart_txn_i       (p3_uart_txn),
        .p3_uart_counts_i    (p3_uart_counts),
        .p3_uart_rx_level_i  (p3_uart_rx_level),
        .p3_uart_rx_fall_i   (p3_uart_rx_falling_seen)
    );

    p3_uart16550_axi_interact u_uart_test (
        .clk        (uart_clk),
        .rst_n      (uart_aresetn),
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx),
        .dbg_status (p3_uart_status),
        .dbg_txn    (p3_uart_txn),
        .dbg_counts (p3_uart_counts)
    );
endmodule

module p3_uart16550_axi_interact (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire [15:0] dbg_status,
    output wire [63:0] dbg_txn,
    output wire [31:0] dbg_counts
);
    localparam [3:0] UART_REG_RBR_THR_DLL = 4'd0;
    localparam [3:0] UART_REG_IER_DLM     = 4'd1;
    localparam [3:0] UART_REG_FCR_IIR     = 4'd2;
    localparam [3:0] UART_REG_LCR         = 4'd3;
    localparam [3:0] UART_REG_MCR         = 4'd4;
    localparam [3:0] UART_REG_LSR         = 4'd5;

    localparam [7:0] C_INIT_START    = 8'd0;
    localparam [7:0] C_INIT_WAIT     = 8'd1;
    localparam [7:0] C_BANNER_LSR    = 8'd2;
    localparam [7:0] C_BANNER_LSR_W  = 8'd3;
    localparam [7:0] C_BANNER_TX     = 8'd4;
    localparam [7:0] C_BANNER_TX_W   = 8'd5;
    localparam [7:0] C_ECHO_LSR      = 8'd6;
    localparam [7:0] C_ECHO_LSR_W    = 8'd7;
    localparam [7:0] C_ECHO_RBR      = 8'd8;
    localparam [7:0] C_ECHO_RBR_W    = 8'd9;
    localparam [7:0] C_ECHO_TX_LSR   = 8'd10;
    localparam [7:0] C_ECHO_TX_LSR_W = 8'd11;
    localparam [7:0] C_ECHO_TX       = 8'd12;
    localparam [7:0] C_ECHO_TX_W     = 8'd13;

    function [12:0] uart_addr;
        input [3:0] reg_index;
        begin
            uart_addr = 13'h1000 | {7'd0, reg_index, 2'b00};
        end
    endfunction

    function [7:0] uart_addr_low;
        input [3:0] reg_index;
        begin
            uart_addr_low = {2'b00, reg_index, 2'b00};
        end
    endfunction

    function [7:0] banner_byte;
        input [4:0] index;
        begin
            case (index)
                5'd0:  banner_byte = "A";
                5'd1:  banner_byte = "X";
                5'd2:  banner_byte = "I";
                5'd3:  banner_byte = "1";
                5'd4:  banner_byte = "6";
                5'd5:  banner_byte = "5";
                5'd6:  banner_byte = "5";
                5'd7:  banner_byte = "0";
                5'd8:  banner_byte = " ";
                5'd9:  banner_byte = "R";
                5'd10: banner_byte = "E";
                5'd11: banner_byte = "A";
                5'd12: banner_byte = "D";
                5'd13: banner_byte = "Y";
                5'd14: banner_byte = 8'h0d;
                5'd15: banner_byte = 8'h0a;
                default: banner_byte = 8'h0a;
            endcase
        end
    endfunction

    function [3:0] init_reg;
        input [3:0] step;
        begin
            case (step)
                4'd0: init_reg = UART_REG_IER_DLM;
                4'd1: init_reg = UART_REG_LCR;
                4'd2: init_reg = UART_REG_RBR_THR_DLL;
                4'd3: init_reg = UART_REG_IER_DLM;
                4'd4: init_reg = UART_REG_FCR_IIR;
                4'd5: init_reg = UART_REG_LCR;
                4'd6: init_reg = UART_REG_MCR;
                default: init_reg = UART_REG_MCR;
            endcase
        end
    endfunction

    function [7:0] init_data;
        input [3:0] step;
        begin
            case (step)
                4'd0: init_data = 8'h00; // IER: disable interrupts
                4'd1: init_data = 8'h80; // LCR: DLAB=1
                4'd2: init_data = 8'd16; // DLL: 30 MHz / (16 * 115200)
                4'd3: init_data = 8'h00; // DLM
                4'd4: init_data = 8'h07; // FCR: enable and clear FIFOs
                4'd5: init_data = 8'h03; // LCR: 8N1, DLAB=0
                4'd6: init_data = 8'h00; // MCR: no autoflow
                default: init_data = 8'h00;
            endcase
        end
    endfunction

    reg  [12:0] s_axi_awaddr_r;
    reg         s_axi_awvalid_r;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata_r;
    wire [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid_r;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready_r;
    reg  [12:0] s_axi_araddr_r;
    reg         s_axi_arvalid_r;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready_r;
    wire        uart_interrupt;

    assign s_axi_wstrb = 4'b0001;

    uart_16550 u_uart16550 (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rst_n),
        .ip2intc_irpt  (uart_interrupt),
        .freeze        (1'b0),
        .s_axi_awaddr  (s_axi_awaddr_r),
        .s_axi_awvalid (s_axi_awvalid_r),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata_r),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid_r),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready_r),
        .s_axi_araddr  (s_axi_araddr_r),
        .s_axi_arvalid (s_axi_arvalid_r),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready_r),
        .baudoutn      (),
        .ctsn          (1'b0),
        .dcdn          (1'b0),
        .ddis          (),
        .dsrn          (1'b0),
        .dtrn          (),
        .out1n         (),
        .out2n         (),
        .rin           (1'b0),
        .rtsn          (),
        .rxrdyn        (),
        .sin           (uart_rx),
        .sout          (uart_tx),
        .txrdyn        ()
    );

    wire aw_fire = s_axi_awvalid_r & s_axi_awready;
    wire w_fire  = s_axi_wvalid_r  & s_axi_wready;
    wire b_fire  = s_axi_bvalid    & s_axi_bready_r;
    wire ar_fire = s_axi_arvalid_r & s_axi_arready;
    wire r_fire  = s_axi_rvalid    & s_axi_rready_r;

    reg        op_start;
    reg        op_write;
    reg [12:0] op_addr;
    reg [7:0]  op_wdata;
    reg        op_busy;
    reg        op_done;
    reg        op_write_q;
    reg        aw_done;
    reg        w_done;
    reg [31:0] op_rdata;

    reg [7:0]  ctrl_state;
    reg [3:0]  init_step;
    reg [4:0]  banner_index;
    reg [7:0]  rx_byte;
    reg [7:0]  last_addr_low;
    reg [7:0]  last_wdata;
    reg [7:0]  last_rdata;
    reg [7:0]  last_lsr;
    reg [7:0]  last_rx_byte;
    reg [15:0] tx_count;
    reg [15:0] rx_count;

    reg rst_seen;
    reg init_done;
    reg banner_done;
    reg tx_write_seen;
    reg rx_read_seen;
    reg rx_byte_seen;
    reg rx_falling_seen;
    reg tx_low_seen;
    reg tx_transition_seen;
    reg axi_b_error;
    reg axi_r_error;
    reg lsr_dr_seen;
    reg lsr_thre_seen;
    reg aw_fire_seen;
    reg w_fire_seen;
    reg b_fire_seen;
    reg ar_fire_seen;
    reg r_fire_seen;
    reg uart_rx_meta;
    reg uart_rx_sync;
    reg uart_rx_q;
    reg uart_tx_q;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            s_axi_awaddr_r  <= 13'd0;
            s_axi_awvalid_r <= 1'b0;
            s_axi_wdata_r   <= 32'd0;
            s_axi_wvalid_r  <= 1'b0;
            s_axi_bready_r  <= 1'b0;
            s_axi_araddr_r  <= 13'd0;
            s_axi_arvalid_r <= 1'b0;
            s_axi_rready_r  <= 1'b0;
            op_busy         <= 1'b0;
            op_done         <= 1'b0;
            op_write_q      <= 1'b0;
            aw_done         <= 1'b0;
            w_done          <= 1'b0;
            op_rdata        <= 32'd0;
            axi_b_error     <= 1'b0;
            axi_r_error     <= 1'b0;
            aw_fire_seen    <= 1'b0;
            w_fire_seen     <= 1'b0;
            b_fire_seen     <= 1'b0;
            ar_fire_seen    <= 1'b0;
            r_fire_seen     <= 1'b0;
        end
        else
        begin
            op_done <= 1'b0;
            if (aw_fire) aw_fire_seen <= 1'b1;
            if (w_fire)  w_fire_seen  <= 1'b1;
            if (b_fire)  b_fire_seen  <= 1'b1;
            if (ar_fire) ar_fire_seen <= 1'b1;
            if (r_fire)  r_fire_seen  <= 1'b1;

            if (!op_busy && op_start)
            begin
                op_busy    <= 1'b1;
                op_write_q <= op_write;
                aw_done    <= 1'b0;
                w_done     <= 1'b0;
                if (op_write)
                begin
                    s_axi_awaddr_r  <= op_addr;
                    s_axi_wdata_r   <= {24'd0, op_wdata};
                    s_axi_awvalid_r <= 1'b1;
                    s_axi_wvalid_r  <= 1'b1;
                    s_axi_bready_r  <= 1'b0;
                end
                else
                begin
                    s_axi_araddr_r  <= op_addr;
                    s_axi_arvalid_r <= 1'b1;
                    s_axi_rready_r  <= 1'b0;
                end
            end
            else if (op_busy && op_write_q)
            begin
                if (aw_fire)
                begin
                    s_axi_awvalid_r <= 1'b0;
                    aw_done <= 1'b1;
                end
                if (w_fire)
                begin
                    s_axi_wvalid_r <= 1'b0;
                    w_done <= 1'b1;
                end
                if ((aw_done || aw_fire) && (w_done || w_fire))
                begin
                    s_axi_bready_r <= 1'b1;
                end
                if (b_fire)
                begin
                    s_axi_bready_r <= 1'b0;
                    op_busy <= 1'b0;
                    op_done <= 1'b1;
                    if (s_axi_bresp != 2'b00)
                    begin
                        axi_b_error <= 1'b1;
                    end
                end
            end
            else if (op_busy)
            begin
                if (ar_fire)
                begin
                    s_axi_arvalid_r <= 1'b0;
                    s_axi_rready_r <= 1'b1;
                end
                if (r_fire)
                begin
                    s_axi_rready_r <= 1'b0;
                    op_rdata <= s_axi_rdata;
                    op_busy <= 1'b0;
                    op_done <= 1'b1;
                    if (s_axi_rresp != 2'b00)
                    begin
                        axi_r_error <= 1'b1;
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            op_start          <= 1'b0;
            op_write          <= 1'b0;
            op_addr           <= 13'd0;
            op_wdata          <= 8'd0;
            ctrl_state        <= C_INIT_START;
            init_step         <= 4'd0;
            banner_index      <= 5'd0;
            rx_byte           <= 8'd0;
            last_addr_low     <= 8'd0;
            last_wdata        <= 8'd0;
            last_rdata        <= 8'd0;
            last_lsr          <= 8'd0;
            last_rx_byte      <= 8'd0;
            tx_count          <= 16'd0;
            rx_count          <= 16'd0;
            rst_seen          <= 1'b0;
            init_done         <= 1'b0;
            banner_done       <= 1'b0;
            tx_write_seen     <= 1'b0;
            rx_read_seen      <= 1'b0;
            rx_byte_seen      <= 1'b0;
            rx_falling_seen   <= 1'b0;
            tx_low_seen       <= 1'b0;
            tx_transition_seen <= 1'b0;
            lsr_dr_seen       <= 1'b0;
            lsr_thre_seen     <= 1'b0;
            uart_rx_meta      <= 1'b1;
            uart_rx_sync      <= 1'b1;
            uart_rx_q         <= 1'b1;
            uart_tx_q         <= 1'b1;
        end
        else
        begin
            op_start <= 1'b0;
            rst_seen <= 1'b1;

            uart_rx_meta <= uart_rx;
            uart_rx_sync <= uart_rx_meta;
            uart_rx_q <= uart_rx_sync;
            uart_tx_q <= uart_tx;

            if (uart_rx_q && !uart_rx_sync)
            begin
                rx_falling_seen <= 1'b1;
            end
            if (!uart_tx)
            begin
                tx_low_seen <= 1'b1;
            end
            if (uart_tx_q ^ uart_tx)
            begin
                tx_transition_seen <= 1'b1;
            end

            case (ctrl_state)
                C_INIT_START:
                begin
                    if (!op_busy)
                    begin
                        op_write <= 1'b1;
                        op_addr <= uart_addr(init_reg(init_step));
                        op_wdata <= init_data(init_step);
                        last_addr_low <= uart_addr_low(init_reg(init_step));
                        last_wdata <= init_data(init_step);
                        op_start <= 1'b1;
                        ctrl_state <= C_INIT_WAIT;
                    end
                end
                C_INIT_WAIT:
                begin
                    if (op_done)
                    begin
                        if (init_step == 4'd6)
                        begin
                            init_done <= 1'b1;
                            banner_index <= 5'd0;
                            ctrl_state <= C_BANNER_LSR;
                        end
                        else
                        begin
                            init_step <= init_step + 1'b1;
                            ctrl_state <= C_INIT_START;
                        end
                    end
                end
                C_BANNER_LSR:
                begin
                    if (!op_busy)
                    begin
                        op_write <= 1'b0;
                        op_addr <= uart_addr(UART_REG_LSR);
                        last_addr_low <= uart_addr_low(UART_REG_LSR);
                        op_start <= 1'b1;
                        ctrl_state <= C_BANNER_LSR_W;
                    end
                end
                C_BANNER_LSR_W:
                begin
                    if (op_done)
                    begin
                        last_rdata <= op_rdata[7:0];
                        last_lsr <= op_rdata[7:0];
                        if (op_rdata[0]) lsr_dr_seen <= 1'b1;
                        if (op_rdata[5]) lsr_thre_seen <= 1'b1;
                        ctrl_state <= op_rdata[5] ? C_BANNER_TX : C_BANNER_LSR;
                    end
                end
                C_BANNER_TX:
                begin
                    if (!op_busy)
                    begin
                        op_write <= 1'b1;
                        op_addr <= uart_addr(UART_REG_RBR_THR_DLL);
                        op_wdata <= banner_byte(banner_index);
                        last_addr_low <= uart_addr_low(UART_REG_RBR_THR_DLL);
                        last_wdata <= banner_byte(banner_index);
                        op_start <= 1'b1;
                        ctrl_state <= C_BANNER_TX_W;
                    end
                end
                C_BANNER_TX_W:
                begin
                    if (op_done)
                    begin
                        tx_write_seen <= 1'b1;
                        tx_count <= tx_count + 1'b1;
                        if (banner_index == 5'd15)
                        begin
                            banner_done <= 1'b1;
                            ctrl_state <= C_ECHO_LSR;
                        end
                        else
                        begin
                            banner_index <= banner_index + 1'b1;
                            ctrl_state <= C_BANNER_LSR;
                        end
                    end
                end
                C_ECHO_LSR:
                begin
                    if (!op_busy)
                    begin
                        op_write <= 1'b0;
                        op_addr <= uart_addr(UART_REG_LSR);
                        last_addr_low <= uart_addr_low(UART_REG_LSR);
                        op_start <= 1'b1;
                        ctrl_state <= C_ECHO_LSR_W;
                    end
                end
                C_ECHO_LSR_W:
                begin
                    if (op_done)
                    begin
                        last_rdata <= op_rdata[7:0];
                        last_lsr <= op_rdata[7:0];
                        if (op_rdata[0]) lsr_dr_seen <= 1'b1;
                        if (op_rdata[5]) lsr_thre_seen <= 1'b1;
                        ctrl_state <= op_rdata[0] ? C_ECHO_RBR : C_ECHO_LSR;
                    end
                end
                C_ECHO_RBR:
                begin
                    if (!op_busy)
                    begin
                        op_write <= 1'b0;
                        op_addr <= uart_addr(UART_REG_RBR_THR_DLL);
                        last_addr_low <= uart_addr_low(UART_REG_RBR_THR_DLL);
                        op_start <= 1'b1;
                        ctrl_state <= C_ECHO_RBR_W;
                    end
                end
                C_ECHO_RBR_W:
                begin
                    if (op_done)
                    begin
                        rx_byte <= op_rdata[7:0];
                        last_rdata <= op_rdata[7:0];
                        last_rx_byte <= op_rdata[7:0];
                        rx_count <= rx_count + 1'b1;
                        rx_read_seen <= 1'b1;
                        rx_byte_seen <= 1'b1;
                        ctrl_state <= C_ECHO_TX_LSR;
                    end
                end
                C_ECHO_TX_LSR:
                begin
                    if (!op_busy)
                    begin
                        op_write <= 1'b0;
                        op_addr <= uart_addr(UART_REG_LSR);
                        last_addr_low <= uart_addr_low(UART_REG_LSR);
                        op_start <= 1'b1;
                        ctrl_state <= C_ECHO_TX_LSR_W;
                    end
                end
                C_ECHO_TX_LSR_W:
                begin
                    if (op_done)
                    begin
                        last_rdata <= op_rdata[7:0];
                        last_lsr <= op_rdata[7:0];
                        if (op_rdata[0]) lsr_dr_seen <= 1'b1;
                        if (op_rdata[5]) lsr_thre_seen <= 1'b1;
                        ctrl_state <= op_rdata[5] ? C_ECHO_TX : C_ECHO_TX_LSR;
                    end
                end
                C_ECHO_TX:
                begin
                    if (!op_busy)
                    begin
                        op_write <= 1'b1;
                        op_addr <= uart_addr(UART_REG_RBR_THR_DLL);
                        op_wdata <= rx_byte;
                        last_addr_low <= uart_addr_low(UART_REG_RBR_THR_DLL);
                        last_wdata <= rx_byte;
                        op_start <= 1'b1;
                        ctrl_state <= C_ECHO_TX_W;
                    end
                end
                C_ECHO_TX_W:
                begin
                    if (op_done)
                    begin
                        tx_write_seen <= 1'b1;
                        tx_count <= tx_count + 1'b1;
                        ctrl_state <= C_ECHO_LSR;
                    end
                end
                default:
                begin
                    ctrl_state <= C_INIT_START;
                end
            endcase
        end
    end

    wire [15:0] dbg_flags = {aw_fire_seen,
                             w_fire_seen,
                             b_fire_seen,
                             ar_fire_seen,
                             r_fire_seen,
                             aw_fire,
                             w_fire,
                             b_fire,
                             ar_fire,
                             r_fire,
                             op_write_q,
                             op_busy,
                             s_axi_bvalid,
                             s_axi_rvalid,
                             uart_rx_sync,
                             uart_tx};

    assign dbg_status = {uart_tx,
                         uart_rx_sync,
                         op_busy,
                         lsr_thre_seen,
                         lsr_dr_seen,
                         axi_r_error,
                         axi_b_error,
                         tx_transition_seen,
                         tx_low_seen,
                         rx_falling_seen,
                         rx_byte_seen,
                         rx_read_seen,
                         tx_write_seen,
                         banner_done,
                         init_done,
                         rst_seen};

    assign dbg_txn = {ctrl_state,
                      last_addr_low,
                      last_wdata,
                      last_rdata,
                      last_lsr,
                      last_rx_byte,
                      dbg_flags};

    assign dbg_counts = {tx_count, rx_count};
endmodule
