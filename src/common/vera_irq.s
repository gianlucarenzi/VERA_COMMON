; ============================================================================
; vera_irq.s - VERA IRQ hook and frame clock, the same on every host
;
; See vera_irq.h for the C interface.
;
; The hook sits on the host IRQ vector (plat.inc: VIMIRQ on the Atari, CINV
; on the C64).  The VERA /IRQ is wired-OR with the host's own sources (POKEY
; on the Atari, CIA 1 on the C64); the VERA registers are always readable,
; so the hook looks at ISR & IEN itself: when the VERA has a source pending
; it is serviced and the IRQ ends there, otherwise the hook chains to the
; previous vector.  An IRQ of both is taken twice in a row, once for each.
;
; The VERA frame clock: VSYNC comes from the VERA's own VGA timing, 59.5 Hz
; on every host (asynchronous to the Atari's / C64's 50 or 60 Hz).  Games
; that time themselves on vera_frame_wait() run at the same speed on PAL
; and NTSC Ataris and C64s.
;
; Callbacks: after the sources are acknowledged the hook runs the user
; callback, then the sound callback (vera_irq_sound, used by rmtdrv.s) and
; the sound effects callback (vera_irq_sfx, sfx.s) and the PCM samples
; callback (vera_irq_pcm, pcm.s):
; the user one does the work that must fit the vertical blank, the music
; (a few hundred to a few thousand cycles) comes after it,
; with interrupts enabled (CLI) so that the host's serial IRQs (Atari SIO)
; are not held off by a long music frame.  A VERA IRQ that arrives while
; the callbacks are running is acknowledged and counted, but does not run
; them again (busy flag).
;
; The hook touches only IEN, ISR and IRQ_LINE_L (VERA_BASE+$06..$08): ADDR,
; DATA, CTRL (ADDRSEL/DCSEL) are never touched, so it can interrupt code
; that is in the middle of a VRAM access sequence.  Callbacks that use the
; data ports must save and restore them (psgrmt.s does).
; ============================================================================

    .setcpu "6502"
    .include "vera.inc"
    .include "plat.inc"

IRQ_MASK        = $0F                   ; IEN/ISR bits 3:0 = AFLOW|SPRCOL|LINE|VSYNC

    .export _vera_irq_install
    .export _vera_irq_remove
    .export _vera_irq_enable
    .export _vera_irq_disable
    .export _vera_irq_take
    .export _vera_irq_set_line
    .export _vera_irq_set_callback
    .export _vera_irq_count
    .export _vera_frame_init
    .export _vera_frame_wait
    .export _vera_scanline
    .export _vera_lines_since
    .export vera_irq_sound, vera_irq_sfx, vera_irq_pcm

    .segment "DATA"

; the previous handler, reached through a JMP abs (old_jmp) whose operand is
; old_vector: a "jmp (old_vector)" breaks on the NMOS 6502 when the vector
; lands on $xxFF, which depends on the link
old_jmp:        .byte $4C               ; JMP
old_vector:     .word 0

    .segment "BSS"

old_ien:        .res 1                  ; IEN before the hook (X16: the KERNAL's VSYNC)
vectors:                                ; called through call_vector
user_cb:        .res 2
vera_irq_sound: .res 2                  ; sound callback (asm only), 0 = none
vera_irq_sfx:   .res 2                  ; sound effects callback (asm only), 0 = none
vera_irq_pcm:   .res 2                  ; PCM samples callback (asm only), 0 = none
installed:      .res 1
busy:           .res 1                  ; the callbacks are running
flags:          .res 1
pending:        .res 1
last_frame:     .res 1                  ; VSYNC count seen by vera_frame_wait
tmp:            .res 1
tmp2:           .res 1
_vera_irq_count: .res 4

    .segment "CODE"

; ----------------------------------------------------------------------------
; The IRQ handler
; ----------------------------------------------------------------------------
irq_handler:
    IRQ_ENTER
    lda VERA_ISR
    and VERA_IEN
    and #IRQ_MASK
    bne @ours
    IRQ_CHAIN old_jmp           ; not the VERA: the host handles it

@ours:
    sta pending
    and #$07
    beq @aflow
    sta VERA_ISR                ; ack VSYNC/LINE/SPRCOL (write 1 clears only these)
@aflow:
    lda pending
    and #$08
    beq @record
    lda VERA_IEN                ; AFLOW cannot be cleared: stop the level IRQ
    and #$F7
    sta VERA_IEN
@record:
    lda pending
    ora flags
    sta flags

    lda pending                 ; per-source counters
    lsr a
    bcc @c1
    inc _vera_irq_count+0
@c1:
    lsr a
    bcc @c2
    inc _vera_irq_count+1
@c2:
    lsr a
    bcc @c3
    inc _vera_irq_count+2
@c3:
    lsr a
    bcc @cb
    inc _vera_irq_count+3
@cb:
    lda busy                    ; the callbacks of an earlier IRQ are running
    bne @done
    inc busy
    cld
    cli                         ; the VERA line is released: host IRQs may nest
    lda user_cb+1               ; the user first: its VSYNC work (scroll,
    beq @sound                  ; sprite attributes) must fit the blank
    ldx #user_cb - vectors
    jsr call_vector
@sound:
    lda vera_irq_sound+1        ; then the music, which can take longer
    beq @sfx
    ldx #vera_irq_sound - vectors
    jsr call_vector
@sfx:
    lda vera_irq_sfx+1          ; and the sound effects
    beq @pcm
    ldx #vera_irq_sfx - vectors
    jsr call_vector
@pcm:
    lda vera_irq_pcm+1          ; and the PCM samples
    beq @end
    ldx #vera_irq_pcm - vectors
    jsr call_vector
@end:
    sei
    dec busy
@done:
    IRQ_OURS_END old_jmp, pending

; Call the vector at vectors+X with A = serviced sources.  No "jmp (abs)":
; the vectors are in BSS and may land on a page border, where the 6502 reads
; the high byte from the wrong address.  Push the target - 1 and RTS to it;
; its own RTS comes back to the caller of call_vector.
call_vector:
    lda vectors,x
    sec
    sbc #1
    tay
    lda vectors+1,x
    sbc #0
    pha
    tya
    pha
    lda pending                 ; A = serviced sources
    rts

; ----------------------------------------------------------------------------
; void vera_irq_install(void)
; ----------------------------------------------------------------------------
_vera_irq_install:
    lda installed
    bne @done
    php
    sei
    IRQ_HOST_INSTALL
    lda IRQ_VECTOR
    sta old_vector
    lda IRQ_VECTOR+1
    sta old_vector+1
    lda VERA_IEN
    and #IRQ_MASK
    sta old_ien
    lda #0
    sta flags
    sta busy
    ldx #3
@clr:
    sta _vera_irq_count,x
    dex
    bpl @clr
    lda #<irq_handler
    sta IRQ_VECTOR
    lda #>irq_handler
    sta IRQ_VECTOR+1
    lda #1
    sta installed
    plp
@done:
    rts

; ----------------------------------------------------------------------------
; void vera_irq_remove(void)
; ----------------------------------------------------------------------------
_vera_irq_remove:
    lda installed
    beq @done
    php
    sei
    lda VERA_IEN                ; the sources as before the hook (X16: the
    and #$80                    ; KERNAL lives on VSYNC), keep IRQ_LINE[8]
    ora old_ien
    sta VERA_IEN
    lda IRQ_VECTOR              ; restore only if the vector is still ours
    cmp #<irq_handler
    bne @keep
    lda IRQ_VECTOR+1
    cmp #>irq_handler
    bne @keep
    lda old_vector
    sta IRQ_VECTOR
    lda old_vector+1
    sta IRQ_VECTOR+1
    lda #0
    sta installed
@keep:                          ; someone hooked after us: stay (now inert, IEN = 0)
    plp
@done:
    rts

; ----------------------------------------------------------------------------
; void __fastcall__ vera_irq_enable(unsigned char mask)    A = mask
; ----------------------------------------------------------------------------
_vera_irq_enable:
    and #IRQ_MASK
    sta tmp
    php
    sei
    lda tmp
    and #$07
    sta VERA_ISR                ; drop stale status of the sources being enabled
    lda VERA_IEN
    and #$8F                    ; keep IRQ_LINE[8] and the current enables
    ora tmp
    sta VERA_IEN
    plp
    rts

; ----------------------------------------------------------------------------
; void __fastcall__ vera_irq_disable(unsigned char mask)   A = mask
; ----------------------------------------------------------------------------
_vera_irq_disable:
    and #IRQ_MASK
    eor #$FF                    ; bits 7:4 stay 1: IRQ_LINE[8] preserved
    sta tmp
    php
    sei
    lda VERA_IEN
    and tmp
    sta VERA_IEN
    plp
    rts

; ----------------------------------------------------------------------------
; unsigned char vera_irq_take(void)   returns and clears the serviced flags
; ----------------------------------------------------------------------------
_vera_irq_take:
    php
    sei
    lda flags
    ldx #0
    stx flags
    plp
    rts

; ----------------------------------------------------------------------------
; void __fastcall__ vera_irq_set_line(unsigned int line)   A = low, X = high
; ----------------------------------------------------------------------------
_vera_irq_set_line:
    sta tmp
    txa
    and #$01
    sta tmp2
    php
    sei
    lda tmp
    sta VERA_IRQLINE_L
    lda VERA_IEN
    and #IRQ_MASK               ; current enables, IRQ_LINE[8] rebuilt below
    ldx tmp2
    beq @b8
    ora #$80
@b8:
    sta VERA_IEN
    plp
    rts

; ----------------------------------------------------------------------------
; void __fastcall__ vera_irq_set_callback(void (*cb)(void))  A = low, X = high
; ----------------------------------------------------------------------------
_vera_irq_set_callback:
    php
    sei
    sta user_cb
    stx user_cb+1
    plp
    rts

; ----------------------------------------------------------------------------
; void vera_frame_init(void) - hook installed, VSYNC on, frame clock synced
; ----------------------------------------------------------------------------
_vera_frame_init:
    jsr _vera_irq_install
    lda _vera_irq_count+0
    sta last_frame
    lda #VERA_IRQ_VSYNC
    jmp _vera_irq_enable

; ----------------------------------------------------------------------------
; unsigned char vera_frame_wait(void) - wait for the next VSYNC; returns the
; frames gone by since the last call (1 = on time, more = frames dropped)
; ----------------------------------------------------------------------------
_vera_frame_wait:
@w: lda _vera_irq_count+0
    cmp last_frame
    beq @w
    tax
    sec
    sbc last_frame
    stx last_frame
    ldx #0
    rts

; ----------------------------------------------------------------------------
; unsigned vera_scanline(void) - the VERA line being drawn (0-524).  Bits 7:0
; (SCANLINE_L) and bit 8 (IEN bit 6) are two reads: the low byte is read again
; and the pair taken again when the line changed between them (255 -> 256
; would otherwise read 511).  CTRL is not touched.
; ----------------------------------------------------------------------------
_vera_scanline:
@r: ldy VERA_SCANLINE_L
    lda VERA_IEN
    cpy VERA_SCANLINE_L
    bne @r
    ldx #0
    and #$40
    beq @lo
    inx
@lo:
    tya
    rts

; ----------------------------------------------------------------------------
; unsigned __fastcall__ vera_lines_since(unsigned start) - VERA lines from
; line start (vera_scanline()) to now, 0-524: the time of a piece of work
; (525 lines a frame)
; ----------------------------------------------------------------------------
_vera_lines_since:
    sta tmp
    stx tmp2
    jsr _vera_scanline
    sec
    sbc tmp
    tay
    txa
    sbc tmp2
    tax
    bcs @pos                    ; now >= start
    tya                         ; wrapped past the end of the frame
    clc
    adc #<525
    tay
    txa
    adc #>525
    tax
@pos:
    tya
    rts
