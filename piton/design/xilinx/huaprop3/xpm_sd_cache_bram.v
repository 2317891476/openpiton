// XPM wrapper: drop-in replacement for blk_mem_gen sd_cache_bram on Versal
// Single-port RAM, 512x64, byte-write-enable, 1-cycle read latency
module sd_cache_bram (
    input  wire        clka,
    input  wire        ena,
    input  wire [7:0]  wea,
    input  wire [8:0]  addra,
    input  wire [63:0] dina,
    output wire [63:0] douta
);

xpm_memory_spram #(
    .ADDR_WIDTH_A        (9),
    .AUTO_SLEEP_TIME     (0),
    .BYTE_WRITE_WIDTH_A  (8),
    .CASCADE_HEIGHT      (0),
    .ECC_BIT_RANGE       ("7:0"),
    .ECC_MODE            ("no_ecc"),
    .ECC_TYPE            ("none"),
    .IGNORE_INIT_SYNTH   (0),
    .MEMORY_INIT_FILE    ("none"),
    .MEMORY_INIT_PARAM   ("0"),
    .MEMORY_OPTIMIZATION ("true"),
    .MEMORY_PRIMITIVE     ("block"),
    .MEMORY_SIZE         (32768),  // 512 * 64
    .MESSAGE_CONTROL     (0),
    .RAM_DECOMP          ("auto"),
    .READ_DATA_WIDTH_A   (64),
    .READ_LATENCY_A      (1),
    .READ_RESET_VALUE_A  ("0"),
    .RST_MODE_A          ("SYNC"),
    .SIM_ASSERT_CHK      (0),
    .USE_MEM_INIT        (0),
    .USE_MEM_INIT_MMI    (0),
    .WAKEUP_TIME         ("disable_sleep"),
    .WRITE_DATA_WIDTH_A  (64),
    .WRITE_MODE_A        ("read_first"),
    .WRITE_PROTECT       (1)
) xpm_mem_inst (
    .clka           (clka),
    .ena            (ena),
    .wea            (wea),
    .addra          (addra),
    .dina           (dina),
    .douta          (douta),
    .rsta           (1'b0),
    .regcea         (1'b1),
    .injectsbiterra (1'b0),
    .injectdbiterra (1'b0),
    .sbiterra       (),
    .dbiterra       (),
    .sleep          (1'b0)
);

endmodule
