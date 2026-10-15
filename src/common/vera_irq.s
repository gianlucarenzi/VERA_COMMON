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
; Callbacks: after the sources are acknowledged the hook runs the sound
; callback (vera_irq_sound, used by rmtdrv.s) and then the user callback,
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
    .export vera_irq_sound

    .segment "BSS"

old_vector:     .res 2
user_cb:        .res 2
vera_irq_sound: .res 2                  ; sound callback (asm only), 0 = none
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
    IRQ_CHAIN old_vector        ; not the VERA: the host handles it

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
    lda vera_irq_sound+1
    beq @user
    lda pending                 ; A = serviced sources
    jsr call_sound
@user:
    lda user_cb+1
    beq @end
    lda pending
    jsr call_user
@end:
    sei
    dec busy
@done:
    IRQ_RETURN

call_sound:
    jmp (vera_irq_sound)
call_user:
    jmp (user_cb)

; ----------------------------------------------------------------------------
; void vera_irq_install(void)
; ----------------------------------------------------------------------------
_vera_irq_install:
    lda installed
    bne @done
    php
    sei
    lda IRQ_VECTOR
    sta old_vector
    lda IRQ_VECTOR+1
    sta old_vector+1
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
    lda VERA_IEN                ; all four sources off, keep IRQ_LINE[8]
    and #$80
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
