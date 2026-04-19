#ifndef UTILS_H
#define UTILS_H

#include <stdint.h>

uint32_t utils_crc32(const uint8_t *data, uint32_t len);
void     utils_hexdump(const uint8_t *data, uint32_t len);

#endif /* UTILS_H */
