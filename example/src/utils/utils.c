#include "utils.h"
#include <stdio.h>

uint32_t utils_crc32(const uint8_t *data, uint32_t len)
{
    uint32_t crc = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++)
            crc = (crc & 1) ? (crc >> 1) ^ 0xEDB88320u : (crc >> 1);
    }
    return ~crc;
}

void utils_hexdump(const uint8_t *data, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++) {
        if (i % 16 == 0) printf("\n  %04x: ", i);
        printf("%02x ", data[i]);
    }
    printf("\n");
}
