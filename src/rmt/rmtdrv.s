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
; Player and output: this is the core (player clock, start / stop).  The
; player is two JMPs (player_play, player_silence) set by rmtrmt.s, the RMT
; routine, or by rmtsds.s, the SID stream player of the C64; the output is
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
; The song in a RAM bank (rmt_bank <> 0): the module lives in the bank
; window (Atari: a RAMbo bank at $4000-$7FFF, rmt_bank = its PORTB bits;
; X16: a banked RAM bank at $A000-$BFFF, rmt_bank = RAM_BANK) and the
; player only sees it while it plays: the callback switches the bank in
; around player_play and restores the one it found (the program may be in
; the middle of an SD call with the FAT32 bank in, or running code in the
; window: an interrupt returns with the window as it was).  rmt_init_core
; does the same around the RMT init; rmt_bank_copy fills the bank.
;
; C interface: see rmt.h
; ============================================================================

        .setcpu "6502"
        .include "vera.inc"

        .export _rmt_start, _rmt_stop
        .export _rmt_frames, _rmt_ispeed, _rmt_rate, _rmt_palnts
        .export rmt_palnts := _rmt_palnts
        .export player_play, player_silence, out_update, out_silence
        .export pokey_shadow, _rmt_pokey := pokey_shadow
        .export _rmt_bank, _rmt_bank_copy, song_bank_in, song_bank_out
        .import popax
        .importzp ptr1, ptr2
        .import vera_irq_sound, _vera_frame_init

VERA_FRAME_RATE = 60                    ; nominal VERA frames a second

        .segment "DATA"

_rmt_rate:      .byte 50        ; frames a second the song was written for
_rmt_palnts:    .byte 1         ; the Atari PALNTS of the song: 1 = PAL, 0 = NTSC
_rmt_bank:      .byte 0         ; the bank of the song, 0 = in the main RAM

        .segment "BSS"

pokey_shadow:   .res 16         ; the POKEY registers written by the player
_rmt_frames:    .res 2          ; song frames played
_rmt_ispeed:    .res 1          ; player calls per song frame (1..4)
on:             .res 1
acc:            .res 1          ; tempo accumulator
calls:          .res 1
irq_bank:       .res 1          ; the window found by the callback
main_bank:      .res 1          ; ... by song_bank_in (main program)

; the window of the song bank: A = rmt_bank (<> 0) in, the old one in sv
.macro  SONG_IN sv
.if .defined(__ATARI__)
        ldx PORTB
        stx sv
        txa
        and #PORTB_KEEP
        ora _rmt_bank
        sta PORTB
.elseif .defined(__CX16__)
        ldx RAM_BANK
        stx sv
        sta RAM_BANK
.endif
.endmacro
.macro  SONG_OUT sv
.if .defined(__ATARI__)
        lda sv
        sta PORTB
.elseif .defined(__CX16__)
        lda sv
        sta RAM_BANK
.endif
.endmacro
PORTB       = $D301                     ; Atari: bits 2, 3, 5, 6 bank, bit 4 = 0 CPU
PORTB_KEEP  = %10000011                 ; self test, BASIC, OS ROM bits (sdbank.s)
RAM_BANK    = $00                       ; X16

        .segment "CODE"

; song_bank_in / song_bank_out: the song bank around a call of the main
; program that reads the module (rmt_init_core); nothing if rmt_bank = 0.
; A, X lost (call it before loading X for the player); Y kept
song_bank_in:
        lda _rmt_bank
        beq :+
        SONG_IN main_bank
:       rts
song_bank_out:
        lda _rmt_bank
        beq :+
        SONG_OUT main_bank
:       rts

; void __fastcall__ rmt_bank_copy(void *dst, const void *src, unsigned n):
; n bytes from the main RAM into the song bank (dst in its window)
_rmt_bank_copy:
        sta calls                       ; n (calls / acc: free while the music is off)
        stx acc
        jsr popax
        sta ptr1                        ; src
        stx ptr1+1
        jsr popax
        sta ptr2                        ; dst
        stx ptr2+1
        jsr song_bank_in
        ldy #0
@page:  lda acc                         ; whole pages, then the rest
        beq @rest
:       lda (ptr1),y
        sta (ptr2),y
        iny
        bne :-
        inc ptr1+1
        inc ptr2+1
        dec acc
        jmp @page
@rest:  ldx calls
        beq @done
:       lda (ptr1),y
        sta (ptr2),y
        iny
        dex
        bne :-
@done:  jmp song_bank_out

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
        jsr player_silence
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
        lda _rmt_bank                   ; the song bank in
        beq @play
        SONG_IN irq_bank
@play:  jsr player_play                 ; RMT: writes pokey_shadow
        dec calls
        bne @play
        lda _rmt_bank
        beq :+
        SONG_OUT irq_bank
:
        inc _rmt_frames
        bne @psg
        inc _rmt_frames+1
@psg:   jmp out_update
@skip:  sta acc
@rts:   rts

out_update:
        jmp no_out                      ; the output's update: channel state
                                        ; -> PSG voices, POKEY or SID
; the player: rmtrmt.s (the RMT routine, rmt_init_core) or rmtsds.s (C64:
; a SID register stream made at build time, rmt_init_sds)
player_play:
        jmp no_out
player_silence:
        jmp no_out
no_out: rts
