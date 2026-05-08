// AX7203 clocking smoke test using the same clk_mmcm IP as the OpenPiton build.

`timescale 1ns/1ps

module a7203x_mmcm_smoke_top #(
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer START_DELAY_CYCLES = 100000,
    parameter integer LED_BASE_BIT = 23,
    parameter integer LOCK_DELAY_CYCLES = 16
) (
    input  wire       chipset_clk_osc_p,
    input  wire       chipset_clk_osc_n,
    input  wire       sys_rst_n,
    input  wire       uart_rx,
    output reg        uart_tx,
    output wire [4:0] leds
);

wire chipset_clk;
wire clk_locked;

`ifdef VERILATOR
reg [15:0] sim_lock_counter = 16'd0;
reg        sim_locked = 1'b0;

assign chipset_clk = chipset_clk_osc_p;
assign clk_locked = sim_locked;

always @(posedge chipset_clk) begin
    if (!sys_rst_n) begin
        sim_lock_counter <= 16'd0;
        sim_locked <= 1'b0;
    end else if (!sim_locked) begin
        if (sim_lock_counter >= LOCK_DELAY_CYCLES[15:0]) begin
            sim_locked <= 1'b1;
        end else begin
            sim_lock_counter <= sim_lock_counter + 16'd1;
        end
    end
end
`else
wire mc_sys_clk_unused;
wire sd_sys_clk_unused;
wire chipset_passthru_clk_unused;
wire chipset_passthru_clk_n_unused;
wire net_phy_clk_unused;
wire net_axi_clk_unused;

clk_mmcm clk_mmcm (
    .clk_in1_p(chipset_clk_osc_p),
    .clk_in1_n(chipset_clk_osc_n),
    .reset(1'b0),
    .locked(clk_locked),
    .chipset_clk(chipset_clk),
    .mc_sys_clk(mc_sys_clk_unused),
    .sd_sys_clk(sd_sys_clk_unused),
    .chipset_passthru_clk(chipset_passthru_clk_unused),
    .chipset_passthru_clk_n(chipset_passthru_clk_n_unused),
    .net_phy_clk(net_phy_clk_unused),
    .net_axi_clk(net_axi_clk_unused)
);
`endif

localparam integer UART_LAST = (UART_CLKS_PER_BIT < 1) ? 0 : UART_CLKS_PER_BIT - 1;
localparam [3:0] MSG_LAST_INDEX = 4'd12;

localparam [2:0] UART_WAIT  = 3'd0;
localparam [2:0] UART_START = 3'd1;
localparam [2:0] UART_DATA  = 3'd2;
localparam [2:0] UART_STOP  = 3'd3;

reg [31:0] led_counter = 32'd0;
reg [31:0] start_counter = 32'd0;
reg [31:0] baud_counter = 32'd0;
reg [7:0]  uart_shift = 8'h00;
reg [3:0]  msg_index = 4'd0;
reg [2:0]  bit_index = 3'd0;
reg [2:0]  uart_state = UART_WAIT;

function [7:0] smoke_msg_byte;
    input [3:0] index;
    begin
        case (index)
            4'd0:  smoke_msg_byte = "A";
            4'd1:  smoke_msg_byte = "X";
            4'd2:  smoke_msg_byte = "7";
            4'd3:  smoke_msg_byte = "2";
            4'd4:  smoke_msg_byte = "0";
            4'd5:  smoke_msg_byte = "3";
            4'd6:  smoke_msg_byte = " ";
            4'd7:  smoke_msg_byte = "M";
            4'd8:  smoke_msg_byte = "M";
            4'd9:  smoke_msg_byte = "C";
            4'd10: smoke_msg_byte = "M";
            4'd11: smoke_msg_byte = 8'h0d;
            4'd12: smoke_msg_byte = 8'h0a;
            default: smoke_msg_byte = 8'h20;
        endcase
    end
endfunction

always @(posedge chipset_clk) begin
    if (!sys_rst_n) begin
        led_counter <= 32'd0;
    end else begin
        led_counter <= led_counter + 32'd1;
    end
end

assign leds[0] = led_counter[LED_BASE_BIT];
assign leds[1] = clk_locked;
assign leds[2] = sys_rst_n;
assign leds[3] = 1'b1;
assign leds[4] = led_counter[LED_BASE_BIT + 1];

always @(posedge chipset_clk) begin
    if (!sys_rst_n) begin
        uart_tx <= 1'b1;
        start_counter <= 32'd0;
        baud_counter <= 32'd0;
        uart_shift <= 8'h00;
        msg_index <= 4'd0;
        bit_index <= 3'd0;
        uart_state <= UART_WAIT;
    end else begin
        case (uart_state)
            UART_WAIT: begin
                uart_tx <= 1'b1;
                baud_counter <= 32'd0;
                bit_index <= 3'd0;

                if (clk_locked && start_counter >= START_DELAY_CYCLES) begin
                    start_counter <= 32'd0;
                    msg_index <= 4'd0;
                    uart_shift <= smoke_msg_byte(4'd0);
                    uart_state <= UART_START;
                end else if (clk_locked) begin
                    start_counter <= start_counter + 32'd1;
                end
            end

            UART_START: begin
                uart_tx <= 1'b0;
                if (baud_counter >= UART_LAST) begin
                    baud_counter <= 32'd0;
                    bit_index <= 3'd0;
                    uart_state <= UART_DATA;
                end else begin
                    baud_counter <= baud_counter + 32'd1;
                end
            end

            UART_DATA: begin
                uart_tx <= uart_shift[0];
                if (baud_counter >= UART_LAST) begin
                    baud_counter <= 32'd0;
                    if (bit_index == 3'd7) begin
                        uart_state <= UART_STOP;
                    end else begin
                        bit_index <= bit_index + 3'd1;
                        uart_shift <= {1'b0, uart_shift[7:1]};
                    end
                end else begin
                    baud_counter <= baud_counter + 32'd1;
                end
            end

            UART_STOP: begin
                uart_tx <= 1'b1;
                if (baud_counter >= UART_LAST) begin
                    baud_counter <= 32'd0;
                    if (msg_index == MSG_LAST_INDEX) begin
                        uart_state <= UART_WAIT;
                    end else begin
                        msg_index <= msg_index + 4'd1;
                        uart_shift <= smoke_msg_byte(msg_index + 4'd1);
                        bit_index <= 3'd0;
                        uart_state <= UART_START;
                    end
                end else begin
                    baud_counter <= baud_counter + 32'd1;
                end
            end

            default: begin
                uart_tx <= 1'b1;
                uart_state <= UART_WAIT;
            end
        endcase
    end
end

wire unused_inputs = uart_rx ^ chipset_clk_osc_n;

endmodule
