#ifndef P3_XSBENCH_MARKERS_H
#define P3_XSBENCH_MARKERS_H

#include <stdint.h>

void p3_xs_mark(const char *text);
void p3_xs_mark_u64(const char *prefix, uint64_t value);

#endif
