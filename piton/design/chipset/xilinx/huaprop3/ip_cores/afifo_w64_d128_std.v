// afifo_w64_d128_std.v — XPM-based async FIFO for Versal (VP1902)
// Drop-in replacement for the fifo_generator-based IP used on 7-series boards.
// Interface matches the original: rst, wr_clk, rd_clk, din[63:0], wr_en, rd_en,
// dout[63:0], full, empty.

module afifo_w64_d128_std (
    input  wire        rst,
    input  wire        wr_clk,
    input  wire        rd_clk,
    input  wire [63:0] din,
    input  wire        wr_en,
    input  wire        rd_en,
    output wire [63:0] dout,
    output wire        full,
    output wire        empty
);

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE ("block"),
        .FIFO_WRITE_DEPTH (128),
        .WRITE_DATA_WIDTH (64),
        .READ_DATA_WIDTH  (64),
        .READ_MODE        ("std"),
        .FIFO_READ_LATENCY(1),
        .FULL_RESET_VALUE (1),
        .USE_ADV_FEATURES ("0000"),
        .CDC_SYNC_STAGES  (2),
        .DOUT_RESET_VALUE ("0"),
        .ECC_MODE         ("no_ecc"),
        .PROG_EMPTY_THRESH(2),
        .PROG_FULL_THRESH (125),
        .RD_DATA_COUNT_WIDTH(1),
        .WR_DATA_COUNT_WIDTH(1),
        .WAKEUP_TIME      (0),
        .SIM_ASSERT_CHK   (0),
        .CASCADE_HEIGHT   (0),
        .RELATED_CLOCKS   (0)
    ) u_xpm_fifo (
        .rst           (rst),
        .wr_clk        (wr_clk),
        .rd_clk        (rd_clk),
        .din           (din),
        .wr_en         (wr_en),
        .rd_en         (rd_en),
        .dout          (dout),
        .full          (full),
        .empty         (empty),
        .wr_rst_busy   (),
        .rd_rst_busy   (),
        .almost_full   (),
        .almost_empty  (),
        .wr_ack        (),
        .overflow      (),
        .underflow     (),
        .data_valid    (),
        .prog_full     (),
        .prog_empty    (),
        .wr_data_count (),
        .rd_data_count (),
        .sleep         (1'b0),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0),
        .sbiterr       (),
        .dbiterr       ()
    );

endmodule
