#ifndef VERA_IRQ_H
#define VERA_IRQ_H

/*
 * vera_irq.h - VERA IRQ hook and frame clock (src/common/vera_irq.s).
 *
 * The hook sits on the host IRQ vector (VIMIRQ on the Atari, CINV on the
 * C64) and chains to the host handler when the VERA has nothing pending.
 *
 * IRQ_n is level sensitive; for every serviced source the hook:
 *   VSYNC, LINE, SPRCOL : acknowledges it (write-1-to-clear in ISR)
 *   AUDIO FIFO LOW      : cannot be acknowledged, so it is masked in IEN
 *                         (refill the FIFO, then vera_irq_enable() again)
 * and records it in the flags returned by vera_irq_take().
 *
 * The hook touches only IEN, ISR and IRQ_LINE_L: it can interrupt code
 * that is in the middle of a VRAM access sequence.
 *
 * The frame clock is the VERA's VSYNC (VGA, 59.5 Hz), the same on every
 * host and TV standard: a game paced by vera_frame_wait() runs at the same
 * speed on a PAL or NTSC Atari and C64.
 */

#define VERA_IRQ_VSYNC   0x01
#define VERA_IRQ_LINE    0x02
#define VERA_IRQ_SPRCOL  0x04
#define VERA_IRQ_AFLOW   0x08

/* Install the hook (idempotent).  Does not enable any VERA IRQ. */
void vera_irq_install(void);

/* Disable all VERA IRQs and restore the host vector (if nobody hooked it
 * after us). */
void vera_irq_remove(void);

/* Enable / disable the VERA IRQ sources in 'mask' (VERA_IRQ_*). Stale status
 * of VSYNC/LINE/SPRCOL is cleared before enabling. */
void __fastcall__ vera_irq_enable(unsigned char mask);
void __fastcall__ vera_irq_disable(unsigned char mask);

/* Return the sources serviced since the last call and clear them (atomic). */
unsigned char vera_irq_take(void);

/* Raster line (0-524) for the LINE IRQ. */
void __fastcall__ vera_irq_set_line(unsigned int line);

/*
 * Optional callback, run in IRQ context after the sources are acknowledged
 * and after the sound driver, with A = serviced sources (VERA_IRQ_*) and
 * interrupts enabled (it is never re-entered).  It must be a plain 6502
 * routine ending in RTS (A, X and Y may be changed) that saves and restores
 * whatever VERA state it changes; do not call cc65-compiled C from it.
 * Pass 0 to remove.
 */
void __fastcall__ vera_irq_set_callback(void (*callback)(void));

/* Serviced-event counters, one per source (VSYNC, LINE, SPRCOL, AFLOW),
 * 8-bit wrap.  vera_irq_count[0] is the frame counter. */
extern volatile unsigned char vera_irq_count[4];

/* Install the hook and turn the VSYNC IRQ on: the frame clock runs. */
void vera_frame_init(void);

/* Wait for the next VERA frame.  Returns the frames gone by since the last
 * call: 1 when the game kept up, more when it dropped frames (move by that
 * many steps to keep the speed). */
unsigned char vera_frame_wait(void);

#endif /* VERA_IRQ_H */
