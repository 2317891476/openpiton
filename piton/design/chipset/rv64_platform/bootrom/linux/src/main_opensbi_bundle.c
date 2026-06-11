#include "sd.h"
#include "uart.h"
#include <stdint.h>

#ifndef P3_OPENSBI_MAX_COMPONENTS
#define P3_OPENSBI_MAX_COMPONENTS 8
#endif

#define P3_BUNDLE_MAGIC0 0x534f3350u /* "P3OS" little-endian */
#define P3_BUNDLE_MAGIC1 0x34364942u /* "BI64" little-endian */
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

static int find_first_partition_lba(uint64_t *first_lba)
{
    uint8_t lba1_buf[512];
    uint8_t entries_buf[512];

    if (sd_copy(lba1_buf, 1, 1) != 0)
        return -1;

    p3_gpt_header_t *hdr = (p3_gpt_header_t *)lba1_buf;
    if (hdr->signature != GPT_SIGNATURE)
        return -2;

    if (hdr->size_partition_entry < sizeof(p3_gpt_entry_t))
        return -3;

    if (sd_copy(entries_buf, (uint32_t)hdr->partition_entries_lba, 1) != 0)
        return -4;

    p3_gpt_entry_t *entry = (p3_gpt_entry_t *)entries_buf;
    if (entry->first_lba == 0)
        return -5;

    *first_lba = entry->first_lba;
    return 0;
}

static int copy_component(uint64_t partition_lba, const p3_bundle_component_t *component)
{
    uint32_t blocks = ceil_blocks(component->size_bytes);

    print_uart("B68 copy ");
    print_kind(component->kind);
    print_uart(" lba=");
    print_uart_addr(partition_lba + component->offset_lba);
    print_uart(" blocks=");
    print_uart_int(blocks);
    print_uart(" dst=");
    print_uart_addr(component->load_addr);
    print_uart("\r\n");

    if (blocks == 0)
        return 0;

    return sd_copy((void *)(uintptr_t)component->load_addr,
                   (uint32_t)(partition_lba + component->offset_lba),
                   blocks);
}

int main()
{
    uint64_t partition_lba = 0;
    uint64_t header_storage[64];
    p3_bundle_header_t *header = (p3_bundle_header_t *)header_storage;

    init_uart(UART_FREQ, 115200);
    print_uart("B68 OpenSBI bundle bootrom\r\n");

    if (init_sd() != 0) {
        print_uart("B68 ERROR sd init\r\n");
        return -1;
    }

    int ret = find_first_partition_lba(&partition_lba);
    if (ret != 0) {
        print_uart("B68 ERROR gpt ");
        print_uart_int((uint32_t)(-ret));
        print_uart("\r\n");
        return ret;
    }

    print_uart("B68 boot partition lba=");
    print_uart_addr(partition_lba);
    print_uart("\r\n");

    if (sd_copy(header_storage, (uint32_t)partition_lba, 1) != 0) {
        print_uart("B68 ERROR header read\r\n");
        return -2;
    }

    if (header->magic0 != P3_BUNDLE_MAGIC0 ||
        header->magic1 != P3_BUNDLE_MAGIC1 ||
        header->version != P3_BUNDLE_VERSION ||
        header->header_size != 512 ||
        header->component_count > P3_OPENSBI_MAX_COMPONENTS) {
        print_uart("B68 ERROR bad header\r\n");
        print_uart_addr((((uint64_t)header->magic1) << 32) | header->magic0);
        print_uart("\r\n");
        return -3;
    }

    for (uint32_t i = 0; i < header->component_count; i++) {
        ret = copy_component(partition_lba, &header->components[i]);
        if (ret != 0) {
            print_uart("B68 ERROR component ");
            print_uart_int(i);
            print_uart("\r\n");
            return ret;
        }
    }

    print_uart("B68 jump fw=");
    print_uart_addr(header->entry_addr);
    print_uart(" dtb=");
    print_uart_addr(header->fdt_addr);
    print_uart("\r\n");

    return 0;
}

void handle_trap(void)
{
}
