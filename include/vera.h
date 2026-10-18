/*
 * vera.h - the registers of the VERA card, for every libvera host.
 *
 * Only the base of the 32 registers depends on the host (see vera.inc):
 *   Atari  $D100 (PBI device space)
 *   C64    $DE00 (IO1), or $DF00 with -DVERA_BASE=0xDF00u (IO2)
 *   X16    $9F20
 * cc65 -t atari / -t c64 / -t cx16 defines __ATARI__ / __C64__ / __CX16__.
 */

#ifndef VERA_H
#define VERA_H

#ifndef VERA_BASE
#if defined(__ATARI__)
#define VERA_BASE 0xD100u
#elif defined(__C64__)
#define VERA_BASE 0xDE00u
#elif defined(__CX16__)
#define VERA_BASE 0x9F20u
#else
#error "libvera: unsupported target (cl65 -t atari, -t c64 or -t cx16)"
#endif
#endif

#define VERA_REG(n)     (*(volatile unsigned char *)(VERA_BASE + (n)))

#define VERA_ADDR_L     VERA_REG(0x00)
#define VERA_ADDR_M     VERA_REG(0x01)
#define VERA_ADDR_H     VERA_REG(0x02)
#define VERA_DATA0      VERA_REG(0x03)
#define VERA_DATA1      VERA_REG(0x04)
#define VERA_CTRL       VERA_REG(0x05)
#define VERA_IEN        VERA_REG(0x06)
#define VERA_ISR        VERA_REG(0x07)
#define VERA_IRQLINE_L  VERA_REG(0x08)  /* write: LINE IRQ line bits 7:0 */
#define VERA_SCANLINE_L VERA_REG(0x08)  /* read: current line bits 7:0 */

/* DCSEL-muxed registers at $09-$0C */
#define VERA_REG09      VERA_REG(0x09)
#define VERA_REG0A      VERA_REG(0x0A)
#define VERA_REG0B      VERA_REG(0x0B)
#define VERA_REG0C      VERA_REG(0x0C)
#define VERA_DC_VIDEO   VERA_REG(0x09)  /* DCSEL 0 */
#define VERA_DC_HSCALE  VERA_REG(0x0A)
#define VERA_DC_VSCALE  VERA_REG(0x0B)
#define VERA_DC_BORDER  VERA_REG(0x0C)
#define VERA_DC_HSTART  VERA_REG(0x09)  /* DCSEL 1 */
#define VERA_DC_HSTOP   VERA_REG(0x0A)
#define VERA_DC_VSTART  VERA_REG(0x0B)
#define VERA_DC_VSTOP   VERA_REG(0x0C)
#define VERA_FX_CTRL    VERA_REG(0x09)  /* DCSEL 2 */

#define VERA_L0_CONFIG   VERA_REG(0x0D)
#define VERA_L0_MAPBASE  VERA_REG(0x0E)
#define VERA_L0_TILEBASE VERA_REG(0x0F)
#define VERA_L0_HSCR_L   VERA_REG(0x10)
#define VERA_L0_HSCR_H   VERA_REG(0x11)
#define VERA_L0_VSCR_L   VERA_REG(0x12)
#define VERA_L0_VSCR_H   VERA_REG(0x13)
#define VERA_L1_CONFIG   VERA_REG(0x14)
#define VERA_L1_MAPBASE  VERA_REG(0x15)
#define VERA_L1_TILEBASE VERA_REG(0x16)
#define VERA_L1_HSCR_L   VERA_REG(0x17)
#define VERA_L1_HSCR_H   VERA_REG(0x18)
#define VERA_L1_VSCR_L   VERA_REG(0x19)
#define VERA_L1_VSCR_H   VERA_REG(0x1A)

#define VERA_AUDIO_CTRL VERA_REG(0x1B)
#define VERA_AUDIO_RATE VERA_REG(0x1C)
#define VERA_AUDIO_DATA VERA_REG(0x1D)
#define VERA_SPI_DATA   VERA_REG(0x1E)
#define VERA_SPI_CTRL   VERA_REG(0x1F)

/* DC_VIDEO bits */
#define VERA_VIDEO_VGA     0x01
#define VERA_VIDEO_LAYER0  0x10
#define VERA_VIDEO_LAYER1  0x20
#define VERA_VIDEO_SPRITES 0x40

/* VRAM address with auto-increment: ADDR_H = incr | bank */
#define VERA_INC0       0x00
#define VERA_INC1       0x10
#define VERA_INC2       0x20
#define VERA_INC4       0x30
#define VERA_INC8       0x40
#define VERA_INC16      0x50
#define VERA_INC32      0x60
#define VERA_INC64      0x70
#define VERA_INC128     0x80
#define VERA_INC256     0x90
#define VERA_INC512     0xA0
#define VERA_DECR       0x08            /* or'ed in: decrement */

#define VERA_PSG_BASE     0x1F9C0ul     /* 16 voices x 4 bytes */
#define VERA_PALETTE_BASE 0x1FA00ul     /* 256 x 2 bytes, GGGGBBBB 0000RRRR */
#define VERA_SPRITE_BASE  0x1FC00ul     /* 128 x 8 bytes */

/* Point data port 0 at a constant VRAM address with the given increment
 * (the compiler folds it into four stores); for a computed address use
 * vram_addr() in vmem.h. */
#define VERA_SET_ADDR(addr, inc) do { \
        VERA_CTRL = 0; \
        VERA_ADDR_L = (unsigned char)(addr); \
        VERA_ADDR_M = (unsigned char)((addr) >> 8); \
        VERA_ADDR_H = (unsigned char)((inc) | (((addr) >> 16) & 1)); \
    } while (0)

#endif /* VERA_H */
