// ========== Copyright Header Begin ============================================
// Copyright (c) 2015 Princeton University
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of Princeton University nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// ========== Copyright Header End ============================================

// P3-compatible SPI-mode SD top. This preserves the native piton_sd_top NoC-side
// interface while replacing the 4-bit native SD controller with the repository's
// AXI-Lite SD block cache and OpenCores SPI master path.

`include "define.tmp.h"
`include "spi_master_defines.v"

module piton_spi_sd_top (
    input  wire                             sys_clk,
    input  wire                             sd_clk,
    input  wire                             sys_rst,

    input  wire                             splitter_sd_val,
    input  wire [`NOC_DATA_WIDTH-1:0]       splitter_sd_data,
    output wire                             sd_splitter_rdy,

    output wire                             sd_splitter_val,
    output wire [`NOC_DATA_WIDTH-1:0]       sd_splitter_data,
    input  wire                             splitter_sd_rdy,

    input  wire                             sd_cd,
    output wire                             sd_reset,
    output wire                             sd_clk_out,
    inout  wire                             sd_cmd,
    inout  wire [3:0]                       sd_dat
`ifdef P3_BD_SD_INIT_ILA
    ,
    output wire [15:0]                      p3_sd_init_seen_o,
    output wire [63:0]                      p3_sd_init_bus_o
`endif
    );

    wire [`NOC_DATA_WIDTH-1:0]              sd_axi_awaddr;
    wire                                    sd_axi_awvalid;
    wire                                    sd_axi_awready;
    wire [`NOC_DATA_WIDTH-1:0]              sd_axi_wdata;
    wire [`NOC_DATA_WIDTH/8-1:0]            sd_axi_wstrb;
    wire                                    sd_axi_wvalid;
    wire                                    sd_axi_wready;
    wire [`NOC_DATA_WIDTH-1:0]              sd_axi_araddr;
    wire                                    sd_axi_arvalid;
    wire                                    sd_axi_arready;
    wire [`NOC_DATA_WIDTH-1:0]              sd_axi_rdata;
    wire [1:0]                              sd_axi_rresp;
    wire                                    sd_axi_rvalid;
    wire                                    sd_axi_rready;
    wire [1:0]                              sd_axi_bresp;
    wire                                    sd_axi_bvalid;
    wire                                    sd_axi_bready;

    wire                                    wb_ack;
    wire [7:0]                              wb_dat_i;
    wire [7:0]                              wb_adr;
    wire [7:0]                              wb_dat_o;
    wire                                    wb_stb;
    wire                                    wb_we;

    wire                                    spi_clk_out;
    wire                                    spi_data_out;
    wire                                    spi_cs_n;
    wire                                    sd_cmd_i;
    wire                                    sd_cmd_o;
    wire                                    sd_cmd_oe;
    wire [3:0]                              sd_dat_i;
    wire [3:0]                              sd_dat_o;
    wire [3:0]                              sd_dat_oe;
    wire                                    spi_data_in = sd_dat_i[0];
`ifdef P3_SPI_SD_REF_CMD_DEBUG
    wire                                    p3_ref_sd_clk_out;
    wire                                    p3_ref_sd_cmd_o;
    wire                                    p3_ref_sd_cmd_oe;
    wire [3:0]                              p3_ref_sd_dat_o;
    wire [3:0]                              p3_ref_sd_dat_oe;
    wire [15:0]                             p3_ref_seen;
    wire [63:0]                             p3_ref_bus;
`endif
`ifdef P3_BD_SD_INIT_ILA
`ifdef P3_SPI_SD_HISTORY_DEBUG
    wire [63:0]                             p3_spi_init_debug;
`else
    wire [31:0]                             p3_spi_init_debug;
`endif
`ifdef P3_SPI_SD_BLOCK_DEBUG
    wire [15:0]                             p3_block_seen;
    wire [63:0]                             p3_block_debug;
`endif
`endif

    assign sd_reset   = sys_rst;

    IOBUF sd_cmd_iobuf (
        .I  (sd_cmd_o),
        .O  (sd_cmd_i),
        .T  (~sd_cmd_oe),
        .IO (sd_cmd)
    );

    IOBUF sd_dat_iobuf_0 (
        .I  (sd_dat_o[0]),
        .O  (sd_dat_i[0]),
        .T  (~sd_dat_oe[0]),
        .IO (sd_dat[0])
    );

    IOBUF sd_dat_iobuf_1 (
        .I  (sd_dat_o[1]),
        .O  (sd_dat_i[1]),
        .T  (~sd_dat_oe[1]),
        .IO (sd_dat[1])
    );

    IOBUF sd_dat_iobuf_2 (
        .I  (sd_dat_o[2]),
        .O  (sd_dat_i[2]),
        .T  (~sd_dat_oe[2]),
        .IO (sd_dat[2])
    );

    IOBUF sd_dat_iobuf_3 (
        .I  (sd_dat_o[3]),
        .O  (sd_dat_i[3]),
        .T  (~sd_dat_oe[3]),
        .IO (sd_dat[3])
    );

`ifdef P3_SPI_SD_REF_CMD_DEBUG
    // Build 62: isolate the external SD response boundary by driving the pads
    // with the standalone Build 56 SPI command sequence inside the full shell.
    assign sd_clk_out = p3_ref_sd_clk_out;
    assign sd_cmd_o   = p3_ref_sd_cmd_o;
    assign sd_cmd_oe  = p3_ref_sd_cmd_oe;
    assign sd_dat_o   = p3_ref_sd_dat_o;
    assign sd_dat_oe  = p3_ref_sd_dat_oe;
`else
    assign sd_clk_out = spi_clk_out;

    // Reference P3 project uses SD in SPI mode:
    //   CMD  = MOSI, DAT0 = MISO, DAT3 = CS#.
    assign sd_cmd_o  = spi_data_out;
    assign sd_cmd_oe = 1'b1;
    assign sd_dat_o  = {spi_cs_n, 3'b111};
    assign sd_dat_oe = 4'b1000;
`endif

`ifdef P3_SPI_SD_REF_CMD_DEBUG
    p3_spi_sd_ref_cmd_probe p3_spi_sd_ref_cmd_probe (
        .clk         (sys_clk),
        .rst         (sys_rst),
        .sd_cd       (sd_cd),
        .sd_cmd_i    (sd_cmd_i),
        .sd_dat_i    (sd_dat_i),
        .sd_clk_o    (p3_ref_sd_clk_out),
        .sd_cmd_o    (p3_ref_sd_cmd_o),
        .sd_cmd_oe   (p3_ref_sd_cmd_oe),
        .sd_dat_o    (p3_ref_sd_dat_o),
        .sd_dat_oe   (p3_ref_sd_dat_oe),
        .dbg_seen_o  (p3_ref_seen),
        .dbg_bus_o   (p3_ref_bus)
    );
`endif

    noc_axilite_bridge #(
        .SLAVE_RESP_BYTEWIDTH (8),
        .SWAP_ENDIANESS       (0),
        .ALIGN_RDATA          (1)
    ) noc_spi_sd_bridge (
        .clk                  (sys_clk),
        .rst                  (sys_rst),

        .splitter_bridge_val  (splitter_sd_val),
        .splitter_bridge_data (splitter_sd_data),
        .bridge_splitter_rdy  (sd_splitter_rdy),

        .bridge_splitter_val  (sd_splitter_val),
        .bridge_splitter_data (sd_splitter_data),
        .splitter_bridge_rdy  (splitter_sd_rdy),

        .m_axi_awaddr         (sd_axi_awaddr),
        .m_axi_awvalid        (sd_axi_awvalid),
        .m_axi_awready        (sd_axi_awready),

        .m_axi_wdata          (sd_axi_wdata),
        .m_axi_wstrb          (sd_axi_wstrb),
        .m_axi_wvalid         (sd_axi_wvalid),
        .m_axi_wready         (sd_axi_wready),

        .m_axi_araddr         (sd_axi_araddr),
        .m_axi_arvalid        (sd_axi_arvalid),
        .m_axi_arready        (sd_axi_arready),

        .m_axi_rdata          (sd_axi_rdata),
        .m_axi_rresp          (sd_axi_rresp),
        .m_axi_rvalid         (sd_axi_rvalid),
        .m_axi_rready         (sd_axi_rready),

        .m_axi_bresp          (sd_axi_bresp),
        .m_axi_bvalid         (sd_axi_bvalid),
        .m_axi_bready         (sd_axi_bready),

        .w_reqbuf_size        (),
        .r_reqbuf_size        ()
    );

    axi_sd_bridge axi_spi_sd_bridge (
        .clk           (sys_clk),
        .rst           (sys_rst),

        .s_axi_awaddr  (sd_axi_awaddr),
        .s_axi_awvalid (sd_axi_awvalid),
        .s_axi_awready (sd_axi_awready),

        .s_axi_wdata   (sd_axi_wdata),
        .s_axi_wstrb   (sd_axi_wstrb),
        .s_axi_wvalid  (sd_axi_wvalid),
        .s_axi_wready  (sd_axi_wready),

        .s_axi_araddr  (sd_axi_araddr),
        .s_axi_arvalid (sd_axi_arvalid),
        .s_axi_arready (sd_axi_arready),

        .s_axi_rdata   (sd_axi_rdata),
        .s_axi_rresp   (sd_axi_rresp),
        .s_axi_rvalid  (sd_axi_rvalid),
        .s_axi_rready  (sd_axi_rready),

        .s_axi_bresp   (sd_axi_bresp),
        .s_axi_bvalid  (sd_axi_bvalid),
        .s_axi_bready  (sd_axi_bready),

        .ack_i         (wb_ack),
        .dat_i         (wb_dat_i),
        .adr_o         (wb_adr),
        .dat_o         (wb_dat_o),
        .stb_o         (wb_stb),
        .we_o          (wb_we)
`ifdef P3_SPI_SD_BLOCK_DEBUG
       ,.p3_block_seen_o  (p3_block_seen),
        .p3_block_debug_o (p3_block_debug)
`endif
    );

    spi_master sd_spi_master (
        .clk_i        (sys_clk),
        .rst_i        (sys_rst),

        .adr_i        (wb_adr),
        .dat_i        (wb_dat_o),
        .stb_i        (wb_stb),
        .we_i         (wb_we),
        .ack_o        (wb_ack),
        .dat_o        (wb_dat_i),

        .spi_sys_clk  (sd_clk),
        .spi_data_in  (spi_data_in),
        .spi_clk_out  (spi_clk_out),
        .spi_data_out (spi_data_out),
        .spi_cs_n     (spi_cs_n)
`ifdef P3_BD_SD_INIT_ILA
       ,.p3_init_debug_o (p3_spi_init_debug)
`endif
    );

`ifdef P3_BD_SD_INIT_ILA
    wire noc_req_fire  = splitter_sd_val & sd_splitter_rdy;
    wire noc_resp_fire = sd_splitter_val & splitter_sd_rdy;
    wire axi_ar_fire   = sd_axi_arvalid & sd_axi_arready;
    wire axi_r_fire    = sd_axi_rvalid  & sd_axi_rready;
    wire axi_aw_fire   = sd_axi_awvalid & sd_axi_awready;
    wire axi_w_fire    = sd_axi_wvalid  & sd_axi_wready;
    wire axi_b_fire    = sd_axi_bvalid  & sd_axi_bready;
    wire wb_fire       = wb_stb & wb_ack;

    reg        spi_clk_sample_q;
    reg        spi_clk_sample_qq;
    wire       spi_clk_toggle = spi_clk_sample_q ^ spi_clk_sample_qq;

    reg [15:0] p3_spi_sd_seen_r;
    reg [15:0] p3_last_sd_req_addr16_r;
    reg [7:0]  p3_last_wb_adr_r;
    reg [7:0]  p3_last_wb_dat_i_r;
    reg [7:0]  p3_last_wb_dat_o_r;
    reg [5:0]  p3_last_error_r;
    reg        p3_last_trans_status_r;
`ifdef P3_SPI_SD_PAD_DEBUG
    reg        p3_spi_cs_n_q;
    reg        p3_cmd_capture_active_r;
    reg [5:0]  p3_cmd_bit_count_r;
    reg [55:0] p3_cmd_mosi_shift_r;
`endif

    wire wb_write_trans_ctrl = wb_fire & wb_we  & (wb_adr == `TRANS_CTRL_REG) & wb_dat_o[0];
    wire wb_write_init_type  = wb_fire & wb_we  & (wb_adr == `TRANS_TYPE_REG) & (wb_dat_o[1:0] == `INIT_SD);
    wire wb_write_read_type  = wb_fire & wb_we  & (wb_adr == `TRANS_TYPE_REG) & (wb_dat_o[1:0] == `RW_READ_SD_BLOCK);
    wire wb_read_status      = wb_fire & ~wb_we & (wb_adr == `TRANS_STS_REG);
    wire wb_read_error       = wb_fire & ~wb_we & (wb_adr == `TRANS_ERROR_REG);
`ifdef P3_SPI_SD_PAD_DEBUG
    wire p3_spi_rise_sys    = spi_clk_sample_q & ~spi_clk_sample_qq;
    wire p3_spi_cs_fall_sys = ~spi_cs_n & p3_spi_cs_n_q;
`endif

    wire [15:0] p3_spi_sd_flags = {
        spi_data_in,
        spi_data_out,
        spi_cs_n,
        spi_clk_out,
        wb_we,
        wb_ack,
        wb_stb,
        sd_axi_bvalid,
        sd_axi_wvalid,
        sd_axi_awvalid,
        sd_axi_rvalid,
        sd_axi_arvalid,
        sd_splitter_val,
        sd_splitter_rdy,
        sd_cd,
        sys_rst
    };

    always @(posedge sys_clk or posedge sys_rst) begin
        if (sys_rst) begin
            spi_clk_sample_q       <= 1'b0;
            spi_clk_sample_qq      <= 1'b0;
            p3_spi_sd_seen_r       <= 16'd0;
            p3_last_sd_req_addr16_r <= 16'd0;
            p3_last_wb_adr_r       <= 8'd0;
            p3_last_wb_dat_i_r     <= 8'd0;
            p3_last_wb_dat_o_r     <= 8'd0;
            p3_last_error_r        <= 6'd0;
            p3_last_trans_status_r <= 1'b0;
`ifdef P3_SPI_SD_PAD_DEBUG
            p3_spi_cs_n_q           <= 1'b1;
            p3_cmd_capture_active_r <= 1'b0;
            p3_cmd_bit_count_r      <= 6'd0;
            p3_cmd_mosi_shift_r     <= 56'd0;
`endif
        end
        else begin
            spi_clk_sample_q  <= spi_clk_out;
            spi_clk_sample_qq <= spi_clk_sample_q;
`ifdef P3_SPI_SD_PAD_DEBUG
            p3_spi_cs_n_q <= spi_cs_n;

            if (p3_spi_cs_fall_sys) begin
                p3_cmd_capture_active_r <= 1'b1;
                p3_cmd_bit_count_r      <= 6'd0;
                p3_cmd_mosi_shift_r     <= 56'd0;
            end
            else if (p3_spi_rise_sys && !spi_cs_n &&
                     p3_cmd_capture_active_r &&
                     p3_cmd_bit_count_r < 6'd56) begin
                p3_cmd_mosi_shift_r <= {p3_cmd_mosi_shift_r[54:0], spi_data_out};
                p3_cmd_bit_count_r  <= p3_cmd_bit_count_r + 1'b1;
                if (p3_cmd_bit_count_r == 6'd55) begin
                    p3_cmd_capture_active_r <= 1'b0;
                end
            end
`endif

            p3_spi_sd_seen_r <= p3_spi_sd_seen_r |
                                {~spi_data_in,
                                 spi_clk_toggle,
                                 wb_write_read_type,
                                 wb_write_init_type,
                                 wb_write_trans_ctrl,
                                 wb_fire,
                                 axi_b_fire,
                                 axi_w_fire,
                                 axi_aw_fire,
                                 noc_resp_fire,
                                 axi_r_fire,
                                 axi_ar_fire,
                                 noc_req_fire,
                                 ~sd_cd,
                                 sd_cd,
                                 ~sys_rst};

            if (noc_req_fire) begin
                p3_last_sd_req_addr16_r <= splitter_sd_data[`MSG_ADDR_HI_:`MSG_ADDR_HI_-15];
            end
            if (wb_fire) begin
                p3_last_wb_adr_r   <= wb_adr;
                p3_last_wb_dat_i_r <= wb_dat_i;
                p3_last_wb_dat_o_r <= wb_dat_o;
            end
            if (wb_read_error) begin
                p3_last_error_r <= wb_dat_i[5:0];
            end
            if (wb_read_status) begin
                p3_last_trans_status_r <= wb_dat_i[0];
            end
        end
    end

`ifdef P3_SPI_SD_BLOCK_DEBUG
    assign p3_sd_init_seen_o = p3_block_seen;
    assign p3_sd_init_bus_o  = p3_block_debug;
`elsif P3_SPI_SD_REF_CMD_DEBUG
    assign p3_sd_init_seen_o = p3_ref_seen;
    assign p3_sd_init_bus_o  = p3_ref_bus;
`elsif P3_SPI_SD_PAD_DEBUG
    assign p3_sd_init_seen_o = p3_spi_sd_seen_r;
    assign p3_sd_init_bus_o  = {p3_cmd_bit_count_r,
                                p3_cmd_mosi_shift_r,
                                p3_cmd_capture_active_r,
                                spi_cs_n};
`elsif P3_SPI_SD_HISTORY_DEBUG
    assign p3_sd_init_seen_o = p3_spi_sd_seen_r;
    assign p3_sd_init_bus_o  = p3_spi_init_debug;
`else
    assign p3_sd_init_seen_o = p3_spi_sd_seen_r;
    assign p3_sd_init_bus_o  = {p3_spi_init_debug,
                                p3_last_wb_adr_r,
                                p3_last_wb_dat_i_r,
                                p3_last_error_r,
                                p3_last_trans_status_r,
                                spi_data_in,
                                p3_spi_sd_flags[15:8]};
`endif
`endif

endmodule

`ifdef P3_SPI_SD_REF_CMD_DEBUG
module p3_spi_sd_ref_cmd_probe (
    input  wire        clk,
    input  wire        rst,
    input  wire        sd_cd,
    input  wire        sd_cmd_i,
    input  wire [3:0]  sd_dat_i,
    output wire        sd_clk_o,
    output wire        sd_cmd_o,
    output wire        sd_cmd_oe,
    output wire [3:0]  sd_dat_o,
    output wire [3:0]  sd_dat_oe,
    output wire [15:0] dbg_seen_o,
    output wire [63:0] dbg_bus_o
);
    localparam integer SD_HALF_DIV   = 37;
    localparam integer POWER_WAIT    = 3000000;
    localparam integer RESPONSE_BITS = 8192;

    localparam [7:0] ST_IDLE          = 8'h00;
    localparam [7:0] ST_POWER_WAIT    = 8'h01;
    localparam [7:0] ST_IDLE_CLOCKS   = 8'h02;
    localparam [7:0] ST_CMD_LOAD      = 8'h03;
    localparam [7:0] ST_CMD_LOW       = 8'h04;
    localparam [7:0] ST_CMD_HIGH      = 8'h05;
    localparam [7:0] ST_SPI_RESP_LOW  = 8'h10;
    localparam [7:0] ST_SPI_RESP_HIGH = 8'h11;
    localparam [7:0] ST_PASS          = 8'hf0;
    localparam [7:0] ST_FAIL          = 8'hf1;

    reg [7:0]  state;
    reg        busy;
    reg        done;
    reg        pass;
    reg        fail;
    reg        timeout_seen;
    reg        spi_miso_seen_low;
    reg        non_ff_response_seen;
    reg        sd_clk_r;
    reg        cmd_r;
    reg        cmd_oe_r;
    reg [3:0]  dat_r;
    reg [3:0]  dat_oe_r;
    reg [31:0] wait_ctr;
    reg [15:0] idle_edges;
    reg [47:0] cmd_shift;
    reg [5:0]  bit_count;
    reg [15:0] response_timeout;
    reg [7:0]  response_byte;
    reg [2:0]  response_bit_count;
    reg [7:0]  command_index;
    reg [15:0] seen_r;

    wire       cmd0_selected = (command_index == 8'd0);
    wire       response_byte_non_ff =
                   (response_bit_count == 3'd7) &&
                   ({response_byte[6:0], sd_dat_i[0]} != 8'hff);

    assign sd_clk_o  = sd_clk_r;
    assign sd_cmd_o  = cmd_r;
    assign sd_cmd_oe = cmd_oe_r;
    assign sd_dat_o  = dat_r;
    assign sd_dat_oe = dat_oe_r;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state                <= ST_IDLE;
            busy                 <= 1'b0;
            done                 <= 1'b0;
            pass                 <= 1'b0;
            fail                 <= 1'b0;
            timeout_seen         <= 1'b0;
            spi_miso_seen_low    <= 1'b0;
            non_ff_response_seen <= 1'b0;
            sd_clk_r             <= 1'b0;
            cmd_r                <= 1'b1;
            cmd_oe_r             <= 1'b0;
            dat_r                <= 4'hf;
            dat_oe_r             <= 4'h0;
            wait_ctr             <= 32'd0;
            idle_edges           <= 16'd0;
            cmd_shift            <= 48'h0;
            bit_count            <= 6'd0;
            response_timeout     <= 16'd0;
            response_byte        <= 8'hff;
            response_bit_count   <= 3'd0;
            command_index        <= 8'd0;
            seen_r               <= 16'd0;
        end else begin
            seen_r <= seen_r | {timeout_seen,
                                fail,
                                pass,
                                non_ff_response_seen,
                                spi_miso_seen_low | ~sd_dat_i[0],
                                sd_clk_r,
                                (state == ST_SPI_RESP_LOW) | (state == ST_SPI_RESP_HIGH),
                                (command_index == 8'd1) & (state == ST_SPI_RESP_HIGH),
                                (command_index == 8'd1) & (state == ST_CMD_LOAD),
                                (command_index == 8'd0) & (state == ST_SPI_RESP_HIGH),
                                (command_index == 8'd0) & (state == ST_CMD_LOAD),
                                (state == ST_IDLE_CLOCKS) & (idle_edges >= 16'd159),
                                (state != ST_POWER_WAIT) & busy,
                                ~sd_cd,
                                sd_cd,
                                1'b1};

            case (state)
                ST_IDLE: begin
                    busy <= 1'b1;
                    done <= 1'b0;
                    pass <= 1'b0;
                    fail <= 1'b0;
                    timeout_seen <= 1'b0;
                    spi_miso_seen_low <= 1'b0;
                    non_ff_response_seen <= 1'b0;
                    sd_clk_r <= 1'b0;
                    cmd_r <= 1'b1;
                    cmd_oe_r <= 1'b1;
                    dat_r <= 4'hf;
                    dat_oe_r <= 4'b1000;
                    wait_ctr <= POWER_WAIT;
                    idle_edges <= 16'd0;
                    command_index <= 8'd0;
                    state <= ST_POWER_WAIT;
                end

                ST_POWER_WAIT: begin
                    cmd_r <= 1'b1;
                    cmd_oe_r <= 1'b1;
                    dat_r <= 4'hf;
                    dat_oe_r <= 4'b1000;
                    if (wait_ctr != 32'd0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        wait_ctr <= SD_HALF_DIV - 1;
                        state <= ST_IDLE_CLOCKS;
                    end
                end

                ST_IDLE_CLOCKS: begin
                    cmd_r <= 1'b1;
                    cmd_oe_r <= 1'b1;
                    dat_r <= 4'hf;
                    dat_oe_r <= 4'b1000;
                    if (wait_ctr != 32'd0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        wait_ctr <= SD_HALF_DIV - 1;
                        sd_clk_r <= ~sd_clk_r;
                        idle_edges <= idle_edges + 1'b1;
                        if (idle_edges >= 16'd159 && sd_clk_r == 1'b1) begin
                            state <= ST_CMD_LOAD;
                        end
                    end
                end

                ST_CMD_LOAD: begin
                    sd_clk_r <= 1'b0;
                    bit_count <= 6'd48;
                    wait_ctr <= SD_HALF_DIV - 1;
                    dat_r[3] <= 1'b0;
                    dat_oe_r <= 4'b1000;
                    cmd_oe_r <= 1'b1;
                    cmd_shift <= cmd0_selected ? 48'h400000000095 : 48'h48000001aa87;
                    state <= ST_CMD_LOW;
                end

                ST_CMD_LOW: begin
                    if (wait_ctr != 32'd0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        sd_clk_r <= 1'b1;
                        cmd_r <= cmd_shift[47];
                        wait_ctr <= SD_HALF_DIV - 1;
                        state <= ST_CMD_HIGH;
                    end
                end

                ST_CMD_HIGH: begin
                    if (wait_ctr != 32'd0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        sd_clk_r <= 1'b0;
                        cmd_shift <= {cmd_shift[46:0], 1'b1};
                        if (bit_count > 6'd1) begin
                            bit_count <= bit_count - 1'b1;
                            wait_ctr <= SD_HALF_DIV - 1;
                            state <= ST_CMD_LOW;
                        end else begin
                            response_timeout <= RESPONSE_BITS[15:0];
                            response_bit_count <= 3'd0;
                            response_byte <= 8'hff;
                            wait_ctr <= SD_HALF_DIV - 1;
                            cmd_r <= 1'b1;
                            cmd_oe_r <= 1'b1;
                            state <= ST_SPI_RESP_LOW;
                        end
                    end
                end

                ST_SPI_RESP_LOW: begin
                    if (wait_ctr != 32'd0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        sd_clk_r <= 1'b1;
                        wait_ctr <= SD_HALF_DIV - 1;
                        state <= ST_SPI_RESP_HIGH;
                    end
                end

                ST_SPI_RESP_HIGH: begin
                    if (wait_ctr != 32'd0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        sd_clk_r <= 1'b0;
                        response_byte <= {response_byte[6:0], sd_dat_i[0]};
                        response_bit_count <= response_bit_count + 1'b1;
                        if (!sd_dat_i[0]) begin
                            spi_miso_seen_low <= 1'b1;
                        end
                        if (response_byte_non_ff) begin
                            non_ff_response_seen <= 1'b1;
                            pass <= 1'b1;
                            done <= 1'b1;
                            busy <= 1'b0;
                            dat_r[3] <= 1'b1;
                            state <= ST_PASS;
                        end else if (response_timeout == 16'd0) begin
                            if (cmd0_selected) begin
                                command_index <= 8'd1;
                                response_timeout <= RESPONSE_BITS[15:0];
                                state <= ST_CMD_LOAD;
                            end else begin
                                fail <= 1'b1;
                                done <= 1'b1;
                                busy <= 1'b0;
                                timeout_seen <= 1'b1;
                                dat_r[3] <= 1'b1;
                                state <= ST_FAIL;
                            end
                        end else begin
                            response_timeout <= response_timeout - 1'b1;
                            wait_ctr <= SD_HALF_DIV - 1;
                            state <= ST_SPI_RESP_LOW;
                        end
                    end
                end

                ST_PASS: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    pass <= 1'b1;
                    fail <= 1'b0;
                    sd_clk_r <= 1'b0;
                    cmd_r <= 1'b1;
                    cmd_oe_r <= 1'b1;
                    dat_r <= 4'hf;
                    dat_oe_r <= 4'b1000;
                end

                ST_FAIL: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    pass <= 1'b0;
                    fail <= 1'b1;
                    sd_clk_r <= 1'b0;
                    cmd_r <= 1'b1;
                    cmd_oe_r <= 1'b1;
                    dat_r <= 4'hf;
                    dat_oe_r <= 4'b1000;
                end

                default: begin
                    fail <= 1'b1;
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= ST_FAIL;
                end
            endcase
        end
    end

    assign dbg_seen_o = seen_r;
    assign dbg_bus_o  = {8'h63,
                         state,
                         command_index,
                         response_byte,
                         response_timeout,
                         bit_count,
                         response_bit_count,
                         sd_clk_r,
                         cmd_oe_r,
                         cmd_r,
                         sd_dat_i[0],
                         spi_miso_seen_low,
                         pass,
                         fail};

    wire unused_sd_cmd_i = sd_cmd_i;
endmodule
`endif
