// XPM wrapper: drop-in replacement for fifo_generator sd_ctrl_fifo on Versal
// Async FIFO, 40-bit x 16 deep, distributed RAM
module sd_ctrl_fifo (
    input  wire        rst,
    input  wire        wr_clk,
    input  wire        rd_clk,
    input  wire        wr_en,
    input  wire        rd_en,
    input  wire [39:0] din,
    output wire [39:0] dout,
    output wire        full,
    output wire        empty
);

xpm_fifo_async #(
    .CASCADE_HEIGHT      (0),
    .CDC_SYNC_STAGES     (4),
    .DOUT_RESET_VALUE    ("0"),
    .ECC_MODE            ("no_ecc"),
    .FIFO_MEMORY_TYPE    ("distributed"),
    .FIFO_READ_LATENCY   (1),
    .FIFO_WRITE_DEPTH    (16),
    .FULL_RESET_VALUE    (1),
    .PROG_EMPTY_THRESH   (3),
    .PROG_FULL_THRESH    (13),
    .RD_DATA_COUNT_WIDTH (4),
    .READ_DATA_WIDTH     (40),
    .READ_MODE           ("std"),
    .RELATED_CLOCKS      (0),
    .SIM_ASSERT_CHK      (0),
    .USE_ADV_FEATURES    ("0000"),
    .WAKEUP_TIME         (0),
    .WRITE_DATA_WIDTH    (40),
    .WR_DATA_COUNT_WIDTH (4)
) xpm_fifo_inst (
    .rst           (rst),
    .wr_clk        (wr_clk),
    .rd_clk        (rd_clk),
    .wr_en         (wr_en),
    .rd_en         (rd_en),
    .din           (din),
    .dout          (dout),
    .full          (full),
    .empty         (empty),
    .wr_rst_busy   (),
    .rd_rst_busy   (),
    .almost_full   (),
    .almost_empty  (),
    .data_valid    (),
    .overflow      (),
    .underflow     (),
    .prog_full     (),
    .prog_empty    (),
    .sleep         (1'b0),
    .injectsbiterr (1'b0),
    .injectdbiterr (1'b0),
    .sbiterr       (),
    .dbiterr       (),
    .wr_data_count (),
    .rd_data_count (),
    .wr_ack        ()
);

endmodule
