#include <stdio.h>
#include "system.h"

// puts rather than printf: the Nios V HAL has no small-C-library option, so
// printf drags newlib's whole format engine in and the program stops fitting
// beside the processor in a small on-chip memory.
int main(void)
{
    puts("Nios V/m alive");

    for (;;) { }

    return 0;
}
