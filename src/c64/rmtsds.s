; ============================================================================
; rmtsds.s - libvera, C64: an RMT song as a SID register stream (.sds, made
; at build time by tools/rmt2sid.py), the player of rmt_init_sds (rmt.h).
;
; rmt2sid.py plays the song on sim65 with the RMT routine and the POKEY ->
; SID translation of rmtsid.s and records the SID registers of every song
; frame; here the C64 only decodes them and writes the SID: a few hundred
; cycles a frame instead of the RMT routine plus the translation (~2200),
; or the routine plus psgrmt.s (~1500).  rmtdrv.s still gives the tempo
; (VERA frame clock, rmt_rate song frames a second).
;
; Every register that changes is a stream of events, a value and the
; frames it lasts (1..255), LZSS coded:
;   t = $00-$7F    t + 1 literal events follow: value, frames
;   t = $80-$FF    (t & $7F) + 2 events from d events before (next byte d)
; Each stream keeps its last 128 events in a ring of its own (ring + 256 *
; stream, value and frames at the write index w).  A frame without an event
; costs a decrement per stream: the player works only when a register
; changes.  The intro section plays once, then the loop section again and
; again (it never refers to the intro).
; In a control register bit 3 (TEST, never set by rmtsid.s) means: restart
; the envelope, the byte goes out with the gate off first.
; File layout: see tools/rmt2sid.py.
; ============================================================================

        .setcpu "6502"

        .export _rmt_init_sds, _rmt_c64_ntsc
        .import _rmt_stop, _rmt_ispeed, _rmt_rate
        .import player_play, player_silence, out_update, out_silence

SID         = $D400
VIC_RASTER  = $D012
MAXSTREAMS  = 16

        .segment "ZEROPAGE"

zp_p:   .res 2                  ; stream data
zp_r:   .res 2                  ; ring of the stream

        .segment "BSS"

base:   .res 2                  ; the .sds data
n:      .res 1                  ; streams
val:    .res 1                  ; the event being read
evf:    .res 1
left:   .res 2                  ; frames left in the section
frames: .res 4                  ; intro, loop frames
ofs:    .res 2                  ; the offset table (intro then loop)
tmp:    .res 1
st_lo:  .res MAXSTREAMS         ; per stream: data pointer,
st_hi:  .res MAXSTREAMS
cnt:    .res MAXSTREAMS         ;   bytes left in the token,
mode:   .res MAXSTREAMS         ;   0 = literal, else match,
src:    .res MAXSTREAMS         ;   ring index the match reads,
w:      .res MAXSTREAMS         ;   ring index of the next event,
dur:    .res MAXSTREAMS         ;   frames left of the current value,
reg:    .res MAXSTREAMS         ;   SID register,
ctrl:   .res MAXSTREAMS         ;   <> 0: a control register (bit 3 = restart)
ring:   .res MAXSTREAMS * 256

        .segment "CODE"

; ---------------------------------------------------------------------------
; unsigned char __fastcall__ rmt_init_sds(const void *sds)
; 1 = ok, 0 = not an .sds file (or too many streams).  The music stopped
; first; rmt_start plays it.
_rmt_init_sds:
        sta base
        stx base+1
        jsr _rmt_stop
        lda base
        sta zp_p
        lda base+1
        sta zp_p+1
        ldy #3
@mag:   lda (zp_p),y
        cmp magic,y
        bne @fail
        dey
        bpl @mag
        ldy #5
        lda (zp_p),y
        beq @fail
        cmp #MAXSTREAMS + 1
        bcc @ok
@fail:  lda #0                          ; not an .sds file
        tax
        rts
@ok:    sta n
        ldy #8
        lda (zp_p),y
        sta _rmt_rate
        lda #1
        sta _rmt_ispeed

        ldx #0                          ; the registers
        ldy #10
@reg:   lda (zp_p),y
        sta reg,x
        lda #0
        sta ctrl,x
        lda reg,x
        cmp #$04
        beq @c
        cmp #$0B
        beq @c
        cmp #$12
        bne @nc
@c:     inc ctrl,x
@nc:    iny
        inx
        cpx n
        bne @reg

        ldx #0                          ; the SID at the start
@init:  lda (zp_p),y
        sta SID,x
        iny
        inx
        cpx #25
        bne @init

        ldx #0                          ; intro and loop frames
@fr:    lda (zp_p),y
        sta frames,x
        iny
        inx
        cpx #4
        bne @fr
        tya                             ; the offset table follows
        clc
        adc base
        sta ofs
        lda #0
        adc base+1
        sta ofs+1

        lda #<ring                      ; the rings: ring + 256 * stream
        sta zp_r
        lda #<play                      ; this player, no output module
        sta player_play+1
        lda #>play
        sta player_play+2
        lda #<silence
        sta player_silence+1
        lda #>silence
        sta player_silence+2
        lda #<done
        sta out_update+1
        lda #>done
        sta out_update+2
        sta out_silence+2
        lda #<done
        sta out_silence+1

        lda frames                      ; an intro?
        ora frames+1
        beq @loop
        lda #0
        jsr section
        lda #1
        rts
@loop:  lda #1
        jsr section
        lda #1
        rts

magic:  .byte $53, $44, $53, $02        ; "SDS", version 2 (ASCII)

; section A (0 intro, 1 loop): every stream from its start
section:
        asl a
        tax
        lda frames,x
        sta left
        lda frames+1,x
        sta left+1
        txa                             ; offset table entry: (sec * n + k) * 2
        beq @t
        lda n
@t:     asl a
        clc
        adc ofs
        sta zp_p
        lda #0
        adc ofs+1
        sta zp_p+1
        ldx #0
        ldy #0
@s:     lda (zp_p),y
        clc
        adc base
        sta st_lo,x
        iny
        lda (zp_p),y
        adc base+1
        sta st_hi,x
        iny
        lda #0
        sta cnt,x
        sta dur,x
        sta w,x
        inx
        cpx n
        bne @s
done:   rts

; ---------------------------------------------------------------------------
; one song frame (rmtdrv.s player_play).  The streams go from the last to
; the first (rmt2sid.py stores them in reverse write order).
play:
        lda left
        ora left+1
        bne @go
        lda #1                          ; the section is over: the loop
        jsr section
@go:    lda left
        bne @dl
        dec left+1
@dl:    dec left

        ldx n
        dex
@s:     lda dur,x                       ; the value goes on?
        beq @ev
        dec dur,x
        dex
        bpl @s
        rts
@ev:    jsr event
        dex
        bpl @s
        rts

; the next event of stream X: its value to the SID register
event:
        lda st_lo,x
        sta zp_p
        lda st_hi,x
        sta zp_p+1
        ldy #0
        lda cnt,x
        bne @have
        lda (zp_p),y                    ; a token
        bmi @m
        iny
        clc
        adc #1                          ; literal events
        sta cnt,x
        lda #0
        sta mode,x
        beq @have                       ; always
@m:     iny
        and #$7F
        clc
        adc #2
        sta cnt,x
        lda (zp_p),y                    ; distance in events
        iny
        asl a
        sta tmp
        lda w,x
        sec
        sbc tmp
        sta src,x
        lda #1
        sta mode,x
@have:  dec cnt,x
        txa                             ; the ring of the stream
        clc
        adc #>ring
        sta zp_r+1
        lda mode,x
        bne @ring
        lda (zp_p),y                    ; a literal event
        sta val
        iny
        lda (zp_p),y
        sta evf
        iny
        bne @adv                        ; always (Y <= 4)
@ring:  sty tmp
        ldy src,x
        lda (zp_r),y
        sta val
        iny
        lda (zp_r),y
        sta evf
        iny
        tya
        sta src,x
        ldy tmp
@adv:   tya                             ; past the bytes read
        clc
        adc st_lo,x
        sta st_lo,x
        bcc @got
        inc st_hi,x
@got:   ldy w,x                         ; kept for the matches
        lda val
        sta (zp_r),y
        iny
        lda evf
        sta (zp_r),y
        iny
        tya
        sta w,x
        ldy evf                         ; frames after this one
        dey
        tya
        sta dur,x
        ldy reg,x
        lda ctrl,x
        beq @put
        lda val
        and #$08
        beq @put
        lda val                         ; restart: gate off, then on
        and #$F6
        sta SID,y
        lda val
        and #$F7
        sta SID,y
        rts
@put:   lda val
        sta SID,y
        rts

; music off: gates off, the envelopes fall to 0 (release 0)
silence:
        lda #$00
        sta SID+$04
        sta SID+$0B
        sta SID+$12
        rts

; ---------------------------------------------------------------------------
; unsigned char rmt_c64_ntsc(void): 1 on an NTSC C64 (262/263 lines), 0 PAL
; (the low byte of the last raster line: $37 PAL, $05/$06 NTSC)
_rmt_c64_ntsc:
        php
        sei
@l1:    lda VIC_RASTER
@l2:    cmp VIC_RASTER
        beq @l2
        bmi @l1
        plp
        ldx #0
        cmp #$20
        lda #0
        bcs @pal
        lda #1
@pal:   rts
