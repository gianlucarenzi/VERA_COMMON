; ============================================================================
; pcm.s - PCM samples on the VERA audio FIFO from VRAM, the same on every
; host (pcm.h)
;
; A sample (8 bit signed mono, any rate) lies in VRAM (pcm_load: from the
; SD / disk straight to VRAM, no RAM).  pcm_play resets the FIFO, fills a
; first block and sets the rate; then every VSYNC (vera_irq_pcm, after the
; music and the PSG effects) copies VRAM -> FIFO through DATA0 until the
; FIFO is full or BLOCK bytes are written: more than the 103 a frame that
; 6.1 kHz takes, so the FIFO never runs dry.  ~12 cycles a byte, only while
; a sample plays.  When it is all in the FIFO the callback is idle; the FIFO
; plays out by itself.
;
; CTRL, FX_CTRL and the port 0 address are saved and restored (as sfx.s).
; ============================================================================

        .setcpu "6502"
        .include "vera.inc"

        .export _pcm_play, _pcm_stop, _pcm_busy
        .import vera_irq_pcm, _vera_frame_init

BLOCK   = 128                   ; bytes a VSYNC at most
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
@go:    ldx #BLOCK
        ; fall through

; copy up to X bytes VRAM -> FIFO (stops when the FIFO is full or the
; sample ends); saves and restores the VERA state
copy:
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
@byte:  lda left_l
        ora left_h
        beq @end
        bit VERA_AUDIO_CTRL             ; N = FIFO full
        bmi @end
        lda VERA_DATA0
        sta VERA_AUDIO_DATA
        lda left_l
        bne @dl
        dec left_h
@dl:    dec left_l
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
