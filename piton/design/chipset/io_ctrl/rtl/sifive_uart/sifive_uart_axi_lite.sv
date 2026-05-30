// AXI4-Lite wrapper for the SiFive/Chipyard TLUART.
//
// The generated TLUART is a 64-bit TileLink-UL register router. OpenPiton's
// UART path presents 32-bit AXI4-Lite accesses, so this bridge maps each AXI
// word to the low or high half of a 64-bit TL beat.

module sifive_uart_axi_lite (
    input         s_axi_aclk,
    input         s_axi_aresetn,
    output        ip2intc_irpt,

    input  [12:0] s_axi_awaddr,
    input         s_axi_awvalid,
    output        s_axi_awready,

    input  [31:0] s_axi_wdata,
    input  [3:0]  s_axi_wstrb,
    input         s_axi_wvalid,
    output        s_axi_wready,

    output [1:0]  s_axi_bresp,
    output reg    s_axi_bvalid,
    input         s_axi_bready,

    input  [12:0] s_axi_araddr,
    input         s_axi_arvalid,
    output        s_axi_arready,

    output reg [31:0] s_axi_rdata,
    output [1:0]  s_axi_rresp,
    output reg    s_axi_rvalid,
    input         s_axi_rready,

    input         uart_rx,
    output        uart_tx
`ifdef P3_SIFIVE_UART_DEBUG_ILA
    ,
    output [63:0] p3_sifive_debug_bus,
    output [15:0] p3_sifive_debug_seen
`endif
);

    localparam [2:0] TL_OP_PUTFULL    = 3'h0;
    localparam [2:0] TL_OP_PUTPARTIAL = 3'h1;
    localparam [2:0] TL_OP_GET        = 3'h4;

    reg        aw_pending;
    reg [12:0] awaddr_q;
    reg        w_pending;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;
    reg        ar_pending;
    reg [12:0] araddr_q;

    wire bridge_reset = ~s_axi_aresetn;
    wire tl_reset = ~s_axi_aresetn;

    wire can_accept_write_addr = s_axi_aresetn & ~aw_pending & ~s_axi_bvalid & ~s_axi_rvalid;
    wire can_accept_write_data = s_axi_aresetn & ~w_pending  & ~s_axi_bvalid & ~s_axi_rvalid;
    wire can_accept_read_addr  = s_axi_aresetn & ~ar_pending & ~aw_pending & ~w_pending &
                                 ~s_axi_bvalid & ~s_axi_rvalid;

    assign s_axi_awready = can_accept_write_addr;
    assign s_axi_wready  = can_accept_write_data;
    assign s_axi_arready = can_accept_read_addr;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_rresp   = 2'b00;

    wire do_write = aw_pending & w_pending & ~s_axi_bvalid & ~s_axi_rvalid;
    wire do_read  = ar_pending & ~do_write & ~s_axi_bvalid & ~s_axi_rvalid;
    wire tl_a_valid = do_write | do_read;

    wire [12:0] active_addr = do_write ? awaddr_q : araddr_q;
    wire        active_hi32 = active_addr[2];
    wire [7:0]  write_mask  = active_hi32 ? {wstrb_q, 4'h0} : {4'h0, wstrb_q};
    wire [63:0] write_data  = active_hi32 ? {wdata_q, 32'h0} : {32'h0, wdata_q};
    wire [7:0]  read_mask   = active_hi32 ? 8'hf0 : 8'h0f;

    wire        tl_a_ready;
    wire        tl_d_valid;
    wire [2:0]  tl_d_opcode;
    wire [1:0]  tl_d_size;
    wire [7:0]  tl_d_source;
    wire [63:0] tl_d_data;

    TLUART u_tluart (
        .clock                               (s_axi_aclk),
        .reset                               (tl_reset),
        .auto_int_xing_out_sync_0            (ip2intc_irpt),
        .auto_control_xing_in_a_ready        (tl_a_ready),
        .auto_control_xing_in_a_valid        (tl_a_valid),
        .auto_control_xing_in_a_bits_opcode  (do_read ? TL_OP_GET :
                                               (wstrb_q == 4'hf ? TL_OP_PUTFULL : TL_OP_PUTPARTIAL)),
        .auto_control_xing_in_a_bits_size    (2'h2),
        .auto_control_xing_in_a_bits_source  (8'h00),
        .auto_control_xing_in_a_bits_address ({18'h0, active_addr[12:3], 3'b000}),
        .auto_control_xing_in_a_bits_mask    (do_read ? read_mask : write_mask),
        .auto_control_xing_in_a_bits_data    (write_data),
        .auto_control_xing_in_d_ready        (tl_a_valid),
        .auto_control_xing_in_d_valid        (tl_d_valid),
        .auto_control_xing_in_d_bits_opcode  (tl_d_opcode),
        .auto_control_xing_in_d_bits_size    (tl_d_size),
        .auto_control_xing_in_d_bits_source  (tl_d_source),
        .auto_control_xing_in_d_bits_data    (tl_d_data),
        .auto_io_out_txd                     (uart_tx),
        .auto_io_out_rxd                     (uart_rx)
    );

    wire tl_fire = tl_a_valid & tl_a_ready & tl_d_valid;

`ifdef P3_SIFIVE_UART_DEBUG_ILA
    reg [15:0] debug_seen_r;
    reg [7:0]  debug_last_addr_r;
    reg [7:0]  debug_last_wdata_r;
    reg [7:0]  debug_last_rdata_r;
    reg [3:0]  debug_last_wstrb_r;
    reg        debug_uart_tx_q;
    reg        debug_uart_tx_low_seen_r;
    reg        debug_uart_tx_transition_seen_r;

    wire s_axi_aw_fire = s_axi_awvalid & s_axi_awready;
    wire s_axi_w_fire  = s_axi_wvalid  & s_axi_wready;
    wire s_axi_ar_fire = s_axi_arvalid & s_axi_arready;
    wire s_axi_b_fire  = s_axi_bvalid  & s_axi_bready;
    wire s_axi_r_fire  = s_axi_rvalid  & s_axi_rready;
    wire tl_write_fire = tl_fire & do_write;
    wire tl_read_fire  = tl_fire & do_read;

    always @(posedge s_axi_aclk) begin
        if (bridge_reset) begin
            debug_seen_r                    <= 16'd0;
            debug_last_addr_r               <= 8'd0;
            debug_last_wdata_r              <= 8'd0;
            debug_last_rdata_r              <= 8'd0;
            debug_last_wstrb_r              <= 4'd0;
            debug_uart_tx_q                 <= 1'b1;
            debug_uart_tx_low_seen_r        <= 1'b0;
            debug_uart_tx_transition_seen_r <= 1'b0;
        end else begin
            debug_uart_tx_q <= uart_tx;
            debug_seen_r <= debug_seen_r |
                            {ip2intc_irpt,
                             (tl_write_fire & (active_addr[5:0] == 6'h18)),
                             (tl_write_fire & (active_addr[5:0] == 6'h08)),
                             (tl_write_fire & (active_addr[5:0] == 6'h00)),
                             (debug_uart_tx_q ^ uart_tx),
                             ~uart_tx,
                             s_axi_r_fire,
                             s_axi_b_fire,
                             tl_read_fire,
                             tl_write_fire,
                             tl_d_valid,
                             tl_a_ready,
                             tl_a_valid,
                             s_axi_ar_fire,
                             s_axi_w_fire,
                             s_axi_aw_fire};

            if (s_axi_aw_fire) begin
                debug_last_addr_r <= s_axi_awaddr[7:0];
            end else if (s_axi_ar_fire) begin
                debug_last_addr_r <= s_axi_araddr[7:0];
            end

            if (s_axi_w_fire) begin
                debug_last_wdata_r <= s_axi_wdata[7:0];
                debug_last_wstrb_r <= s_axi_wstrb;
            end

            if (tl_fire & do_read) begin
                debug_last_rdata_r <= active_hi32 ? tl_d_data[39:32] : tl_d_data[7:0];
            end

            if (~uart_tx) begin
                debug_uart_tx_low_seen_r <= 1'b1;
            end
            if (debug_uart_tx_q ^ uart_tx) begin
                debug_uart_tx_transition_seen_r <= 1'b1;
            end
        end
    end

    assign p3_sifive_debug_seen = debug_seen_r;
    assign p3_sifive_debug_bus = {debug_last_addr_r,
                                  debug_last_wdata_r,
                                  debug_last_rdata_r,
                                  debug_last_wstrb_r,
                                  aw_pending,
                                  w_pending,
                                  ar_pending,
                                  s_axi_bvalid,
                                  s_axi_rvalid,
                                  tl_a_valid,
                                  tl_a_ready,
                                  tl_d_valid,
                                  uart_tx,
                                  debug_uart_tx_low_seen_r,
                                  debug_uart_tx_transition_seen_r,
                                  ip2intc_irpt,
                                  24'd0};
`endif

    always @(posedge s_axi_aclk) begin
        if (bridge_reset) begin
            aw_pending   <= 1'b0;
            awaddr_q     <= 13'd0;
            w_pending    <= 1'b0;
            wdata_q      <= 32'd0;
            wstrb_q      <= 4'd0;
            ar_pending   <= 1'b0;
            araddr_q     <= 13'd0;
            s_axi_bvalid <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
        end else begin
            if (s_axi_awvalid & s_axi_awready) begin
                aw_pending <= 1'b1;
                awaddr_q   <= s_axi_awaddr;
            end

            if (s_axi_wvalid & s_axi_wready) begin
                w_pending <= 1'b1;
                wdata_q   <= s_axi_wdata;
                wstrb_q   <= s_axi_wstrb;
            end

            if (s_axi_arvalid & s_axi_arready) begin
                ar_pending <= 1'b1;
                araddr_q   <= s_axi_araddr;
            end

            if (tl_fire & do_write) begin
                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bvalid & s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (tl_fire & do_read) begin
                ar_pending  <= 1'b0;
                s_axi_rdata <= active_hi32 ? tl_d_data[63:32] : tl_d_data[31:0];
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid & s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
