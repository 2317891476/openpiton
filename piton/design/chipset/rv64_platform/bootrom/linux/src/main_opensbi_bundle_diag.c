#include "sd.h"
#include "uart.h"
#include <stdint.h>

#ifndef P3_OPENSBI_MAX_COMPONENTS
#define P3_OPENSBI_MAX_COMPONENTS 8
#endif

#ifndef P3_DIAG_DDR_PROBE_ADDR
#define P3_DIAG_DDR_PROBE_ADDR 0x84001000ull
#endif

#define P3_BUNDLE_MAGIC0 0x534f3350u
#define P3_BUNDLE_MAGIC1 0x34364942u
#define P3_BUNDLE_VERSION 1u
#define P3_BUNDLE_KIND_FW 1u
#define P3_BUNDLE_KIND_IMAGE 2u
#define P3_BUNDLE_KIND_DTB 3u
#define P3_BUNDLE_KIND_INITRD 4u
#define GPT_SIGNATURE 0x5452415020494645ull

typedef struct __attribute__((packed)) {
    uint32_t kind;
    uint32_t flags;
    uint64_t offset_lba;
    uint64_t size_bytes;
    uint64_t load_addr;
    uint64_t reserved;
} p3_bundle_component_t;

typedef struct __attribute__((packed)) {
    uint32_t magic0;
    uint32_t magic1;
    uint32_t version;
    uint32_t header_size;
    uint32_t component_count;
    uint32_t flags;
    uint64_t entry_addr;
    uint64_t fdt_addr;
    uint64_t reserved[4];
    p3_bundle_component_t components[P3_OPENSBI_MAX_COMPONENTS];
} p3_bundle_header_t;

typedef struct __attribute__((packed)) {
    uint64_t signature;
    uint32_t revision;
    uint32_t header_size;
    uint32_t crc_header;
    uint32_t reserved;
    uint64_t current_lba;
    uint64_t backup_lba;
    uint64_t first_usable_lba;
    uint64_t last_usable_lba;
    uint8_t disk_guid[16];
    uint64_t partition_entries_lba;
    uint32_t nr_partition_entries;
    uint32_t size_partition_entry;
    uint32_t crc_partition_entry;
} p3_gpt_header_t;

typedef struct __attribute__((packed)) {
    uint8_t partition_type_guid[16];
    uint8_t partition_guid[16];
    uint64_t first_lba;
    uint64_t last_lba;
    uint64_t attributes;
    uint8_t name[72];
} p3_gpt_entry_t;

static uint32_t ceil_blocks(uint64_t size_bytes)
{
    return (uint32_t)((size_bytes + 511ull) >> 9);
}

static void print_label64(const char *label, uint64_t value)
{
    print_uart(label);
    print_uart_addr(value);
    print_uart("\r\n");
}

static void print_kind(uint32_t kind)
{
    if (kind == P3_BUNDLE_KIND_FW)
        print_uart("fw");
    else if (kind == P3_BUNDLE_KIND_IMAGE)
        print_uart("image");
    else if (kind == P3_BUNDLE_KIND_DTB)
        print_uart("dtb");
    else if (kind == P3_BUNDLE_KIND_INITRD)
        print_uart("initrd");
    else
        print_uart("unknown");
}

static int ddr_probe(void)
{
    volatile uint64_t *p = (volatile uint64_t *)(uintptr_t)P3_DIAG_DDR_PROBE_ADDR;

    print_uart("B69 DDR probe addr=");
    print_uart_addr(P3_DIAG_DDR_PROBE_ADDR);
    print_uart("\r\n");

    p[0] = 0x1122334455667788ull;
    p[1] = 0x8877665544332211ull;
    p[2] = 0xa5a55a5adeadbeefull;
    p[3] = 0x0123456789abcdefull;
    __asm__ volatile("fence rw, rw" ::: "memory");

    if (p[0] != 0x1122334455667788ull) {
        print_uart("B69 ERROR ddr idx=00000000 got=");
        print_uart_addr(p[0]);
        print_uart("\r\n");
        return -1;
    }
    if (p[1] != 0x8877665544332211ull) {
        print_uart("B69 ERROR ddr idx=00000001 got=");
        print_uart_addr(p[1]);
        print_uart("\r\n");
        return -1;
    }
    if (p[2] != 0xa5a55a5adeadbeefull) {
        print_uart("B69 ERROR ddr idx=00000002 got=");
        print_uart_addr(p[2]);
        print_uart("\r\n");
        return -1;
    }
    if (p[3] != 0x0123456789abcdefull) {
        print_uart("B69 ERROR ddr idx=00000003 got=");
        print_uart_addr(p[3]);
        print_uart("\r\n");
        return -1;
    }

    print_uart("B69 DDR OK\r\n");
    return 0;
}

static int find_first_partition_lba(uint64_t *first_lba)
{
    uint8_t lba1_buf[512];
    uint8_t entries_buf[512];

    print_uart("B69 SD read GPT header\r\n");
    if (sd_copy(lba1_buf, 1, 1) != 0)
        return -1;

    p3_gpt_header_t *hdr = (p3_gpt_header_t *)lba1_buf;
    print_label64("B69 GPT sig=", hdr->signature);
    print_label64("B69 GPT entries_lba=", hdr->partition_entries_lba);

    if (hdr->signature != GPT_SIGNATURE)
        return -2;

    if (hdr->size_partition_entry < sizeof(p3_gpt_entry_t))
        return -3;

    print_uart("B69 SD read GPT entry\r\n");
    if (sd_copy(entries_buf, (uint32_t)hdr->partition_entries_lba, 1) != 0)
        return -4;

    p3_gpt_entry_t *entry = (p3_gpt_entry_t *)entries_buf;
    print_label64("B69 part first_lba=", entry->first_lba);
    print_label64("B69 part last_lba=", entry->last_lba);

    if (entry->first_lba == 0)
        return -5;

    *first_lba = entry->first_lba;
    return 0;
}

static int copy_component(uint64_t partition_lba, const p3_bundle_component_t *component)
{
    uint32_t blocks = ceil_blocks(component->size_bytes);

    print_uart("B69 copy ");
    print_kind(component->kind);
    print_uart(" lba=");
    print_uart_addr(partition_lba + component->offset_lba);
    print_uart(" blocks=");
    print_uart_int(blocks);
    print_uart(" dst=");
    print_uart_addr(component->load_addr);
    print_uart(" bytes=");
    print_uart_addr(component->size_bytes);
    print_uart("\r\n");

    if (blocks == 0)
        return 0;

    int ret = sd_copy((void *)(uintptr_t)component->load_addr,
                      (uint32_t)(partition_lba + component->offset_lba),
                      blocks);
    if (ret != 0)
        return ret;

    __asm__ volatile("fence rw, rw" ::: "memory");
    print_uart("B69 copied first64=");
    print_uart_addr(*(volatile uint64_t *)(uintptr_t)component->load_addr);
    print_uart("\r\n");
    return 0;
}

int main()
{
    uint64_t partition_lba = 0;
    uint64_t header_storage[64];
    p3_bundle_header_t *header = (p3_bundle_header_t *)header_storage;

    init_uart(UART_FREQ, 115200);
    print_uart("B69 OpenSBI bundle diag bootrom\r\n");

    if (ddr_probe() != 0)
        return -1;

    print_uart("B69 SD init start\r\n");
    if (init_sd() != 0) {
        print_uart("B69 ERROR sd init\r\n");
        return -2;
    }
    print_uart("B69 SD init OK\r\n");

    int ret = find_first_partition_lba(&partition_lba);
    if (ret != 0) {
        print_uart("B69 ERROR gpt ");
        print_uart_int((uint32_t)(-ret));
        print_uart("\r\n");
        return ret;
    }

    print_label64("B69 boot partition lba=", partition_lba);

    print_uart("B69 read bundle header\r\n");
    if (sd_copy(header_storage, (uint32_t)partition_lba, 1) != 0) {
        print_uart("B69 ERROR header read\r\n");
        return -3;
    }

    print_label64("B69 magic=", (((uint64_t)header->magic1) << 32) | header->magic0);
    print_label64("B69 entry=", header->entry_addr);
    print_label64("B69 fdt=", header->fdt_addr);
    print_uart("B69 components=");
    print_uart_int(header->component_count);
    print_uart("\r\n");

    if (header->magic0 != P3_BUNDLE_MAGIC0 ||
        header->magic1 != P3_BUNDLE_MAGIC1 ||
        header->version != P3_BUNDLE_VERSION ||
        header->header_size != 512 ||
        header->component_count > P3_OPENSBI_MAX_COMPONENTS) {
        print_uart("B69 ERROR bad header\r\n");
        return -4;
    }

    for (uint32_t i = 0; i < header->component_count; i++) {
        ret = copy_component(partition_lba, &header->components[i]);
        if (ret != 0) {
            print_uart("B69 ERROR component ");
            print_uart_int(i);
            print_uart("\r\n");
            return ret;
        }
    }

    print_uart("B69 releasing harts and jumping OpenSBI\r\n");
    print_label64("B69 jump fw=", header->entry_addr);
    print_label64("B69 jump dtb=", header->fdt_addr);

    return 0;
}

void handle_trap(void)
{
    print_uart("B69 TRAP\r\n");
    while (1) {
    }
}
