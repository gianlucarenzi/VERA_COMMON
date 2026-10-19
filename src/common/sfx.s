; ============================================================================
; sfx.s - sound effects on the VERA PSG, the same on every host (sfx.h)
;
; An effect is a list of frames, each the 4 registers of a PSG voice
; (frequency low, high, pan | volume, waveform | pulse width): the VERA
; frame clock (vera_irq.s, vera_irq_sfx: after the music) copies one frame
; a VSYNC to the voice that plays the effect.  The frames are made at build
; time (tools/psgsfx.py), so playing costs ~70 cycles a frame per voice and
; nothing when no effect sounds.
;
; Voices SFX_V0 .. SFX_V0+SFX_NV-1 (12-15): free with RMT4 / RMT8 music
; (voices 0-7).  sfx_play takes a free voice, else the one that has played
; longest.
;
; Bank (tools/psgsfx.py): .byte count, .word effect 0 .. count-1; an
; effect: .byte frames (1..63), then 4 bytes a frame.
;
; The PSG writes happen in the IRQ: CTRL, FX_CTRL and the port 0 address
; are saved and restored (as psgrmt.s does).
; ============================================================================

        .setcpu "6502"
        .include "vera.inc"

        .export _sfx_init, _sfx_play, _sfx_stop, _sfx_busy
        .import vera_irq_sfx, _vera_frame_init

SFX_V0  = 12                    ; first PSG voice
SFX_NV  = 4                     ; voices
PSG_V0  = VERA_PSG_BASE + 4 * SFX_V0

        .segment "ZEROPAGE"
ptr:    .res 2

        .segment "BSS"
bank:   .res 2                  ; the bank of sfx_init
vptr_l: .res SFX_NV             ; next frame of each voice
vptr_h: .res SFX_NV
vcnt:   .res SFX_NV             ; frames left + 1 (0 = idle, 1 = silence it)
vage:   .res SFX_NV             ; play order (the oldest is taken)
age:    .res 1
idx:    .res 1
best:   .res 1
save_ctrl: .res 1
save_fx:   .res 1
save_l:    .res 1
save_m:    .res 1
save_h:    .res 1

        .segment "CODE"

; void __fastcall__ sfx_init(const void *bank)
_sfx_init:
        sta bank
        stx bank+1
        jsr _sfx_stop
        jsr _vera_frame_init            ; VSYNC IRQ (idempotent)
        php
        sei
        lda #<tick
        sta vera_irq_sfx
        lda #>tick
        sta vera_irq_sfx+1
        plp
        rts

; unsigned char sfx_busy(void): 1 while an effect sounds
_sfx_busy:
        ldx #SFX_NV-1
        lda #0
@b:     ora vcnt,x
        dex
        bpl @b
        tax
        beq @r
        lda #1
@r:     ldx #0
        rts

; void __fastcall__ sfx_play(unsigned char id)
_sfx_play:
        php
        sei
        asl a                           ; bank + 1 + id * 2
        clc
        adc #1
        sta idx
        lda bank
        sta ptr
        lda bank+1
        sta ptr+1
        ldx #SFX_NV-1                   ; a free voice, else the oldest
@free:  lda vcnt,x
        beq @got
        dex
        bpl @free
        jsr oldest
@got:   ldy idx
        lda (ptr),y                     ; the effect: frames, then the data
        pha
        iny
        lda (ptr),y
        sta ptr+1
        pla
        sta ptr
        ldy #0
        lda (ptr),y
        clc
        adc #1
        sta vcnt,x                      ; frames + 1: the last tick silences
        lda ptr
        clc
        adc #1
        sta vptr_l,x
        lda ptr+1
        adc #0
        sta vptr_h,x
        inc age
        lda age
        sta vage,x
        plp
        rts

; X = the voice that started first (the largest age - vage, modulo 256)
oldest:
        ldx #0
        lda age
        sec
        sbc vage
        sta best
        ldy #1
@n:     lda age
        sec
        sbc vage,y
        cmp best
        bcc @k
        sta best
        tya
        tax
@k:     iny
        cpy #SFX_NV
        bne @n
        rts

; void sfx_stop(void): every effect off
_sfx_stop:
        php
        sei
        ldx #SFX_NV-1
        lda #1                          ; silenced by the next tick
@s:     sta vcnt,x
        dex
        bpl @s
        plp
        lda vera_irq_sfx+1              ; no frame clock yet: silence now
        bne @r
        jsr silence_now
@r:     rts

silence_now:
        php
        sei
        jsr vera_begin
        ldx #SFX_NV-1
@v:     lda #0
        sta vcnt,x
        jsr voice_addr
        sta VERA_DATA0
        sta VERA_DATA0
        sta VERA_DATA0
        sta VERA_DATA0
        dex
        bpl @v
        jsr vera_end
        plp
        rts

; ----------------------------------------------------------------------------
; VERA IRQ callback (vera_irq_sfx), A = serviced sources
tick:
        and #VERA_IRQ_VSYNC
        beq @rts
        ldx #SFX_NV-1                   ; anything to do?
        lda #0
@any:   ora vcnt,x
        dex
        bpl @any
        tax
        beq @rts
        jsr vera_begin
        ldx #SFX_NV-1
@v:     lda vcnt,x
        beq @next
        dec vcnt,x
        jsr voice_addr
        lda vcnt,x
        bne @frame
        sta VERA_DATA0                  ; the end: voice silent
        sta VERA_DATA0
        sta VERA_DATA0
        sta VERA_DATA0
        beq @next
@frame: lda vptr_l,x
        sta ptr
        lda vptr_h,x
        sta ptr+1
        ldy #0
        lda (ptr),y
        sta VERA_DATA0
        iny
        lda (ptr),y
        sta VERA_DATA0
        iny
        lda (ptr),y
        sta VERA_DATA0
        iny
        lda (ptr),y
        sta VERA_DATA0
        lda ptr
        clc
        adc #4
        sta vptr_l,x
        bcc @next
        inc vptr_h,x
@next:  dex
        bpl @v
        jmp vera_end
@rts:   rts

; DATA0 on the registers of voice X; returns A = 0, X kept
voice_addr:
        txa
        asl a
        asl a
        clc
        adc #<PSG_V0
        sta VERA_ADDR_L
        lda #>PSG_V0
        adc #0
        sta VERA_ADDR_M
        lda #(VERA_INC1 | ^PSG_V0)
        sta VERA_ADDR_H
        lda #0
        rts

vera_begin:
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
        rts

vera_end:
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
