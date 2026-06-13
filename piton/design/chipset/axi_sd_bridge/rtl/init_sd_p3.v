//////////////////////////////////////////////////////////////////////
////                                                              ////
//// init_sd_p3.v                                                 ////
////                                                              ////
//// P3 SD-card SPI initialization sequence.                      ////
////                                                              ////
//// This is interface-compatible with init_sd.v, but uses the    ////
//// modern SDHC-friendly CMD0, CMD8, CMD55/ACMD41 sequence       ////
//// instead of the original CMD0/CMD1 flow.                      ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`include "spi_master_defines.v"

module init_sd_p3(
    input  wire       clk,
    input  wire       rst,

    input  wire       sd_init_req,
    input  wire       send_cmd_rdy,

    input  wire [7:0] resp_byte,
    input  wire       resp_tout,
    input  wire       rx_data_rdy,
    input  wire       tx_data_empty,
    input  wire       tx_data_full,
    input  wire [7:0] spi_clk_delay_in,

    output reg  [7:0] check_sum_byte,
    output reg  [7:0] cmd_byte,
    output reg  [7:0] data_byte_1,
    output reg  [7:0] data_byte_2,
    output reg  [7:0] data_byte_3,
    output reg  [7:0] data_byte_4,
    output reg        send_cmd_req,
    output reg  [1:0] sd_init_error,
    output reg        sd_init_rdy,
    output reg  [7:0] spi_clk_delay_out,
    output reg        spi_cs_n,
    output reg        rx_data_rdy_clr,
    output reg  [7:0] tx_data_out,
    output reg        tx_data_wen
`ifdef P3_BD_SD_INIT_ILA
    ,
    output wire [31:0] p3_init_debug_o
`endif
);

    reg [7:0] next_check_sum_byte;
    reg [7:0] next_cmd_byte;
    reg [7:0] next_data_byte_1;
    reg [7:0] next_data_byte_2;
    reg [7:0] next_data_byte_3;
    reg [7:0] next_data_byte_4;
    reg [1:0] next_sd_init_error;
    reg       next_rx_data_rdy_clr;
    reg       next_sd_init_rdy;
    reg       next_send_cmd_req;
    reg [7:0] next_spi_clk_delay_out;
    reg       next_spi_cs_n;
    reg [7:0] next_tx_data_out;
    reg       next_tx_data_wen;

    reg [9:0] del_cnt_1, next_del_cnt_1;
    reg [7:0] del_cnt_2, next_del_cnt_2;
    reg [21:0] power_wait_cnt, next_power_wait_cnt;
    reg [7:0] loop_cnt, next_loop_cnt;

    localparam [4:0] START                 = 5'd0;
    localparam [4:0] WT_INIT_REQ           = 5'd1;
    localparam [4:0] CLK_SEQ_SEND_FF       = 5'd2;
    localparam [4:0] CLK_SEQ_CHK_FIN       = 5'd3;
    localparam [4:0] CLK_SEQ_WT_DATA_EMPTY = 5'd4;
    localparam [4:0] CMD0_SEND             = 5'd5;
    localparam [4:0] CMD0_DEL              = 5'd6;
    localparam [4:0] CMD0_WAIT             = 5'd7;
    localparam [4:0] CMD0_CHECK            = 5'd8;
    localparam [4:0] CMD8_SEND             = 5'd9;
    localparam [4:0] CMD8_DEL              = 5'd10;
    localparam [4:0] CMD8_WAIT             = 5'd11;
    localparam [4:0] CMD8_CHECK            = 5'd12;
    localparam [4:0] CMD55_SEND            = 5'd13;
    localparam [4:0] CMD55_DEL             = 5'd14;
    localparam [4:0] CMD55_WAIT            = 5'd15;
    localparam [4:0] CMD55_CHECK           = 5'd16;
    localparam [4:0] ACMD41_SEND           = 5'd17;
    localparam [4:0] ACMD41_DEL            = 5'd18;
    localparam [4:0] ACMD41_WAIT           = 5'd19;
    localparam [4:0] ACMD41_CHECK          = 5'd20;
    localparam [4:0] ACMD41_RETRY_DEL1     = 5'd21;
    localparam [4:0] ACMD41_RETRY_DEL2     = 5'd22;
    localparam [4:0] INIT_DONE             = 5'd23;
    localparam [4:0] POWER_WAIT            = 5'd24;

    localparam [21:0] POWER_WAIT_CYCLES    = 22'd3000000;

    reg [4:0] state, next_state;

`ifdef P3_SPI_SD_HISTORY_DEBUG
    reg [24:0] p3_state_seen;
    reg        p3_sd_init_req_seen;
    reg        p3_resp_tout_seen;

    wire [24:0] p3_state_bit = (25'd1 << state);
`endif

    always @(*) begin
        next_state             = state;
        next_spi_clk_delay_out = spi_clk_delay_out;
        next_sd_init_rdy       = sd_init_rdy;
        next_spi_cs_n          = spi_cs_n;
        next_sd_init_error     = sd_init_error;
        next_tx_data_out       = tx_data_out;
        next_tx_data_wen       = tx_data_wen;
        next_cmd_byte          = cmd_byte;
        next_data_byte_1       = data_byte_1;
        next_data_byte_2       = data_byte_2;
        next_data_byte_3       = data_byte_3;
        next_data_byte_4       = data_byte_4;
        next_check_sum_byte    = check_sum_byte;
        next_send_cmd_req      = send_cmd_req;
        next_loop_cnt          = loop_cnt;
        next_del_cnt_1         = del_cnt_1;
        next_del_cnt_2         = del_cnt_2;
        next_power_wait_cnt    = power_wait_cnt;
        next_rx_data_rdy_clr   = rx_data_rdy_clr;

        case (state)
            START: begin
                next_spi_clk_delay_out = spi_clk_delay_in;
                next_sd_init_rdy       = 1'b0;
                next_spi_cs_n          = 1'b1;
                next_sd_init_error     = `INIT_NO_ERROR;
                next_tx_data_out       = 8'h00;
                next_tx_data_wen       = 1'b0;
                next_cmd_byte          = 8'h00;
                next_data_byte_1       = 8'h00;
                next_data_byte_2       = 8'h00;
                next_data_byte_3       = 8'h00;
                next_data_byte_4       = 8'h00;
                next_check_sum_byte    = 8'h00;
                next_send_cmd_req      = 1'b0;
                next_loop_cnt          = 8'h00;
                next_del_cnt_1         = 10'h000;
                next_del_cnt_2         = 8'h00;
                next_rx_data_rdy_clr   = 1'b0;
                next_state             = WT_INIT_REQ;
            end

            WT_INIT_REQ: begin
                next_sd_init_rdy       = 1'b1;
                next_spi_clk_delay_out = spi_clk_delay_in;
                next_spi_cs_n          = 1'b1;
                next_tx_data_wen       = 1'b0;
                next_send_cmd_req      = 1'b0;
                next_rx_data_rdy_clr   = rx_data_rdy;
                next_cmd_byte          = 8'h00;
                next_data_byte_1       = 8'h00;
                next_data_byte_2       = 8'h00;
                next_data_byte_3       = 8'h00;
                next_data_byte_4       = 8'h00;
                next_check_sum_byte    = 8'h00;
                if (sd_init_req == 1'b1) begin
                    next_state             = POWER_WAIT;
                    next_sd_init_rdy       = 1'b0;
                    next_loop_cnt          = 8'h00;
                    next_power_wait_cnt    = 22'd0;
                    next_spi_clk_delay_out = `SLOW_SPI_CLK;
                    next_sd_init_error     = `INIT_NO_ERROR;
                end
            end

            POWER_WAIT: begin
                next_spi_cs_n       = 1'b1;
                next_tx_data_wen    = 1'b0;
                next_send_cmd_req   = 1'b0;
                next_rx_data_rdy_clr = rx_data_rdy;
                if (power_wait_cnt == POWER_WAIT_CYCLES) begin
                    next_state = CLK_SEQ_SEND_FF;
                end
                else begin
                    next_power_wait_cnt = power_wait_cnt + 1'b1;
                end
            end

            CLK_SEQ_SEND_FF: begin
                next_rx_data_rdy_clr = 1'b0;
                if (tx_data_full == 1'b0) begin
                    next_state       = CLK_SEQ_CHK_FIN;
                    next_tx_data_out = 8'hff;
                    next_tx_data_wen = 1'b1;
                    next_loop_cnt    = loop_cnt + 1'b1;
                end
            end

            CLK_SEQ_CHK_FIN: begin
                next_tx_data_wen = 1'b0;
                if (loop_cnt == `SD_INIT_START_SEQ_LEN) begin
                    next_state = CLK_SEQ_WT_DATA_EMPTY;
                end
                else begin
                    next_state = CLK_SEQ_SEND_FF;
                end
            end

            CLK_SEQ_WT_DATA_EMPTY: begin
                if (tx_data_empty == 1'b1) begin
                    next_state    = CMD0_SEND;
                    next_loop_cnt = 8'h00;
                end
            end

            CMD0_SEND: begin
                next_cmd_byte       = 8'h40;
                next_data_byte_1    = 8'h00;
                next_data_byte_2    = 8'h00;
                next_data_byte_3    = 8'h00;
                next_data_byte_4    = 8'h00;
                next_check_sum_byte = 8'h95;
                next_send_cmd_req   = 1'b1;
                next_loop_cnt       = loop_cnt + 1'b1;
                next_spi_cs_n       = 1'b0;
                next_state          = CMD0_DEL;
            end

            CMD0_DEL: begin
                next_send_cmd_req = 1'b0;
                next_state        = CMD0_WAIT;
            end

            CMD0_WAIT: begin
                if (send_cmd_rdy == 1'b1) begin
                    next_state    = CMD0_CHECK;
                    next_spi_cs_n = 1'b1;
                end
            end

            CMD0_CHECK: begin
                if ((resp_tout == 1'b1 || resp_byte != 8'h01) && loop_cnt != 8'hff) begin
                    next_state = CMD0_SEND;
                end
                else if (resp_tout == 1'b1 || resp_byte != 8'h01) begin
                    next_state         = WT_INIT_REQ;
                    next_sd_init_error = `INIT_CMD0_ERROR;
                end
                else begin
                    next_state    = CMD8_SEND;
                    next_loop_cnt = 8'h00;
                end
            end

            CMD8_SEND: begin
                next_cmd_byte       = 8'h48;
                next_data_byte_1    = 8'h00;
                next_data_byte_2    = 8'h00;
                next_data_byte_3    = 8'h01;
                next_data_byte_4    = 8'haa;
                next_check_sum_byte = 8'h87;
                next_send_cmd_req   = 1'b1;
                next_spi_cs_n       = 1'b0;
                next_state          = CMD8_DEL;
            end

            CMD8_DEL: begin
                next_send_cmd_req = 1'b0;
                next_state        = CMD8_WAIT;
            end

            CMD8_WAIT: begin
                if (send_cmd_rdy == 1'b1) begin
                    next_state    = CMD8_CHECK;
                    next_spi_cs_n = 1'b1;
                end
            end

            CMD8_CHECK: begin
                if (resp_tout == 1'b1 || resp_byte != 8'h01) begin
                    next_state         = WT_INIT_REQ;
                    next_sd_init_error = `INIT_CMD8_ERROR;
                end
                else begin
                    next_state    = CMD55_SEND;
                    next_loop_cnt = 8'h00;
                end
            end

            CMD55_SEND: begin
                next_cmd_byte       = 8'h77;
                next_data_byte_1    = 8'h00;
                next_data_byte_2    = 8'h00;
                next_data_byte_3    = 8'h00;
                next_data_byte_4    = 8'h00;
                next_check_sum_byte = 8'h65;
                next_send_cmd_req   = 1'b1;
                next_spi_cs_n       = 1'b0;
                next_state          = CMD55_DEL;
            end

            CMD55_DEL: begin
                next_send_cmd_req = 1'b0;
                next_state        = CMD55_WAIT;
            end

            CMD55_WAIT: begin
                if (send_cmd_rdy == 1'b1) begin
                    next_state    = CMD55_CHECK;
                    next_spi_cs_n = 1'b1;
                end
            end

            CMD55_CHECK: begin
                if ((resp_tout == 1'b1 ||
                    (resp_byte != 8'h01 && resp_byte != 8'h00)) &&
                    loop_cnt != 8'hff) begin
                    next_state = ACMD41_RETRY_DEL1;
                end
                else if (resp_tout == 1'b1 ||
                         (resp_byte != 8'h01 && resp_byte != 8'h00)) begin
                    next_state         = WT_INIT_REQ;
                    next_sd_init_error = `INIT_ACMD41_ERROR;
                end
                else begin
                    next_state = ACMD41_SEND;
                end
            end

            ACMD41_SEND: begin
                next_cmd_byte       = 8'h69;
                next_data_byte_1    = 8'h40;
                next_data_byte_2    = 8'h00;
                next_data_byte_3    = 8'h00;
                next_data_byte_4    = 8'h00;
                next_check_sum_byte = 8'hff;
                next_send_cmd_req   = 1'b1;
                next_loop_cnt       = loop_cnt + 1'b1;
                next_spi_cs_n       = 1'b0;
                next_del_cnt_1      = 10'h000;
                next_state          = ACMD41_DEL;
            end

            ACMD41_DEL: begin
                next_send_cmd_req = 1'b0;
                next_state        = ACMD41_WAIT;
            end

            ACMD41_WAIT: begin
                if (send_cmd_rdy == 1'b1) begin
                    next_state    = ACMD41_CHECK;
                    next_spi_cs_n = 1'b1;
                end
            end

            ACMD41_CHECK: begin
                if (resp_tout == 1'b0 && resp_byte == 8'h00) begin
                    next_state = INIT_DONE;
                end
                else if ((resp_tout == 1'b1 || resp_byte != 8'h01) && loop_cnt == 8'hff) begin
                    next_state         = WT_INIT_REQ;
                    next_sd_init_error = `INIT_ACMD41_ERROR;
                end
                else if (loop_cnt == 8'hff) begin
                    next_state         = WT_INIT_REQ;
                    next_sd_init_error = `INIT_ACMD41_ERROR;
                end
                else begin
                    next_state = ACMD41_RETRY_DEL1;
                end
            end

            ACMD41_RETRY_DEL1: begin
                next_del_cnt_1    = del_cnt_1 + 1'b1;
                next_del_cnt_2    = 8'h00;
                next_send_cmd_req = 1'b0;
                if (del_cnt_1 == `TWO_MS) begin
                    next_state = CMD55_SEND;
                end
                else begin
                    next_state = ACMD41_RETRY_DEL2;
                end
            end

            ACMD41_RETRY_DEL2: begin
                next_del_cnt_2 = del_cnt_2 + 1'b1;
                if (del_cnt_2 == 8'hff) begin
                    next_state = ACMD41_RETRY_DEL1;
                end
            end

            INIT_DONE: begin
                next_sd_init_rdy = 1'b1;
                next_spi_cs_n    = 1'b1;
                next_state       = WT_INIT_REQ;
            end

            default: begin
                next_state = START;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst)
            state <= START;
        else
            state <= next_state;
    end

    always @(posedge clk) begin
        if (rst) begin
            spi_clk_delay_out <= spi_clk_delay_in;
            sd_init_rdy       <= 1'b0;
            spi_cs_n          <= 1'b1;
            sd_init_error     <= `INIT_NO_ERROR;
            tx_data_out       <= 8'h00;
            tx_data_wen       <= 1'b0;
            cmd_byte          <= 8'h00;
            data_byte_1       <= 8'h00;
            data_byte_2       <= 8'h00;
            data_byte_3       <= 8'h00;
            data_byte_4       <= 8'h00;
            check_sum_byte    <= 8'h00;
            send_cmd_req      <= 1'b0;
            rx_data_rdy_clr   <= 1'b0;
            loop_cnt          <= 8'h00;
            del_cnt_1         <= 10'h000;
            del_cnt_2         <= 8'h00;
            power_wait_cnt    <= 22'd0;
`ifdef P3_SPI_SD_HISTORY_DEBUG
            p3_state_seen       <= 25'd0;
            p3_sd_init_req_seen <= 1'b0;
            p3_resp_tout_seen   <= 1'b0;
`endif
        end
        else begin
            spi_clk_delay_out <= next_spi_clk_delay_out;
            sd_init_rdy       <= next_sd_init_rdy;
            spi_cs_n          <= next_spi_cs_n;
            sd_init_error     <= next_sd_init_error;
            tx_data_out       <= next_tx_data_out;
            tx_data_wen       <= next_tx_data_wen;
            cmd_byte          <= next_cmd_byte;
            data_byte_1       <= next_data_byte_1;
            data_byte_2       <= next_data_byte_2;
            data_byte_3       <= next_data_byte_3;
            data_byte_4       <= next_data_byte_4;
            check_sum_byte    <= next_check_sum_byte;
            send_cmd_req      <= next_send_cmd_req;
            rx_data_rdy_clr   <= next_rx_data_rdy_clr;
            loop_cnt          <= next_loop_cnt;
            del_cnt_1         <= next_del_cnt_1;
            del_cnt_2         <= next_del_cnt_2;
            power_wait_cnt    <= next_power_wait_cnt;
`ifdef P3_SPI_SD_HISTORY_DEBUG
            p3_state_seen       <= p3_state_seen | p3_state_bit;
            p3_sd_init_req_seen <= p3_sd_init_req_seen | sd_init_req;
            p3_resp_tout_seen   <= p3_resp_tout_seen | resp_tout |
                                    (sd_init_error != `INIT_NO_ERROR);
`endif
        end
    end

`ifdef P3_BD_SD_INIT_ILA
`ifdef P3_SPI_SD_HISTORY_DEBUG
    assign p3_init_debug_o = {state,
                              p3_state_seen,
                              p3_sd_init_req_seen,
                              p3_resp_tout_seen};
`else
    assign p3_init_debug_o = {state,
                              cmd_byte,
                              resp_byte,
                              resp_tout,
                              send_cmd_req,
                              send_cmd_rdy,
                              sd_init_rdy,
                              spi_cs_n,
                              sd_init_error,
                              rx_data_rdy,
                              tx_data_empty,
                              tx_data_full,
                              loop_cnt[0]};
`endif
`endif

endmodule
