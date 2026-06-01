// p3_sd_dual_probe_top.v - Standalone P3 SD pin/protocol probe.
//
// The design uses a small RTL command engine plus a BD-owned ILA. It does
// not instantiate OpenPiton, DDR, bootrom, or the native SD controller.

module p3_sd_dual_probe_top (
    input  wire        diff_sysclock_clk_p,
    input  wire        diff_sysclock_clk_n,
    input  wire        reset,

    output wire        sd_ref_clk,
    inout  wire        sd_ref_cmd,
    inout  wire [3:0]  sd_ref_dat,
    output wire        sd_ref_vsd_en,
    output wire        sd_ref_sel,
    output wire        sd_ref_resetn,

    output wire        sd_phc3_clk,
    inout  wire        sd_phc3_cmd,
    inout  wire [3:0]  sd_phc3_dat,
    output wire        sd_phc3_vsd_en,
    output wire        sd_phc3_sel,
    output wire        sd_phc3_resetn,

    input  wire        sd_cd
);
    wire        probe_clk;
    wire        probe_aresetn;
    wire [31:0] dbg_status;
    wire [63:0] dbg_bus0;
    wire [63:0] dbg_bus1;
    wire [63:0] dbg_summary;

    p3_sd_probe_bd_wrapper u_bd (
        .diff_sysclock_clk_p (diff_sysclock_clk_p),
        .diff_sysclock_clk_n (diff_sysclock_clk_n),
        .reset               (reset),
        .probe_clk_o         (probe_clk),
        .probe_aresetn_o     (probe_aresetn),
        .p3_sd_status_i      (dbg_status),
        .p3_sd_bus0_i        (dbg_bus0),
        .p3_sd_bus1_i        (dbg_bus1),
        .p3_sd_summary_i     (dbg_summary)
    );

    p3_sd_dual_probe_engine u_probe (
        .clk              (probe_clk),
        .rst_n            (probe_aresetn),
        .sd_cd            (sd_cd),

        .sd_ref_clk       (sd_ref_clk),
        .sd_ref_cmd       (sd_ref_cmd),
        .sd_ref_dat       (sd_ref_dat),
        .sd_ref_vsd_en    (sd_ref_vsd_en),
        .sd_ref_sel       (sd_ref_sel),
        .sd_ref_resetn    (sd_ref_resetn),

        .sd_phc3_clk      (sd_phc3_clk),
        .sd_phc3_cmd      (sd_phc3_cmd),
        .sd_phc3_dat      (sd_phc3_dat),
        .sd_phc3_vsd_en   (sd_phc3_vsd_en),
        .sd_phc3_sel      (sd_phc3_sel),
        .sd_phc3_resetn   (sd_phc3_resetn),

        .dbg_status       (dbg_status),
        .dbg_bus0         (dbg_bus0),
        .dbg_bus1         (dbg_bus1),
        .dbg_summary      (dbg_summary)
    );
endmodule

module p3_sd_dual_probe_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sd_cd,

    output wire        sd_ref_clk,
    inout  wire        sd_ref_cmd,
    inout  wire [3:0]  sd_ref_dat,
    output wire        sd_ref_vsd_en,
    output wire        sd_ref_sel,
    output wire        sd_ref_resetn,

    output wire        sd_phc3_clk,
    inout  wire        sd_phc3_cmd,
    inout  wire [3:0]  sd_phc3_dat,
    output wire        sd_phc3_vsd_en,
    output wire        sd_phc3_sel,
    output wire        sd_phc3_resetn,

    output wire [31:0] dbg_status,
    output wire [63:0] dbg_bus0,
    output wire [63:0] dbg_bus1,
    output wire [63:0] dbg_summary
);
    localparam integer SD_HALF_DIV   = 37;        // ~405 kHz at 30 MHz.
    localparam integer POWER_WAIT    = 3000000;   // 100 ms at 30 MHz.
    localparam integer RESPONSE_BITS = 8192;

    localparam [7:0] ST_IDLE           = 8'h00;
    localparam [7:0] ST_POWER_WAIT     = 8'h01;
    localparam [7:0] ST_IDLE_CLOCKS    = 8'h02;
    localparam [7:0] ST_CMD_LOAD       = 8'h03;
    localparam [7:0] ST_CMD_LOW        = 8'h04;
    localparam [7:0] ST_CMD_HIGH       = 8'h05;
    localparam [7:0] ST_SPI_RESP_LOW   = 8'h10;
    localparam [7:0] ST_SPI_RESP_HIGH  = 8'h11;
    localparam [7:0] ST_NATIVE_WAIT_L  = 8'h20;
    localparam [7:0] ST_NATIVE_WAIT_H  = 8'h21;
    localparam [7:0] ST_RECORD         = 8'he0;
    localparam [7:0] ST_ALL_DONE       = 8'he1;
    localparam [7:0] ST_PASS           = 8'hf0;
    localparam [7:0] ST_FAIL           = 8'hf1;

    reg         pin_sel_q;
    reg         proto_sel_q;
    reg  [1:0]  combo_index;
    reg         all_done;
    reg  [3:0]  combo_done;
    reg  [3:0]  combo_pass;
    reg  [3:0]  combo_fail;
    reg  [3:0]  combo_timeout;
    reg  [3:0]  combo_resp_seen;
    reg  [31:0] combo_fail_code;

    reg  [7:0]  state;
    reg  [7:0]  fail_code;
    reg         busy;
    reg         done;
    reg         pass;
    reg         fail;
    reg         timeout_seen;
    reg         start_seen;
    reg         spi_miso_seen_low;
    reg         native_cmd_resp_seen;

    reg         sd_clk_o;
    reg         cmd_o;
    reg         cmd_oe;
    reg  [3:0]  dat_o;
    reg  [3:0]  dat_oe;

    wire        active_ref  = (pin_sel_q == 1'b0);
    wire        active_phc3 = (pin_sel_q == 1'b1);
    wire        drive_sd    = !all_done && (busy || state != ST_IDLE);

    assign sd_ref_clk    = active_ref  ? sd_clk_o : 1'b0;
    assign sd_phc3_clk   = active_phc3 ? sd_clk_o : 1'b0;
    assign sd_ref_cmd    = (active_ref  && cmd_oe) ? cmd_o : 1'bz;
    assign sd_phc3_cmd   = (active_phc3 && cmd_oe) ? cmd_o : 1'bz;
    assign sd_ref_dat[0] = (active_ref  && dat_oe[0]) ? dat_o[0] : 1'bz;
    assign sd_ref_dat[1] = (active_ref  && dat_oe[1]) ? dat_o[1] : 1'bz;
    assign sd_ref_dat[2] = (active_ref  && dat_oe[2]) ? dat_o[2] : 1'bz;
    assign sd_ref_dat[3] = (active_ref  && dat_oe[3]) ? dat_o[3] : 1'bz;
    assign sd_phc3_dat[0] = (active_phc3 && dat_oe[0]) ? dat_o[0] : 1'bz;
    assign sd_phc3_dat[1] = (active_phc3 && dat_oe[1]) ? dat_o[1] : 1'bz;
    assign sd_phc3_dat[2] = (active_phc3 && dat_oe[2]) ? dat_o[2] : 1'bz;
    assign sd_phc3_dat[3] = (active_phc3 && dat_oe[3]) ? dat_o[3] : 1'bz;

    assign sd_ref_vsd_en   = active_ref  ? drive_sd : 1'b0;
    assign sd_phc3_vsd_en  = active_phc3 ? drive_sd : 1'b0;
    assign sd_ref_sel      = 1'b0; // 3.3 V selection for the SD daughter card side.
    assign sd_phc3_sel     = 1'b0;
    assign sd_ref_resetn   = active_ref  ? drive_sd : 1'b0;
    assign sd_phc3_resetn  = active_phc3 ? drive_sd : 1'b0;

    wire        cmd_i = active_ref ? sd_ref_cmd : sd_phc3_cmd;
    wire [3:0]  dat_i = active_ref ? sd_ref_dat : sd_phc3_dat;

    reg  [31:0] wait_ctr;
    reg  [15:0] idle_edges;
    reg  [47:0] cmd_shift;
    reg  [5:0]  bit_count;
    reg  [15:0] response_timeout;
    reg  [7:0]  response_byte;
    reg  [2:0]  response_bit_count;
    reg  [39:0] response_shift;
    reg  [15:0] clk_toggle_count;
    reg  [7:0]  command_index;

    always @(posedge clk) begin
        if (!rst_n) begin
            pin_sel_q            <= 1'b0;
            proto_sel_q          <= 1'b0;
            combo_index          <= 2'd0;
            all_done             <= 1'b0;
            combo_done           <= 4'h0;
            combo_pass           <= 4'h0;
            combo_fail           <= 4'h0;
            combo_timeout        <= 4'h0;
            combo_resp_seen      <= 4'h0;
            combo_fail_code      <= 32'h0;
            state                <= ST_IDLE;
            fail_code            <= 8'h00;
            busy                 <= 1'b0;
            done                 <= 1'b0;
            pass                 <= 1'b0;
            fail                 <= 1'b0;
            timeout_seen         <= 1'b0;
            start_seen           <= 1'b0;
            spi_miso_seen_low    <= 1'b0;
            native_cmd_resp_seen <= 1'b0;
            sd_clk_o             <= 1'b0;
            cmd_o                <= 1'b1;
            cmd_oe               <= 1'b0;
            dat_o                <= 4'hf;
            dat_oe               <= 4'h0;
            wait_ctr             <= 32'd0;
            idle_edges           <= 16'd0;
            cmd_shift            <= 48'h0;
            bit_count            <= 6'd0;
            response_timeout     <= 16'd0;
            response_byte        <= 8'hff;
            response_bit_count   <= 3'd0;
            response_shift       <= 40'h0;
            clk_toggle_count     <= 16'd0;
            command_index        <= 8'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    sd_clk_o <= 1'b0;
                    cmd_o <= 1'b1;
                    cmd_oe <= 1'b0;
                    dat_o <= 4'hf;
                    dat_oe <= 4'h0;
                    if (!all_done) begin
                        pin_sel_q <= combo_index[1];
                        proto_sel_q <= combo_index[0];
                        busy <= 1'b1;
                        done <= 1'b0;
                        pass <= 1'b0;
                        fail <= 1'b0;
                        fail_code <= 8'h00;
                        timeout_seen <= 1'b0;
                        start_seen <= 1'b1;
                        spi_miso_seen_low <= 1'b0;
                        native_cmd_resp_seen <= 1'b0;
                        response_shift <= 40'h0;
                        response_byte <= 8'hff;
                        response_bit_count <= 3'd0;
                        clk_toggle_count <= 16'd0;
                        wait_ctr <= POWER_WAIT;
                        state <= ST_POWER_WAIT;
                    end
                end

                ST_POWER_WAIT: begin
                    cmd_o <= 1'b1;
                    cmd_oe <= (proto_sel_q == 1'b0);
                    dat_o <= 4'hf;
                    dat_oe <= (proto_sel_q == 1'b0) ? 4'b1000 : 4'h0;
                    if (wait_ctr != 0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        idle_edges <= 16'd0;
                        wait_ctr <= SD_HALF_DIV - 1;
                        state <= ST_IDLE_CLOCKS;
                    end
                end

                ST_IDLE_CLOCKS: begin
                    cmd_o <= 1'b1;
                    cmd_oe <= (proto_sel_q == 1'b0);
                    dat_o <= 4'hf;
                    dat_oe <= (proto_sel_q == 1'b0) ? 4'b1000 : 4'h0;
                    if (wait_ctr != 0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        wait_ctr <= SD_HALF_DIV - 1;
                        sd_clk_o <= ~sd_clk_o;
                        clk_toggle_count <= clk_toggle_count + 1'b1;
                        idle_edges <= idle_edges + 1'b1;
                        if (idle_edges >= 16'd159 && sd_clk_o == 1'b1) begin
                            command_index <= 8'd0;
                            state <= ST_CMD_LOAD;
                        end
                    end
                end

                ST_CMD_LOAD: begin
                    sd_clk_o <= 1'b0;
                    bit_count <= 6'd48;
                    wait_ctr <= SD_HALF_DIV - 1;
                    if (proto_sel_q == 1'b0) begin
                        dat_o[3] <= 1'b0; // SPI CS asserted on SD DAT3.
                        dat_oe <= 4'b1000;
                        cmd_oe <= 1'b1;   // SPI MOSI on SD CMD.
                        if (command_index == 8'd0) begin
                            cmd_shift <= 48'h400000000095; // CMD0
                        end else begin
                            cmd_shift <= 48'h48000001aa87; // CMD8
                        end
                    end else begin
                        dat_oe <= 4'h0;
                        cmd_oe <= 1'b1;
                        if (command_index == 8'd0) begin
                            cmd_shift <= 48'h400000000095; // CMD0
                        end else if (command_index == 8'd1) begin
                            cmd_shift <= 48'h48000001aa87; // CMD8
                        end else begin
                            cmd_shift <= 48'h770000000065; // CMD55
                        end
                    end
                    state <= ST_CMD_LOW;
                end

                ST_CMD_LOW: begin
                    if (wait_ctr != 0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        sd_clk_o <= 1'b1;
                        clk_toggle_count <= clk_toggle_count + 1'b1;
                        cmd_o <= cmd_shift[47];
                        wait_ctr <= SD_HALF_DIV - 1;
                        state <= ST_CMD_HIGH;
                    end
                end

                ST_CMD_HIGH: begin
                    if (wait_ctr != 0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        sd_clk_o <= 1'b0;
                        clk_toggle_count <= clk_toggle_count + 1'b1;
                        cmd_shift <= {cmd_shift[46:0], 1'b1};
                        if (bit_count > 1) begin
                            bit_count <= bit_count - 1'b1;
                            wait_ctr <= SD_HALF_DIV - 1;
                            state <= ST_CMD_LOW;
                        end else begin
                            response_timeout <= RESPONSE_BITS[15:0];
                            response_bit_count <= 3'd0;
                            response_byte <= 8'hff;
                            wait_ctr <= SD_HALF_DIV - 1;
                            if (proto_sel_q == 1'b0) begin
                                cmd_o <= 1'b1;
                                cmd_oe <= 1'b1;
                                state <= ST_SPI_RESP_LOW;
                            end else if (command_index == 8'd0) begin
                                cmd_oe <= 1'b0;
                                command_index <= 8'd1;
                                state <= ST_CMD_LOAD;
                            end else begin
                                cmd_oe <= 1'b0;
                                state <= ST_NATIVE_WAIT_L;
                            end
                        end
                    end
                end

                ST_SPI_RESP_LOW: begin
                    if (wait_ctr != 0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        sd_clk_o <= 1'b1;
                        clk_toggle_count <= clk_toggle_count + 1'b1;
                        wait_ctr <= SD_HALF_DIV - 1;
                        state <= ST_SPI_RESP_HIGH;
                    end
                end

                ST_SPI_RESP_HIGH: begin
                    if (wait_ctr != 0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        sd_clk_o <= 1'b0;
                        clk_toggle_count <= clk_toggle_count + 1'b1;
                        response_byte <= {response_byte[6:0], dat_i[0]};
                        response_shift <= {response_shift[38:0], dat_i[0]};
                        response_bit_count <= response_bit_count + 1'b1;
                        if (!dat_i[0]) begin
                            spi_miso_seen_low <= 1'b1;
                        end
                        if (response_bit_count == 3'd7) begin
                            if ({response_byte[6:0], dat_i[0]} != 8'hff) begin
                                pass <= 1'b1;
                                done <= 1'b1;
                                busy <= 1'b0;
                                dat_o[3] <= 1'b1;
                                state <= ST_PASS;
                            end else if (response_timeout == 16'd0) begin
                                if (spi_miso_seen_low || command_index == 8'd0) begin
                                    command_index <= 8'd1;
                                    response_timeout <= RESPONSE_BITS[15:0];
                                    state <= ST_CMD_LOAD;
                                end else begin
                                    fail <= 1'b1;
                                    done <= 1'b1;
                                    busy <= 1'b0;
                                    timeout_seen <= 1'b1;
                                    fail_code <= 8'h11;
                                    dat_o[3] <= 1'b1;
                                    state <= ST_FAIL;
                                end
                            end else begin
                                response_timeout <= response_timeout - 1'b1;
                                wait_ctr <= SD_HALF_DIV - 1;
                                state <= ST_SPI_RESP_LOW;
                            end
                        end else begin
                            response_timeout <= response_timeout - 1'b1;
                            wait_ctr <= SD_HALF_DIV - 1;
                            state <= ST_SPI_RESP_LOW;
                        end
                    end
                end

                ST_NATIVE_WAIT_L: begin
                    if (wait_ctr != 0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        sd_clk_o <= 1'b1;
                        clk_toggle_count <= clk_toggle_count + 1'b1;
                        wait_ctr <= SD_HALF_DIV - 1;
                        state <= ST_NATIVE_WAIT_H;
                    end
                end

                ST_NATIVE_WAIT_H: begin
                    if (wait_ctr != 0) begin
                        wait_ctr <= wait_ctr - 1'b1;
                    end else begin
                        sd_clk_o <= 1'b0;
                        clk_toggle_count <= clk_toggle_count + 1'b1;
                        response_shift <= {response_shift[38:0], cmd_i};
                        if (!cmd_i) begin
                            native_cmd_resp_seen <= 1'b1;
                            pass <= 1'b1;
                            done <= 1'b1;
                            busy <= 1'b0;
                            state <= ST_PASS;
                        end else if (response_timeout == 16'd0) begin
                            if (command_index < 8'd2) begin
                                command_index <= command_index + 1'b1;
                                response_timeout <= RESPONSE_BITS[15:0];
                                state <= ST_CMD_LOAD;
                            end else begin
                                fail <= 1'b1;
                                done <= 1'b1;
                                busy <= 1'b0;
                                timeout_seen <= 1'b1;
                                fail_code <= 8'h21;
                                state <= ST_FAIL;
                            end
                        end else begin
                            response_timeout <= response_timeout - 1'b1;
                            wait_ctr <= SD_HALF_DIV - 1;
                            state <= ST_NATIVE_WAIT_L;
                        end
                    end
                end

                ST_PASS: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    pass <= 1'b1;
                    fail <= 1'b0;
                    sd_clk_o <= 1'b0;
                    cmd_o <= 1'b1;
                    cmd_oe <= (proto_sel_q == 1'b0);
                    dat_o <= 4'hf;
                    dat_oe <= (proto_sel_q == 1'b0) ? 4'b1000 : 4'h0;
                    state <= ST_RECORD;
                end

                ST_FAIL: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    pass <= 1'b0;
                    fail <= 1'b1;
                    sd_clk_o <= 1'b0;
                    cmd_o <= 1'b1;
                    cmd_oe <= (proto_sel_q == 1'b0);
                    dat_o <= 4'hf;
                    dat_oe <= (proto_sel_q == 1'b0) ? 4'b1000 : 4'h0;
                    state <= ST_RECORD;
                end

                ST_RECORD: begin
                    combo_done[combo_index] <= 1'b1;
                    combo_pass[combo_index] <= pass;
                    combo_fail[combo_index] <= fail;
                    combo_timeout[combo_index] <= timeout_seen;
                    combo_resp_seen[combo_index] <= spi_miso_seen_low | native_cmd_resp_seen;
                    case (combo_index)
                        2'd0: combo_fail_code[7:0]   <= fail_code;
                        2'd1: combo_fail_code[15:8]  <= fail_code;
                        2'd2: combo_fail_code[23:16] <= fail_code;
                        2'd3: combo_fail_code[31:24] <= fail_code;
                    endcase
                    sd_clk_o <= 1'b0;
                    cmd_o <= 1'b1;
                    cmd_oe <= 1'b0;
                    dat_o <= 4'hf;
                    dat_oe <= 4'h0;
                    if (combo_index == 2'd3) begin
                        all_done <= 1'b1;
                        state <= ST_ALL_DONE;
                    end else begin
                        combo_index <= combo_index + 1'b1;
                        state <= ST_IDLE;
                    end
                end

                ST_ALL_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    sd_clk_o <= 1'b0;
                    cmd_o <= 1'b1;
                    cmd_oe <= 1'b0;
                    dat_o <= 4'hf;
                    dat_oe <= 4'h0;
                end

                default: begin
                    fail <= 1'b1;
                    done <= 1'b1;
                    busy <= 1'b0;
                    fail_code <= 8'hee;
                    state <= ST_FAIL;
                end
            endcase
        end
    end

    assign dbg_status = {fail_code,
                         2'h0,
                         all_done,
                         drive_sd,
                         sd_cd,
                         timeout_seen,
                         native_cmd_resp_seen,
                         spi_miso_seen_low,
                         proto_sel_q,
                         pin_sel_q,
                         fail,
                         pass,
                         done,
                         busy,
                         state};

    assign dbg_bus0 = {8'h56,
                       response_byte,
                       sd_clk_o,
                       cmd_oe,
                       cmd_o,
                       cmd_i,
                       dat_oe,
                       dat_o,
                       dat_i,
                       clk_toggle_count,
                       response_timeout};

    assign dbg_bus1 = {command_index,
                       bit_count,
                       response_bit_count,
                       5'h0,
                       response_shift};

    assign dbg_summary = {8'h56,
                          all_done,
                          3'h0,
                          combo_done,
                          combo_pass,
                          combo_fail,
                          combo_timeout,
                          combo_resp_seen,
                          combo_fail_code};
endmodule
