#include "p3_xsbench_markers.h"

#include <stddef.h>
#include <unistd.h>

static void p3_xs_write_all(const char *text, size_t length)
{
    while (length != 0) {
        ssize_t written = write(STDOUT_FILENO, text, length);

        if (written <= 0)
            return;
        text += written;
        length -= (size_t) written;
    }
}

void p3_xs_mark(const char *text)
{
    size_t length = 0;

    while (text[length] != '\0')
        length++;
    p3_xs_write_all(text, length);
}

void p3_xs_mark_u64(const char *prefix, uint64_t value)
{
    char buffer[160];
    char digits[32];
    size_t used = 0;
    size_t count = 0;

    while (prefix[used] != '\0') {
        buffer[used] = prefix[used];
        used++;
    }
    do {
        digits[count++] = (char) ('0' + value % 10);
        value /= 10;
    } while (value != 0);
    while (count != 0)
        buffer[used++] = digits[--count];
    buffer[used++] = '\n';
    p3_xs_write_all(buffer, used);
}

__attribute__((constructor(101)))
static void p3_xs_constructor_marker(void)
{
    p3_xs_mark("P3_XS M-1 constructor\n");
}
