#include <stdio.h>
#include <stdint.h>
#include "utils/utils.h"

int main(void)
{
    const uint8_t msg[] = "Hello, Makefile template!";
    uint32_t crc = utils_crc32(msg, sizeof(msg) - 1);

    printf("Message : %s\n", msg);
    printf("CRC-32  : 0x%08X\n", crc);
    utils_hexdump(msg, sizeof(msg) - 1);

    return 0;
}
