; ============================================================================
; pcm.s - PCM samples on the VERA audio FIFO from VRAM, the same on every
; host (pcm.h)
;
; A sample (8 bit signed mono, any rate) lies in VRAM (pcm_load: from the
; SD / disk straight to VRAM, no RAM).  pcm_play resets the FIFO, fills a
; first block and sets the rate; then every VSYNC (vera_irq_pcm, after the
; music and the PSG effects) copies a block VRAM -> FIFO through DATA0:
; 7 * AUDIO_RATE bytes (112 at 6.1 kHz), a little more than the 6.4 *
; AUDIO_RATE a VERA frame takes, so the FIFO never runs dry and fills by
; ~9 bytes a frame (a 5.5 KB sample ends < 800 bytes into the 4 KB FIFO).
; 13 cycles a byte in a tight loop, ~1600 cycles a frame at 6.1 kHz
; (tests/prof_pcm.c), only while a sample plays; a frame is skipped when
; the FIFO reads full.  When it is all in the FIFO the callback is idle;
; the FIFO plays out by itself.
;
; CTRL, FX_CTRL and the port 0 address are saved and restored (as sfx.s).
; ============================================================================

        .setcpu "6502"
        .include "vera.inc"

        .export _pcm_play, _pcm_stop, _pcm_busy
        .import vera_irq_pcm, _vera_frame_init

FIRST   = 255                   ; bytes before the rate is set
VOLUME  = $0F                   ; AUDIO_CTRL volume (max)
FIFO_FULL = $80                 ; AUDIO_CTRL read: FIFO full

        .segment "ZEROPAGE"
sp_:    .res 2

        .segment "BSS"
src_l:  .res 1                  ; next VRAM byte
src_m:  .res 1
src_h:  .res 1
left_l: .res 1                  ; bytes left to put in the FIFO
left_h: .res 1
rate:   .res 1
block:  .res 1                  ; bytes a VSYNC: 7 * rate, at most 255
count:  .res 1                  ; bytes of this block
save_ctrl: .res 1
save_fx:   .res 1
save_l:    .res 1
save_m:    .res 1
save_h:    .res 1

        .segment "CODE"

; void __fastcall__ pcm_play(const pcm_sound *s)
; pcm_sound: unsigned long vram (3 bytes used), unsigned len, unsigned char rate
_pcm_play:
        sta sp_
        stx sp_+1
        jsr _vera_frame_init
        php
        sei
        ldy #0
        lda (sp_),y
        sta src_l
        iny
        lda (sp_),y
        sta src_m
        iny
        lda (sp_),y
        sta src_h
        ldy #4                          ; len (after the 4 bytes of vram)
        lda (sp_),y
        sta left_l
        iny
        lda (sp_),y
        sta left_h
        iny
        lda (sp_),y
        sta rate
        asl a                           ; block = 7 * rate (max 255)
        asl a
        asl a
        bcs @max
        sec
        sbc rate
        bcs @blk
@max:   lda #255
@blk:   sta block
        lda #0
        sta VERA_AUDIO_RATE             ; stopped while the FIFO is filled
        lda #($80 | VOLUME)             ; reset the FIFO, 8 bit mono
        sta VERA_AUDIO_CTRL
        ldx #FIRST
        jsr copy
        lda rate
        sta VERA_AUDIO_RATE
        lda #<tick
        sta vera_irq_pcm
        lda #>tick
        sta vera_irq_pcm+1
        plp
        rts

; void pcm_stop(void): the sample off, the FIFO emptied
_pcm_stop:
        php
        sei
        lda #0
        sta vera_irq_pcm+1
        sta left_l
        sta left_h
        sta VERA_AUDIO_RATE
        lda #($80 | VOLUME)
        sta VERA_AUDIO_CTRL
        plp
        rts

; unsigned char pcm_busy(void): 1 while the sample is not all in the FIFO
; or the FIFO is not empty
_pcm_busy:
        lda left_l
        ora left_h
        bne @y
        lda VERA_AUDIO_CTRL
        and #$40                        ; FIFO empty
        bne @n
@y:     lda #1
        ldx #0
        rts
@n:     lda #0
        tax
        rts

; VERA IRQ callback (vera_irq_pcm), A = serviced sources
tick:
        and #VERA_IRQ_VSYNC
        beq @rts
        lda left_l
        ora left_h
        bne @go
        sta vera_irq_pcm+1              ; all in the FIFO: idle
@rts:   rts
@go:    bit VERA_AUDIO_CTRL             ; FIFO full: nothing this frame
        bmi @rts
        ldx block
        ; fall through

; copy min(X, bytes left) bytes VRAM -> FIFO; saves and restores the VERA
; state
copy:
        lda left_h                      ; X = min(X, left), left -= X
        bne @n
        cpx left_l
        bcc @n
        ldx left_l
@n:     stx count
        lda left_l
        sec
        sbc count
        sta left_l
        bcs @nb
        dec left_h
@nb:
        lda VERA_CTRL
        sta save_ctrl
        lda #VERA_DCSEL2
        sta VERA_CTRL
        lda VERA_FX_CTRL
        sta save_fx
        lda #0
        sta VERA_FX_CTRL
        sta VERA_CTRL                   ; ADDRSEL 0, DCSEL 0
        lda VERA_ADDR_L
        sta save_l
        lda VERA_ADDR_M
        sta save_m
        lda VERA_ADDR_H
        sta save_h
        lda src_l
        sta VERA_ADDR_L
        lda src_m
        sta VERA_ADDR_M
        lda src_h
        and #$01
        ora #VERA_INC1
        sta VERA_ADDR_H
        ldx count
        beq @end
@byte:  lda VERA_DATA0                  ; 13 cycles a byte
        sta VERA_AUDIO_DATA
        dex
        bne @byte
@end:   lda VERA_ADDR_L                 ; where the next block starts
        sta src_l
        lda VERA_ADDR_M
        sta src_m
        lda VERA_ADDR_H
        and #$01
        sta src_h
        lda save_l
        sta VERA_ADDR_L
        lda save_m
        sta VERA_ADDR_M
        lda save_h
        sta VERA_ADDR_H
        lda #VERA_DCSEL2
        sta VERA_CTRL
        lda save_fx
        sta VERA_FX_CTRL
        lda save_ctrl
        sta VERA_CTRL
        rts
