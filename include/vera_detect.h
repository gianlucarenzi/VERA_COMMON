#ifndef VERA_DETECT_H
#define VERA_DETECT_H

/*
 * vera_detect.h - is the VERA card there (src/common/vera_detect.c)?
 */

/* 'V' | 'X', the identifier of the card */
#define VERA_CARD_ID  ((unsigned int)0x5658)

/*
 * Select DCSEL 63 (CTRL = $7E) and check the identity bytes: $09 = 'V',
 * $0A = major version >= 47 (the FX firmware: 47.0.2 reads 'V',47,0,0,
 * 48.0.1 reads 'V',48,0,1).  An open bus cannot fake them (on the C64 IO1
 * reads what the VIC-II fetched last).  CTRL and the port 0 address are
 * left at 0.
 *
 * Returns VERA_CARD_ID when the card answers, 0 otherwise (absent, still
 * configuring after power-on, or the emulator started without it:
 * atari800 -verax16, x64sc -vera).
 */
unsigned int vera_detect(void);

/* vera_detect(), or a message on the host screen and exit(1). */
unsigned int vera_require(void);

/* Firmware version read by the last vera_detect(): major, minor, build. */
extern unsigned char vera_version[3];

#endif /* VERA_DETECT_H */
