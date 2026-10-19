/* prof_pcm.c - CPU cycles of pcm.s on sim65: pcm_play (the first fill of
 * the FIFO) and the VSYNC callback, frame after frame, until a 5494 byte
 * sample at AUDIO_RATE 16 (6104 Hz) is all in the FIFO.
 *
 *   make prof-pcm
 */
#include <stdio.h>
#include <sim65.h>
#include "pcm.h"

/* sim65: the VERA registers are RAM; AUDIO_CTRL ($DE1B) must read "FIFO not
   full" (it would read back what pcm_play wrote) */
#define AUDIO_CTRL (*(volatile unsigned char *)0xDE1B)

void call_tick(void);
unsigned char tick_on(void);

static unsigned long cycles(void)
{
    peripherals.counter.latch = 0;
    peripherals.counter.select = COUNTER_SELECT_CLOCKCYCLE_COUNTER;
    return peripherals.counter.value32[0];
}

int main(void)
{
    static pcm_sound s;
    unsigned long t0, t, sum = 0, max = 0, play;
    unsigned frames = 0;

    s.vram = 0x10000ul;
    s.len = 5494;
    s.rate = 16;
    AUDIO_CTRL = 0;
    t0 = cycles();
    pcm_play(&s);
    play = cycles() - t0;
    while (tick_on()) {
        AUDIO_CTRL = 0;
        t0 = cycles();
        call_tick();
        t = cycles() - t0;
        sum += t;
        if (t > max) max = t;
        ++frames;
    }
    printf("pcm_play: %lu cycles\n", play);
    printf("callback: %u frames, avg %lu max %lu cycles (C64 PAL frame: 16553)\n",
           frames, sum / frames, max);
    return 0;
}
