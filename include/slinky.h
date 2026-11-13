#ifndef SLINKY_H
#define SLINKY_H

/*
 * slinky.h - Apple II: a RAM card compatible with the Apple II Memory
 * Expansion Card ("Slinky"), such as the 256 KB of the VERA Module RBL-A2
 * (VERA + Slinky RAM disk in one slot), as a store to copy to and from the
 * main RAM (src/apple2/slinky.s).
 *
 * The card is not a memory window: $C0n0-$C0n2 hold a 24-bit address (bits
 * 0-7, 8-15, 16-23; $C0n2 reads with $F0 ORed in) and $C0n3 reads or writes
 * the byte there, then the address goes up by one.  The memory repeats
 * after its size (256 KB on the RBL-A2).  Every access goes through
 * (zp,X): an indexed store would make a dummy read of $C0n3 first on an
 * NMOS 6502 and skip a byte.
 *
 * The RBL-A2 formats its 256 KB as the ProDOS volume /SLINKY at power-on and
 * never clears it afterwards: a program that writes there overwrites that
 * volume (ProDOS sees it again only after the next format).  slinky_open
 * puts back the bytes its size test touches.
 *
 * Not reentrant: do not call these from an interrupt while the main program
 * uses them (the card has one address counter).
 */

#if defined(__APPLE2__)

/* the slot (1-7) of a VERA Module RBL-A2 ("VERAS" at $CnF0, found by reads
 * only), 0 = none */
unsigned char slinky_find(void);

/* use the Slinky card in slot (1-7): checks that its address registers keep
 * what is written, then measures its size.  Returns the size in 64 KB units
 * (4 = 256 KB, 16 = 1 MB or more), 0 = no card there (nothing else works
 * then).  Writes $C0n0-$C0n3 of that slot: only for a slot known to hold
 * such a card (slinky_find, or the user's choice) - slot 6 is usually the
 * Disk II, whose $C0E0-$C0E3 move the drive head. */
unsigned char __fastcall__ slinky_open(unsigned char slot);

/* the address of the next read / write (0 - size-1; it wraps at the size) */
void __fastcall__ slinky_seek(unsigned long addr);

/* n bytes from the card into dst / from src onto the card, from the current
 * address on (it goes up by n).  ~17 cycles a byte. */
void __fastcall__ slinky_read(void *dst, unsigned n);
void __fastcall__ slinky_write(const void *src, unsigned n);

#endif
#endif
