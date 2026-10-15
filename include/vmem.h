#ifndef VMEM_H
#define VMEM_H

/*
 * vmem.h - VRAM transfer primitives (src/common/vmem.s).
 *
 * A VRAM address is passed as one unsigned long built by VRAM(): bits 16:0
 * the address, bits 23:16 the ADDR_H byte (bank in bit 0, increment in the
 * high nibble).  The transfers work on data port 0 at the address set by
 * vram_seek(); CTRL is left at 0.
 *
 *   vram_seek(VRAM(0x1FA00ul, VERA_INC1));      palette entry 0
 *   vram_write(pal, 32);
 */

#include "vera.h"

#define VRAM(addr, inc) ((unsigned long)(addr) | ((unsigned long)(inc) << 16))

/* Port 0 (vram_seek) / port 1 (vram_seek1) at a VRAM() address. */
void __fastcall__ vram_seek(unsigned long vaddr);
void __fastcall__ vram_seek1(unsigned long vaddr);

/* n bytes RAM -> VRAM / VRAM -> RAM through DATA0 (~11 cycles a byte). */
void __fastcall__ vram_write(const void *src, unsigned n);
void __fastcall__ vram_read(void *dst, unsigned n);

/* n bytes of value through DATA0 (~5 cycles a byte). */
void __fastcall__ vram_fill(unsigned char value, unsigned n);

/* 4 * nquads bytes of value through the FX 32 bit write cache (~1.3 cycles
 * a byte).  Port 0 must be 4 byte aligned with increment 4:
 *   vram_seek(VRAM(0, VERA_INC4)); vram_fill32(0, 320u * 240u / 4); */
void __fastcall__ vram_fill32(unsigned char value, unsigned nquads);

/* n bytes VRAM -> VRAM: DATA1 (vram_seek1) to DATA0 (vram_seek). */
void __fastcall__ vram_copy(unsigned n);

/* Palette: count entries (2 bytes each, GGGGBBBB 0000RRRR) from rgb, from
 * entry first on. */
#define vera_palette(first, rgb, count) do { \
        vram_seek(VRAM(VERA_PALETTE_BASE + 2u * (first), VERA_INC1)); \
        vram_write((rgb), 2u * (count)); \
    } while (0)

#endif /* VMEM_H */
