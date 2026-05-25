// Vivado implementation shim for Ariane/common_cells unread.
//
// The upstream common_cells unread module intentionally has no body. Vivado
// preserves that empty leaf as a black box in this P3 project, which later
// trips opt_design DRC INBB-3. Keep a tiny real LUT sink instead.

module unread (
    input logic d_i
);

    (* KEEP = "TRUE" *) wire unread_sink;

    (* DONT_TOUCH = "TRUE" *)
    LUT1 #(
        .INIT(2'b10)
    ) unread_sink_lut (
        .I0(d_i),
        .O(unread_sink)
    );

endmodule
