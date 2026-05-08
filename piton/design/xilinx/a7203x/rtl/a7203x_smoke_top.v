// Minimal AX7203 board smoke test.
//
// This design intentionally avoids the OpenPiton core, DDR3, and generated IP.
// It verifies the board clock, LED pins, and USB-UART path before loading a
// larger system bitstream.

`timescale 1ns/1ps

module a7203x_smoke_top #(
    parameter integer UART_CLKS_PER_BIT = 1736,
    parameter integer START_DELAY_CYCLES = 200000,
    parameter integer LED_BASE_BIT = 24
) (
    input  wire       chipset_clk_osc_p,
    input  wire       chipset_clk_osc_n,
    input  wire       sys_rst_n,
    input  wire       uart_rx,
    output reg        uart_tx,
    output wire [4:0] leds
);

`ifdef VERILATOR
wire sys_clk = chipset_clk_osc_p;
`else
wire sys_clk;

IBUFDS #(
    .DIFF_TERM("TRUE"),
    .IBUF_LOW_PWR("FALSE"),
    .IOSTANDARD("DIFF_SSTL15")
) sys_clk_ibuf (
    .I(chipset_clk_osc_p),
    .IB(chipset_clk_osc_n),
    .O(sys_clk)
);
`endif

localparam integer UART_LAST = (UART_CLKS_PER_BIT < 1) ? 0 : UART_CLKS_PER_BIT - 1;
localparam integer MSG_LEN = 14;
localparam [3:0] MSG_LAST_INDEX = 4'd13;

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
            4'd7:  smoke_msg_byte = "S";
            4'd8:  smoke_msg_byte = "M";
            4'd9:  smoke_msg_byte = "O";
            4'd10: smoke_msg_byte = "K";
            4'd11: smoke_msg_byte = "E";
            4'd12: smoke_msg_byte = 8'h0d;
            4'd13: smoke_msg_byte = 8'h0a;
            default: smoke_msg_byte = 8'h20;
        endcase
    end
endfunction

always @(posedge sys_clk) begin
    led_counter <= led_counter + 32'd1;
end

assign leds[0] = led_counter[LED_BASE_BIT];
assign leds[1] = led_counter[LED_BASE_BIT + 1];
assign leds[2] = led_counter[LED_BASE_BIT + 2];
assign leds[3] = led_counter[LED_BASE_BIT + 3];
assign leds[4] = led_counter[LED_BASE_BIT + 4];

always @(posedge sys_clk) begin
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

                if (start_counter >= START_DELAY_CYCLES) begin
                    start_counter <= 32'd0;
                    msg_index <= 4'd0;
                    uart_shift <= smoke_msg_byte(4'd0);
                    uart_state <= UART_START;
                end else begin
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
