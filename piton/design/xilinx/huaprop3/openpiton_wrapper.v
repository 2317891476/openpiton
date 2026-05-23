// OpenPiton BD Wrapper for HuaPro P3 (Versal VP1902)
// Instantiates system.v with the port subset active for HUAPROP3_BOARD:
//   - External clocks (PITON_CHIPSET_CLKS_GEN undefined)
//   - AXI4 memory interface (PITONSYS_AXI4_MEM)
//   - SD card with extra control signals
//   - UART, LEDs
//   - No JTAG, no Ethernet, no OLED, no passthru
//
// All port widths are hardcoded to match noc_axi4_bridge_define.vh:
//   AXI4_DATA_WIDTH=512, AXI4_ADDR_WIDTH=64, AXI4_ID_WIDTH=6,
//   AXI4_STRB_WIDTH=64, AXI4_USER_WIDTH=11

module openpiton_wrapper (
    // Clocks from Block Design Clock Wizard
    input  wire        chipset_clk,
    input  wire        sd_sys_clk,

    // Reset (active-HIGH from board, matching PITON_FPGA_RST_ACT_HIGH)
    input  wire        sys_rst_n,

    // DDR ready from AXI NoC (init_calib_complete equivalent)
    input  wire        ddr_ready,

    // AXI4 Master to DDR (512-bit data, 64-bit addr, 6-bit ID)
    output wire [5:0]  m_axi_awid,
    output wire [63:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awlock,
    output wire [3:0]  m_axi_awcache,
    output wire [2:0]  m_axi_awprot,
    output wire [3:0]  m_axi_awqos,
    output wire [3:0]  m_axi_awregion,
    output wire [10:0] m_axi_awuser,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,

    output wire [5:0]  m_axi_wid,
    output wire [511:0] m_axi_wdata,
    output wire [63:0] m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire [10:0] m_axi_wuser,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,

    output wire [5:0]  m_axi_arid,
    output wire [63:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arlock,
    output wire [3:0]  m_axi_arcache,
    output wire [2:0]  m_axi_arprot,
    output wire [3:0]  m_axi_arqos,
    output wire [3:0]  m_axi_arregion,
    output wire [10:0] m_axi_aruser,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,

    input  wire [5:0]  m_axi_rid,
    input  wire [511:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire [10:0] m_axi_ruser,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,

    input  wire [5:0]  m_axi_bid,
    input  wire [1:0]  m_axi_bresp,
    input  wire [10:0] m_axi_buser,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,

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
    output wire [3:0]  leds
);

system system_inst (
    // Clocks (PITON_CHIPSET_CLKS_GEN undefined path)
    .chipset_clk        (chipset_clk),
    .mc_clk             (chipset_clk),
    .sd_sys_clk         (sd_sys_clk),

    // Reset
    .sys_rst_n          (sys_rst_n),

    // DDR ready
    .ddr_ready          (ddr_ready),

    // AXI4 Write Address
    .m_axi_awid         (m_axi_awid),
    .m_axi_awaddr       (m_axi_awaddr),
    .m_axi_awlen        (m_axi_awlen),
    .m_axi_awsize       (m_axi_awsize),
    .m_axi_awburst      (m_axi_awburst),
    .m_axi_awlock       (m_axi_awlock),
    .m_axi_awcache      (m_axi_awcache),
    .m_axi_awprot       (m_axi_awprot),
    .m_axi_awqos        (m_axi_awqos),
    .m_axi_awregion     (m_axi_awregion),
    .m_axi_awuser       (m_axi_awuser),
    .m_axi_awvalid      (m_axi_awvalid),
    .m_axi_awready      (m_axi_awready),

    // AXI4 Write Data
    .m_axi_wid          (m_axi_wid),
    .m_axi_wdata        (m_axi_wdata),
    .m_axi_wstrb        (m_axi_wstrb),
    .m_axi_wlast        (m_axi_wlast),
    .m_axi_wuser        (m_axi_wuser),
    .m_axi_wvalid       (m_axi_wvalid),
    .m_axi_wready       (m_axi_wready),

    // AXI4 Read Address
    .m_axi_arid         (m_axi_arid),
    .m_axi_araddr       (m_axi_araddr),
    .m_axi_arlen        (m_axi_arlen),
    .m_axi_arsize       (m_axi_arsize),
    .m_axi_arburst      (m_axi_arburst),
    .m_axi_arlock       (m_axi_arlock),
    .m_axi_arcache      (m_axi_arcache),
    .m_axi_arprot       (m_axi_arprot),
    .m_axi_arqos        (m_axi_arqos),
    .m_axi_arregion     (m_axi_arregion),
    .m_axi_aruser       (m_axi_aruser),
    .m_axi_arvalid      (m_axi_arvalid),
    .m_axi_arready      (m_axi_arready),

    // AXI4 Read Data
    .m_axi_rid          (m_axi_rid),
    .m_axi_rdata        (m_axi_rdata),
    .m_axi_rresp        (m_axi_rresp),
    .m_axi_rlast        (m_axi_rlast),
    .m_axi_ruser        (m_axi_ruser),
    .m_axi_rvalid       (m_axi_rvalid),
    .m_axi_rready       (m_axi_rready),

    // AXI4 Write Response
    .m_axi_bid          (m_axi_bid),
    .m_axi_bresp        (m_axi_bresp),
    .m_axi_buser        (m_axi_buser),
    .m_axi_bvalid       (m_axi_bvalid),
    .m_axi_bready       (m_axi_bready),

    // UART
    .uart_tx            (uart_tx),
    .uart_rx            (uart_rx),

    // SD Card
    .sd_clk_out         (sd_clk_out),
    .sd_cmd             (sd_cmd),
    .sd_dat             (sd_dat),
    .sd_cd              (sd_cd),

    // SD Control
    .sd_vsd_en          (sd_vsd_en),
    .sd_sel             (sd_sel),
    .sd_resetn          (sd_resetn),

    // LEDs
    .leds               (leds)
);

endmodule
