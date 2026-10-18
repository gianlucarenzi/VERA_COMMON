; ============================================================================
; rmtdrv.s - RMT player on the VERA PSG, driven by the VERA frame clock
;
; The same driver on every host: it replaces rmtvbi.s (Atari VBI) and
; rmtirq.s (C64 raster IRQ).  The Atari RMT player (rmtplayr.s, or
; lzsplayr.s for a .sap/.xex song, -D RMT_SHADOW -D RMT_VERA) writes its
; POKEY registers to pokey_shadow (RAM) and psgrmt.s turns the channel
; state into VERA PSG voices.
;
; Tempo: the player is called from the VERA VSYNC IRQ (vera_irq.s sound
; callback), 59.5 times a second on every host.  An RMT song is written for
; the 50 Hz of a PAL Atari or the 60 Hz of an NTSC one (rmt_rate): a
; Bresenham accumulator plays rmt_rate frames out of every 60 VERA frames
; (a 50 Hz song skips one VERA frame in six), so it keeps its tempo on a PAL
; or NTSC Atari or C64 alike.  With instrument speed N the player is called
; N times in a row in its frame; psg_update then writes the PSG once.
;
; The PSG pitch follows the Atari the song was written on (rmt_palnts: the
; POKEY clock of a PAL or NTSC machine), not the host.
;
; Output: this is the core (player clock, start / stop); the output is
; the target of two JMPs (out_update, out_silence) that an output module
; sets: rmtpsg.s (rmt_init, rmt_out_psg: the VERA PSG, psgrmt.s) or the
; host one (rmt_init_host, rmt_out_host; Atari: rmtpokey.s, POKEY; C64:
; rmtsid.s, the SID).  The tempo is the VERA frame clock either way, and a
; program links only the outputs it calls.
;
; The callback runs with interrupts enabled (vera_irq.s), so the Atari SIO
; keeps working while the music plays; psgrmt.s saves and restores CTRL,
; FX_CTRL and the port 0 address, so the game can be in the middle of its
; own VRAM access sequence.
;
; C interface: see rmt.h
; ============================================================================

        .setcpu "6502"
        .include "vera.inc"

        .export rmt_init_core, _rmt_start, _rmt_stop
        .export _rmt_frames, _rmt_ispeed, _rmt_rate, _rmt_palnts
        .export rmt_palnts := _rmt_palnts
        .export out_update, out_silence
        .export pokey_shadow, _rmt_pokey := pokey_shadow
        .import RASTERMUSICTRACKER
        .import vera_irq_sound, _vera_frame_init

rmt_init    = RASTERMUSICTRACKER+0      ; X/Y = module, A = song line
rmt_play    = RASTERMUSICTRACKER+3
rmt_silence = RASTERMUSICTRACKER+9

VERA_FRAME_RATE = 60                    ; nominal VERA frames a second

        .segment "DATA"

_rmt_rate:      .byte 50        ; frames a second the song was written for
_rmt_palnts:    .byte 1         ; the Atari PALNTS of the song: 1 = PAL, 0 = NTSC

        .segment "BSS"

pokey_shadow:   .res 16         ; the POKEY registers written by the player
_rmt_frames:    .res 2          ; song frames played
_rmt_ispeed:    .res 1          ; player calls per song frame (1..4)
on:             .res 1
acc:            .res 1          ; tempo accumulator
calls:          .res 1

        .segment "CODE"

; ---------------------------------------------------------------------------
; rmt_init_core: A/X = module (the output modules' rmt_init*, once they set
; the output).  Music stopped first.  Returns A = instrument speed (1..4),
; X = 0.
rmt_init_core:
        pha
        txa
        pha
        jsr _rmt_stop
        pla                             ; X = lo, Y = hi for the player
        tay
        pla
        tax
        lda #0                          ; from song line 0
        jsr rmt_init                    ; A = instrument speed
        cmp #1                          ; clamp to 1..4 (RMT format range)
        bcs @lo
        lda #1
@lo:    cmp #5
        bcc @hi
        lda #4
@hi:    sta _rmt_ispeed
        ldx #0
        rts

; ---------------------------------------------------------------------------
; void rmt_start(void): the music plays from the VERA frame clock
_rmt_start:
        jsr _vera_frame_init            ; hook + VSYNC IRQ (idempotent)
        lda _rmt_ispeed
        bne @sp
        lda #1                          ; not initialised: one call a frame
        sta _rmt_ispeed
@sp:    php
        sei
        lda #0
        sta acc
        lda #<frame
        sta vera_irq_sound
        lda #>frame
        sta vera_irq_sound+1
        lda #1
        sta on
        plp
        rts

; void rmt_stop(void): music off, PSG voices silent; the song position is
; kept (rmt_start goes on from there)
_rmt_stop:
        lda on
        bne @off
        rts
@off:   php
        sei
        lda #0
        sta on
        sta vera_irq_sound+1            ; callback off
        plp
        jsr rmt_silence
out_silence:
        jmp no_out                      ; the output's silence (rmtpsg.s, ...)

; ---------------------------------------------------------------------------
; VERA IRQ sound callback: A = serviced sources
frame:
        and #VERA_IRQ_VSYNC
        beq @rts
        lda acc                         ; acc += rate; a song frame each
        clc                             ; time it passes 60
        adc _rmt_rate
        cmp #VERA_FRAME_RATE
        bcc @skip
        sbc #VERA_FRAME_RATE
        sta acc
        lda _rmt_ispeed
        sta calls
@play:  jsr rmt_play                    ; writes pokey_shadow
        dec calls
        bne @play
        inc _rmt_frames
        bne @psg
        inc _rmt_frames+1
@psg:   jmp out_update
@skip:  sta acc
@rts:   rts

out_update:
        jmp no_out                      ; the output's update: channel state
                                        ; -> PSG voices, POKEY or SID
no_out: rts
