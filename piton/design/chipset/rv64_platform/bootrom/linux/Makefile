UART_FREQ ?= 30000000
MAX_HARTS ?= 1
PITON_SIFIVE_UART ?= 0
BOOTROM_MODE ?= normal
CROSSCOMPILE ?= riscv64-unknown-elf-
CC = ${CROSSCOMPILE}gcc
PYTHON=python3

CFLAGS = -DMAX_HARTS=$(MAX_HARTS) -DUART_FREQ=$(UART_FREQ) -Os -ggdb -march=rv64imac -mabi=lp64 -Wall -mcmodel=medany -mexplicit-relocs
ifeq ($(PITON_SIFIVE_UART),1)
CFLAGS += -DPITON_SIFIVE_UART
endif
CCASFLAGS = -mcmodel=medany -mexplicit-relocs
LDFLAGS = -nostdlib -nodefaultlibs -nostartfiles

INCLUDES = -I./ -I./src

ifeq ($(BOOTROM_MODE),asm_uart)
SRCS_C =
SRCS_ASM = startup_asm_uart.S
else ifeq ($(BOOTROM_MODE),asm_uart16550)
SRCS_C =
SRCS_ASM = startup_asm_uart16550.S
else ifeq ($(BOOTROM_MODE),asm_uart16550_ddrprobe)
SRCS_C =
SRCS_ASM = startup_asm_uart16550_ddrprobe.S
else ifeq ($(BOOTROM_MODE),asm_uart16550_sdprobe)
SRCS_C =
SRCS_ASM = startup_asm_uart16550_sdprobe.S
else ifeq ($(BOOTROM_MODE),sd_smoke)
SRCS_C = src/main_sd_smoke.c src/uart.c
SRCS_ASM = startup.S
else
SRCS_C = src/main.c src/uart.c src/spi.c src/sd.c src/gpt.c
SRCS_ASM = startup.S
endif
OBJS_C = $(SRCS_C:.c=.o)
OBJS_S = $(SRCS_ASM:.S=.o)

MAIN = bootrom_linux.elf
MAIN_BIN = $(MAIN:.elf=.bin)
MAIN_IMG = $(MAIN:.elf=.img)
MAIN_SV = $(MAIN:.elf=.sv)

#.PHONY: clean

$(MAIN): rv64_platform.dtb $(OBJS_C) $(OBJS_S) linker.lds
	$(CC) $(CFLAGS) $(LDFLAGS) $(INCLUDES) -Tlinker.lds $(OBJS_S) $(OBJS_C) -o $(MAIN)
	@echo "LD    >= $(MAIN)"

%.img: %.bin
	dd if=$< of=$@ bs=128 

%.bin: %.elf
	$(CROSSCOMPILE)objcopy -O binary $< $@

%.o: %.c
	@echo "MAX_HARTS = $(MAX_HARTS)"
	@$(CC) $(CFLAGS) $(INCLUDES) -c $<  -o $@ 
	@echo "CC    <= $<"

%.o: %.S
	@echo "MAX_HARTS = $(MAX_HARTS)"
	@$(CC) $(CFLAGS) $(CCASFLAGS) $(INCLUDES) -c $<  -o $@ 
	@echo "CC    <= $<"

rv64_platform.dts: FORCE
	$(PYTHON) ${DV_ROOT}/tools/bin/riscvlib.py

%.dtb: %.dts
	dtc -I dts $< -O dtb -o $@

%.sv: %.img
	$(PYTHON) ./gen_rom.py $<
	@echo "PYTHON >= $(MAIN_SV)"

clean:
	$(RM) $(OBJS_C) $(OBJS_S) src/main_sd_smoke.o startup_asm_uart.o startup_asm_uart16550.o startup_asm_uart16550_ddrprobe.o startup_asm_uart16550_sdprobe.o $(MAIN) $(MAIN_BIN) $(MAIN_IMG) *.dtb

all: $(MAIN) $(MAIN_BIN) $(MAIN_IMG) $(MAIN_SV)
	@echo "zero stage bootloader has been compiled!"

FORCE:

# DO NOT DELETE THIS LINE -- make depend needs it
