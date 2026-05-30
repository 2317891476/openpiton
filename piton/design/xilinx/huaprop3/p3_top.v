// p3_top.v — Top-level for HuaPro P3 (Versal VP1902) OpenPiton
// Instantiates:
//   1. Block Design wrapper (openpiton_top) — Clock Wizard, AXI NoC, proc_sys_reset
//   2. openpiton_wrapper — OpenPiton SoC (system.v)
// Connects BD infrastructure outputs to OpenPiton inputs, and routes
// board-level IO (UART, SD, LEDs) directly.

module p3_top (
    // Differential system clock (100 MHz LVDS15)
    input  wire        diff_sysclock_clk_p,
    input  wire        diff_sysclock_clk_n,

    // Differential memory ref clock (100 MHz LVDS15)
    input  wire        diff_memclock_clk_p,
    input  wire        diff_memclock_clk_n,

    // DDR4 SODIMM interface
    output wire [16:0] ddr4_rtl_0_adr,
    output wire [1:0]  ddr4_rtl_0_bg,
    output wire [1:0]  ddr4_rtl_0_ba,
    output wire        ddr4_rtl_0_reset_n,
    output wire        ddr4_rtl_0_act_n,
    output wire [1:0]  ddr4_rtl_0_ck_c,
    output wire [1:0]  ddr4_rtl_0_ck_t,
    output wire [1:0]  ddr4_rtl_0_cke,
    output wire [1:0]  ddr4_rtl_0_cs_n,
    output wire [1:0]  ddr4_rtl_0_odt,
    output wire        ddr4_rtl_0_par,
    inout  wire [71:0] ddr4_rtl_0_dq,
    inout  wire [8:0]  ddr4_rtl_0_dqs_c,
    inout  wire [8:0]  ddr4_rtl_0_dqs_t,
    inout  wire [8:0]  ddr4_rtl_0_dm_n,
    input  wire        ddr4_rtl_0_alert_n,

    // Reset (active-HIGH from P3 push button)
    input  wire        reset,

    // UART
    output wire        uart_tx,
    input  wire        uart_rx,

    // SD Card (SPI mode)
    output wire        sd_clk_out,
    inout  wire        sd_cmd,
    inout  wire [3:0]  sd_dat,
    input  wire        sd_cd,

    // SD Control (P3 daughter card)
    output wire        sd_vsd_en,
    output wire        sd_sel,
    output wire        sd_resetn,

    // LEDs
    output wire [1:0]  leds
);

    // BD infrastructure outputs
    wire chipset_clk;
    wire sd_sys_clk;
    wire peripheral_aresetn;

    // AXI4 signals between OpenPiton and BD (AXI NoC)
    wire [5:0]   m_axi_awid;
    wire [63:0]  m_axi_awaddr;
    wire [7:0]   m_axi_awlen;
    wire [2:0]   m_axi_awsize;
    wire [1:0]   m_axi_awburst;
    wire         m_axi_awlock;
    wire [3:0]   m_axi_awcache;
    wire [2:0]   m_axi_awprot;
    wire [3:0]   m_axi_awqos;
    wire [3:0]   m_axi_awregion;
    wire [10:0]  m_axi_awuser;
    wire         m_axi_awvalid;
    wire         m_axi_awready;

    wire [5:0]   m_axi_wid;
    wire [511:0] m_axi_wdata;
    wire [63:0]  m_axi_wstrb;
    wire         m_axi_wlast;
    wire [10:0]  m_axi_wuser;
    wire         m_axi_wvalid;
    wire         m_axi_wready;

    wire [5:0]   m_axi_arid;
    wire [63:0]  m_axi_araddr;
    wire [7:0]   m_axi_arlen;
    wire [2:0]   m_axi_arsize;
    wire [1:0]   m_axi_arburst;
    wire         m_axi_arlock;
    wire [3:0]   m_axi_arcache;
    wire [2:0]   m_axi_arprot;
    wire [3:0]   m_axi_arqos;
    wire [3:0]   m_axi_arregion;
    wire [10:0]  m_axi_aruser;
    wire         m_axi_arvalid;
    wire         m_axi_arready;

    wire [5:0]   m_axi_rid;
    wire [511:0] m_axi_rdata;
    wire [1:0]   m_axi_rresp;
    wire         m_axi_rlast;
    wire [10:0]  m_axi_ruser;
    wire         m_axi_rvalid;
    wire         m_axi_rready;

    wire [5:0]   m_axi_bid;
    wire [1:0]   m_axi_bresp;
    wire [10:0]  m_axi_buser;
    wire         m_axi_bvalid;
    wire         m_axi_bready;

`ifdef P3_AXI_DDR_ADDR_TRANSLATE
    wire         p3_axi_ddr_awaddr_translate;
    wire         p3_axi_ddr_araddr_translate;
    wire [63:0]  bd_m_axi_awaddr;
    wire [63:0]  bd_m_axi_araddr;

    assign p3_axi_ddr_awaddr_translate = (m_axi_awaddr[63:32] == 32'h0000_0000) &&
                                          m_axi_awaddr[31];
    assign p3_axi_ddr_araddr_translate = (m_axi_araddr[63:32] == 32'h0000_0000) &&
                                          m_axi_araddr[31];
    assign bd_m_axi_awaddr = p3_axi_ddr_awaddr_translate ? {32'h0000_0000, m_axi_awaddr[30:0]} :
                                                              m_axi_awaddr;
    assign bd_m_axi_araddr = p3_axi_ddr_araddr_translate ? {32'h0000_0000, m_axi_araddr[30:0]} :
                                                              m_axi_araddr;
`else
    wire [63:0]  bd_m_axi_awaddr;
    wire [63:0]  bd_m_axi_araddr;

    assign bd_m_axi_awaddr = m_axi_awaddr;
    assign bd_m_axi_araddr = m_axi_araddr;
`endif

    (* keep = "true" *) reg  [31:0]  p3_min_dbg_heartbeat = 32'h0000_0000;
    (* keep = "true" *) wire [31:0]  p3_min_dbg_status;

    always @(posedge chipset_clk) begin
        p3_min_dbg_heartbeat <= p3_min_dbg_heartbeat + 32'h0000_0001;
    end

    assign p3_min_dbg_status = {
        16'h2501,
        reset,
        peripheral_aresetn,
        sd_resetn,
        uart_tx,
        uart_rx,
        sd_cd,
        leds[1:0],
        8'h00
    };

`ifdef P3_RTL_DEBUG
`ifdef P3_BD_SPLIT_DEBUG_ILA
    wire [127:0] p3_debug_bus;
    wire [31:0]  p3_debug_seen;
    wire [31:0]  p3_top_status;
    wire [63:0]  dbg_m_axi_araddr;
    wire [63:0]  dbg_m_axi_awaddr;
`elsif P3_BD_CHIPSET_DEBUG_ILA
    wire [127:0] p3_debug_bus;
    wire [31:0]  p3_debug_seen;
    wire [31:0]  p3_top_status;
    wire [63:0]  dbg_m_axi_araddr;
    wire [63:0]  dbg_m_axi_awaddr;
`elsif P3_BD_UART_DEBUG_ILA
    wire [127:0] p3_debug_bus;
    wire [31:0]  p3_debug_seen;
    wire [31:0]  p3_top_status;
    wire [63:0]  dbg_m_axi_araddr;
    wire [63:0]  dbg_m_axi_awaddr;
`elsif P3_BD_DDR_DEBUG_ILA
    wire [127:0] p3_debug_bus;
    wire [31:0]  p3_debug_seen;
    wire [31:0]  p3_top_status;
    wire [63:0]  dbg_m_axi_araddr;
    wire [63:0]  dbg_m_axi_awaddr;
`elsif P3_BD_BUILD41_DEBUG_ILA
    wire [127:0] p3_debug_bus;
    wire [31:0]  p3_debug_seen;
    wire [31:0]  p3_top_status;
    wire [63:0]  dbg_m_axi_araddr;
    wire [63:0]  dbg_m_axi_awaddr;
`else
    (* keep = "true", mark_debug = "true" *) wire [127:0] p3_debug_bus;
    (* keep = "true", mark_debug = "true" *) wire [31:0]  p3_debug_seen;
    (* keep = "true", mark_debug = "true" *) wire [31:0]  p3_top_status;
    (* keep = "true", mark_debug = "true" *) wire [63:0]  dbg_m_axi_araddr;
    (* keep = "true", mark_debug = "true" *) wire [63:0]  dbg_m_axi_awaddr;
`endif

    assign dbg_m_axi_araddr = m_axi_araddr;
    assign dbg_m_axi_awaddr = m_axi_awaddr;

`ifdef P3_BD_SPLIT_DEBUG_ILA
    (* keep = "true" *) wire        p3_dbg_heartbeat_bit;
    (* keep = "true" *) wire [15:0] p3_dbg_top_status16;
    (* keep = "true" *) wire [14:0] p3_dbg_seen15;
    (* keep = "true" *) wire [31:0] p3_dbg_core_bus32;
    (* keep = "true" *) wire [63:0] p3_dbg_axi_bus64;

    assign p3_dbg_heartbeat_bit = p3_min_dbg_heartbeat[0];
    assign p3_dbg_top_status16  = p3_top_status[15:0];
    assign p3_dbg_seen15        = p3_debug_seen[14:0];
    assign p3_dbg_core_bus32    = {
        p3_debug_bus[39:32],
        p3_debug_bus[23:16],
        p3_debug_bus[15:0]
    };
    assign p3_dbg_axi_bus64     = {
        m_axi_araddr[31:2],
        m_axi_awaddr[31:2],
        m_axi_arvalid,
        m_axi_arready,
        m_axi_awvalid,
        m_axi_awready
    };
`endif
`ifdef P3_BD_CHIPSET_DEBUG_ILA
    (* keep = "true" *) wire        p3_dbg_heartbeat_bit;
    (* keep = "true" *) wire [15:0] p3_dbg_top_status16;
    (* keep = "true" *) wire [15:0] p3_dbg_chipset_seen16;
    (* keep = "true" *) wire [63:0] p3_dbg_chipset_bus64;

    assign p3_dbg_heartbeat_bit    = p3_min_dbg_heartbeat[0];
    assign p3_dbg_top_status16     = p3_top_status[15:0];
    assign p3_dbg_chipset_seen16   = p3_debug_seen[31:16];
    assign p3_dbg_chipset_bus64    = p3_debug_bus[127:64];
`endif
`ifdef P3_BD_UART_DEBUG_ILA
    (* keep = "true" *) wire        p3_dbg_heartbeat_bit;
    (* keep = "true" *) wire [15:0] p3_dbg_top_status16;
    (* keep = "true" *) wire [15:0] p3_dbg_uart_seen16;
    (* keep = "true" *) wire [63:0] p3_dbg_uart_bus64;

    assign p3_dbg_heartbeat_bit = p3_min_dbg_heartbeat[0];
    assign p3_dbg_top_status16  = p3_top_status[15:0];
    assign p3_dbg_uart_seen16   = p3_debug_seen[31:16];
    assign p3_dbg_uart_bus64    = p3_debug_bus[127:64];
`endif
`ifdef P3_BD_DDR_DEBUG_ILA
    (* keep = "true" *) wire        p3_dbg_heartbeat_bit;
    (* keep = "true" *) wire [15:0] p3_dbg_top_status16;
    (* keep = "true" *) wire [15:0] p3_dbg_ddr_seen16;
    (* keep = "true" *) wire [63:0] p3_dbg_ddr_bus64;

    reg [15:0] p3_ddr_seen16_r;
    reg [29:0] p3_ddr_last_addr30_r;
    reg [7:0]  p3_ddr_last_wdata8_r;
    reg [7:0]  p3_ddr_last_rdata8_r;
    reg [1:0]  p3_ddr_last_bresp_r;
    reg [1:0]  p3_ddr_last_rresp_r;

    wire p3_ddr_aw_fire = m_axi_awvalid & m_axi_awready;
    wire p3_ddr_w_fire  = m_axi_wvalid  & m_axi_wready;
    wire p3_ddr_b_fire  = m_axi_bvalid  & m_axi_bready;
    wire p3_ddr_ar_fire = m_axi_arvalid & m_axi_arready;
    wire p3_ddr_r_fire  = m_axi_rvalid  & m_axi_rready;

    always @(posedge chipset_clk or negedge peripheral_aresetn) begin
        if (!peripheral_aresetn) begin
            p3_ddr_seen16_r       <= 16'd0;
            p3_ddr_last_addr30_r  <= 30'd0;
            p3_ddr_last_wdata8_r  <= 8'd0;
            p3_ddr_last_rdata8_r  <= 8'd0;
            p3_ddr_last_bresp_r   <= 2'd0;
            p3_ddr_last_rresp_r   <= 2'd0;
        end else begin
            p3_ddr_seen16_r <= p3_ddr_seen16_r |
                               {m_axi_awready,
                                (p3_ddr_ar_fire & (m_axi_araddr[31:24] == 8'h84)),
                                (p3_ddr_aw_fire & (m_axi_awaddr[31:24] == 8'h84)),
                                (p3_ddr_r_fire & (m_axi_rresp != 2'b00)),
                                p3_ddr_r_fire,
                                m_axi_rvalid,
                                p3_ddr_ar_fire,
                                m_axi_arvalid,
                                (p3_ddr_b_fire & (m_axi_bresp != 2'b00)),
                                p3_ddr_b_fire,
                                m_axi_bvalid,
                                p3_ddr_w_fire,
                                m_axi_wvalid,
                                p3_ddr_aw_fire,
                                m_axi_awvalid,
                                peripheral_aresetn};

            if (p3_ddr_aw_fire) begin
                p3_ddr_last_addr30_r <= bd_m_axi_awaddr[31:2];
            end else if (p3_ddr_ar_fire) begin
                p3_ddr_last_addr30_r <= bd_m_axi_araddr[31:2];
            end
            if (p3_ddr_w_fire) begin
                p3_ddr_last_wdata8_r <= m_axi_wdata[7:0];
            end
            if (p3_ddr_r_fire) begin
                p3_ddr_last_rdata8_r <= m_axi_rdata[7:0];
                p3_ddr_last_rresp_r  <= m_axi_rresp;
            end
            if (p3_ddr_b_fire) begin
                p3_ddr_last_bresp_r <= m_axi_bresp;
            end
        end
    end

    assign p3_dbg_heartbeat_bit = p3_min_dbg_heartbeat[0];
    assign p3_dbg_top_status16  = p3_top_status[15:0];
    assign p3_dbg_ddr_seen16    = p3_ddr_seen16_r;
    assign p3_dbg_ddr_bus64     = {p3_ddr_last_addr30_r,
                                   p3_ddr_last_wdata8_r,
                                   p3_ddr_last_rdata8_r,
                                   p3_ddr_last_bresp_r,
                                   p3_ddr_last_rresp_r,
                                   p3_ddr_seen16_r[13:0]};
`endif
`ifdef P3_BD_SIFIVE_DEBUG_ILA
    (* keep = "true" *) wire [15:0] p3_dbg_chip_seen16;

    assign p3_dbg_chip_seen16 = p3_debug_seen[15:0];
`endif
`ifdef P3_BD_BUILD41_DEBUG_ILA
    (* keep = "true" *) wire        p3_dbg_heartbeat_bit;
    (* keep = "true" *) wire [15:0] p3_dbg_top_status16;
    (* keep = "true" *) wire [15:0] p3_dbg_uart_seen16;
    (* keep = "true" *) wire [15:0] p3_dbg_chip_seen16;
    (* keep = "true" *) wire [63:0] p3_dbg_b41_core_bus64;
    (* keep = "true" *) wire [63:0] p3_dbg_b41_chipset_bus64;

    assign p3_dbg_heartbeat_bit = p3_min_dbg_heartbeat[0];
    assign p3_dbg_top_status16  = p3_top_status[15:0];
    assign p3_dbg_uart_seen16   = p3_debug_seen[31:16]; // Chipset seen
    assign p3_dbg_chip_seen16   = p3_debug_seen[15:0];  // Chip/tile seen
    assign p3_dbg_b41_core_bus64 = p3_debug_bus[63:0];
    assign p3_dbg_b41_chipset_bus64 = p3_debug_bus[127:64];
`endif
`endif

    // =========================================================================
    // Block Design Instance (Clock Wizard + AXI NoC + proc_sys_reset)
    // =========================================================================
    openpiton_top_wrapper u_bd (
        .diff_sysclock_clk_p    (diff_sysclock_clk_p),
        .diff_sysclock_clk_n    (diff_sysclock_clk_n),
        .diff_memclock_clk_p    (diff_memclock_clk_p),
        .diff_memclock_clk_n    (diff_memclock_clk_n),
        .ddr4_rtl_0_adr         (ddr4_rtl_0_adr),
        .ddr4_rtl_0_bg          (ddr4_rtl_0_bg),
        .ddr4_rtl_0_ba          (ddr4_rtl_0_ba),
        .ddr4_rtl_0_reset_n     (ddr4_rtl_0_reset_n),
        .ddr4_rtl_0_act_n       (ddr4_rtl_0_act_n),
        .ddr4_rtl_0_ck_c        (ddr4_rtl_0_ck_c),
        .ddr4_rtl_0_ck_t        (ddr4_rtl_0_ck_t),
        .ddr4_rtl_0_cke         (ddr4_rtl_0_cke),
        .ddr4_rtl_0_cs_n        (ddr4_rtl_0_cs_n),
        .ddr4_rtl_0_odt         (ddr4_rtl_0_odt),
        .ddr4_rtl_0_par         (ddr4_rtl_0_par),
        .ddr4_rtl_0_dq          (ddr4_rtl_0_dq),
        .ddr4_rtl_0_dqs_c       (ddr4_rtl_0_dqs_c),
        .ddr4_rtl_0_dqs_t       (ddr4_rtl_0_dqs_t),
        .ddr4_rtl_0_dm_n        (ddr4_rtl_0_dm_n),
        .ddr4_rtl_0_alert_n     (ddr4_rtl_0_alert_n),
        .reset                  (reset),
        // BD outputs
        .chipset_clk_o          (chipset_clk),
        .sd_sys_clk_o           (sd_sys_clk),
        .peripheral_aresetn_o   (peripheral_aresetn),
        // BD-owned minimal debug ILA inputs
        .p3_dbg_heartbeat_i     (p3_min_dbg_heartbeat),
        .p3_dbg_status_i        (p3_min_dbg_status),
`ifdef P3_BD_RTL_DEBUG_ILA
        .p3_dbg_seen_i          (p3_debug_seen),
        .p3_dbg_top_status_i    (p3_top_status),
        .p3_dbg_bus_i           (p3_debug_bus),
        .p3_dbg_axi_araddr_i    (dbg_m_axi_araddr),
        .p3_dbg_axi_awaddr_i    (dbg_m_axi_awaddr),
`endif
`ifdef P3_BD_SPLIT_DEBUG_ILA
        .p3_dbg_heartbeat_bit_i (p3_dbg_heartbeat_bit),
        .p3_dbg_top_status16_i  (p3_dbg_top_status16),
        .p3_dbg_seen15_i        (p3_dbg_seen15),
        .p3_dbg_core_bus32_i    (p3_dbg_core_bus32),
        .p3_dbg_axi_bus64_i     (p3_dbg_axi_bus64),
`endif
`ifdef P3_BD_CHIPSET_DEBUG_ILA
        .p3_dbg_heartbeat_bit_i (p3_dbg_heartbeat_bit),
        .p3_dbg_top_status16_i  (p3_dbg_top_status16),
        .p3_dbg_chipset_seen16_i(p3_dbg_chipset_seen16),
        .p3_dbg_chipset_bus64_i (p3_dbg_chipset_bus64),
`endif
`ifdef P3_BD_UART_DEBUG_ILA
        .p3_dbg_heartbeat_bit_i (p3_dbg_heartbeat_bit),
        .p3_dbg_top_status16_i  (p3_dbg_top_status16),
        .p3_dbg_uart_seen16_i   (p3_dbg_uart_seen16),
        .p3_dbg_uart_bus64_i    (p3_dbg_uart_bus64),
`endif
`ifdef P3_BD_DDR_DEBUG_ILA
        .p3_dbg_heartbeat_bit_i (p3_dbg_heartbeat_bit),
        .p3_dbg_top_status16_i  (p3_dbg_top_status16),
        .p3_dbg_ddr_seen16_i    (p3_dbg_ddr_seen16),
        .p3_dbg_ddr_bus64_i     (p3_dbg_ddr_bus64),
`endif
`ifdef P3_BD_SIFIVE_DEBUG_ILA
        .p3_dbg_chip_seen16_i   (p3_dbg_chip_seen16),
`endif
`ifdef P3_BD_BUILD41_DEBUG_ILA
        .p3_dbg_heartbeat_bit_i (p3_dbg_heartbeat_bit),
        .p3_dbg_top_status16_i  (p3_dbg_top_status16),
        .p3_dbg_uart_seen16_i   (p3_dbg_uart_seen16),
        .p3_dbg_chip_seen16_i   (p3_dbg_chip_seen16),
        .p3_dbg_b41_core_bus64_i(p3_dbg_b41_core_bus64),
        .p3_dbg_b41_chipset_bus64_i(p3_dbg_b41_chipset_bus64),
`endif
        // AXI4 Slave (from OpenPiton master)
        .S_AXI_MEM_awid         (m_axi_awid),
        .S_AXI_MEM_awaddr       (bd_m_axi_awaddr),
        .S_AXI_MEM_awlen        (m_axi_awlen),
        .S_AXI_MEM_awsize       (m_axi_awsize),
        .S_AXI_MEM_awburst      (m_axi_awburst),
        .S_AXI_MEM_awlock       (m_axi_awlock),
        .S_AXI_MEM_awcache      (m_axi_awcache),
        .S_AXI_MEM_awprot       (m_axi_awprot),
        .S_AXI_MEM_awqos        (m_axi_awqos),
        .S_AXI_MEM_awregion     (m_axi_awregion),
        .S_AXI_MEM_awvalid      (m_axi_awvalid),
        .S_AXI_MEM_awready      (m_axi_awready),
        .S_AXI_MEM_wdata        (m_axi_wdata),
        .S_AXI_MEM_wstrb        (m_axi_wstrb),
        .S_AXI_MEM_wlast        (m_axi_wlast),
        .S_AXI_MEM_wvalid       (m_axi_wvalid),
        .S_AXI_MEM_wready       (m_axi_wready),
        .S_AXI_MEM_arid         (m_axi_arid),
        .S_AXI_MEM_araddr       (bd_m_axi_araddr),
        .S_AXI_MEM_arlen        (m_axi_arlen),
        .S_AXI_MEM_arsize       (m_axi_arsize),
        .S_AXI_MEM_arburst      (m_axi_arburst),
        .S_AXI_MEM_arlock       (m_axi_arlock),
        .S_AXI_MEM_arcache      (m_axi_arcache),
        .S_AXI_MEM_arprot       (m_axi_arprot),
        .S_AXI_MEM_arqos        (m_axi_arqos),
        .S_AXI_MEM_arregion     (m_axi_arregion),
        .S_AXI_MEM_arvalid      (m_axi_arvalid),
        .S_AXI_MEM_arready      (m_axi_arready),
        .S_AXI_MEM_rid          (m_axi_rid),
        .S_AXI_MEM_rdata        (m_axi_rdata),
        .S_AXI_MEM_rresp        (m_axi_rresp),
        .S_AXI_MEM_rlast        (m_axi_rlast),
        .S_AXI_MEM_rvalid       (m_axi_rvalid),
        .S_AXI_MEM_rready       (m_axi_rready),
        .S_AXI_MEM_bid          (m_axi_bid),
        .S_AXI_MEM_bresp        (m_axi_bresp),
        .S_AXI_MEM_bvalid       (m_axi_bvalid),
        .S_AXI_MEM_bready       (m_axi_bready)
    );

    // =========================================================================
    // OpenPiton Wrapper Instance
    // =========================================================================
    openpiton_wrapper u_openpiton (
        .chipset_clk    (chipset_clk),
        .sd_sys_clk     (sd_sys_clk),
        .sys_rst_n      (peripheral_aresetn),
        .ddr_ready      (1'b1),
        // AXI4 Master
        .m_axi_awid     (m_axi_awid),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awlock   (m_axi_awlock),
        .m_axi_awcache  (m_axi_awcache),
        .m_axi_awprot   (m_axi_awprot),
        .m_axi_awqos    (m_axi_awqos),
        .m_axi_awregion (m_axi_awregion),
        .m_axi_awuser   (m_axi_awuser),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wid      (m_axi_wid),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wuser    (m_axi_wuser),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_arid     (m_axi_arid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arlock   (m_axi_arlock),
        .m_axi_arcache  (m_axi_arcache),
        .m_axi_arprot   (m_axi_arprot),
        .m_axi_arqos    (m_axi_arqos),
        .m_axi_arregion (m_axi_arregion),
        .m_axi_aruser   (m_axi_aruser),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_ruser    (m_axi_ruser),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready),
        .m_axi_bid      (m_axi_bid),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_buser    (m_axi_buser),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        // UART
        .uart_tx        (uart_tx),
        .uart_rx        (uart_rx),
        // SD Card
        .sd_clk_out     (sd_clk_out),
        .sd_cmd         (sd_cmd),
        .sd_dat         (sd_dat),
        .sd_cd          (sd_cd),
        .sd_vsd_en      (sd_vsd_en),
        .sd_sel         (sd_sel),
        .sd_resetn      (sd_resetn),
        // LEDs
        .leds           (leds)
`ifdef P3_RTL_DEBUG
        ,
        .p3_debug_bus   (p3_debug_bus),
        .p3_debug_seen  (p3_debug_seen),
        .p3_top_status  (p3_top_status)
`endif
    );

endmodule
