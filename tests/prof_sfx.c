/* prof_sfx.c - CPU cycles of the sfx.s VSYNC callback on sim65: idle, one
 * effect, two effects at the same time (bank: tests/sfx_test.py).
 *
 *   make prof-sfx
 */
#include <stdio.h>
#include <sim65.h>
#include "sfx.h"

extern const unsigned char sfx_bank[];
void call_sfx(void);

static unsigned long cycles(void)
{
    peripherals.counter.latch = 0;
    peripherals.counter.select = COUNTER_SELECT_CLOCKCYCLE_COUNTER;
    return peripherals.counter.value32[0];
}

static unsigned long tick(void)
{
    unsigned long t0 = cycles();
    call_sfx();
    return cycles() - t0;
}

int main(void)
{
    sfx_init(sfx_bank);
    printf("idle: %lu cycles\n", tick());
    sfx_play(0);
    printf("1 effect: %lu cycles\n", tick());
    sfx_play(3);
    printf("2 effects: %lu cycles\n", tick());
    return 0;
}
