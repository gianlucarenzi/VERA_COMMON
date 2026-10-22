/*
 * vera_detect.c - is the VERA card there (see vera_detect.h)?
 */

#include <conio.h>
#include <stdlib.h>

#include "vera.h"
#include "vera_detect.h"

unsigned char vera_version[3];

unsigned int vera_detect(void)
{
    unsigned char v;

    VERA_CTRL = 0x7E;                   /* DCSEL 63 */
    v = VERA_REG09;
    vera_version[0] = VERA_REG0A;
    vera_version[1] = VERA_REG0B;
    vera_version[2] = VERA_REG0C;
    VERA_CTRL = 0;
    /* 'V' in ASCII (not 'V': PETSCII on the C64) */
    if (v != 0x56 || vera_version[0] < 47)
        return 0;

    VERA_ADDR_L = 0;
    VERA_ADDR_M = 0;
    VERA_ADDR_H = 0;
    return VERA_CARD_ID;
}

unsigned int vera_require(void)
{
    unsigned int id = vera_detect();

    if (!id) {
#if defined(__ATARI__)
        cputs("VERA card not found at $D100.\r\n"
              "atari800 -verax16 -verax16-rom ...\r\n");
#elif defined(__CX16__)
        cputs("vera not found at $9f20.\r\n");
#elif defined(__APPLE2__)
        cputs("VERA card not found in slot ");
        cputc('0' + ((VERA_BASE >> 8) & 7));
        cputs(".\r\nA2_VERA_SLOT=n a2emu ...\r\n");
#else
        cputs("vera card not found (io1/io2).\r\n"
              "x64sc -vera\r\n");
#endif
        exit(1);
    }
    return id;
}
