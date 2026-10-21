; ============================================================================
; pksplay.s - libvera, Atari: the player of a POKEY register stream (.pks,
; made at build time by tools/rmt2pks.py) for a boot loader: the music of
; the game on POKEY channels 1+2 while the loader reads the disk with the
; SIO (channels 3+4 and AUDCTL are the serial clock, sio.s).
;
; Not in libvera.lib: the program links it with its stream (pks_data, the
; .pks file) into a RAM bank image (a RAMbo bank at $4000), with PKSJMP
; first: the loader's VBI switches the bank in and calls pks_play.
; Segments: PKSJMP (the jump table), PKSCODE (self-modified: RAM), PKSBSS,
; PKSRING (4 pages, page aligned).
;   +0  jmp pks_init        A = 1 ok, 0 not a .pks stream; POKEY 1+2 set
;   +3  jmp pks_play        one VBI: one song frame (PAL; NTSC skips one
;                           VBI in 6, the songs are 50 Hz)
;   +6  jmp pks_silence     channels 1+2 at volume 0
; No zero page (it plays under whatever program runs, the loader or the
; game): the stream and ring reads are self-modified absolute addresses;
; A, X, Y not kept.
;
; The decoder is the one of src/c64/rmtsds.s (LZSS events, a 128 event
; ring per stream, intro once then the loop), writing POKEY registers 0-3.
; File layout: see tools/rmt2pks.py.
; ============================================================================

        .setcpu "6502"

        .import pks_data

POKEY       = $D200
PAL         = $D014                     ; bits 1-3: 0 PAL, 7 NTSC
MAXSTREAMS  = 4

        .segment "PKSJMP"

        jmp pks_init
        jmp pks_play
        jmp pks_silence

        .segment "PKSBSS"

n:      .res 1                  ; streams
val:    .res 1                  ; the event being read
evf:    .res 1
tmp:    .res 1
ntsc:   .res 1                  ; VBIs to the one skipped (NTSC)
left:   .res 2                  ; frames left in the section
frames: .res 4                  ; intro, loop frames
ofs:    .res 2                  ; the offset table (intro then loop)
st_lo:  .res MAXSTREAMS         ; per stream: data pointer,
st_hi:  .res MAXSTREAMS
cnt:    .res MAXSTREAMS         ;   bytes left in the token,
mode:   .res MAXSTREAMS         ;   0 = literal, else match,
src:    .res MAXSTREAMS         ;   ring index the match reads,
w:      .res MAXSTREAMS         ;   ring index of the next event,
dur:    .res MAXSTREAMS         ;   frames left of the current value,
reg:    .res MAXSTREAMS         ;   POKEY register

        .segment "PKSRING"      ; page aligned: ring + 256 * stream

ring:   .res MAXSTREAMS * 256

        .segment "PKSCODE"

; ---------------------------------------------------------------------------
pks_init:
        ldx #3
@mag:   lda pks_data,x
        cmp magic,x
        bne @fail
        dex
        bpl @mag
        lda pks_data+4
        beq @fail
        cmp #MAXSTREAMS + 1
        bcc @ok
@fail:  lda #0
        rts
@ok:    sta n
        lda #6
        sta ntsc
        lda #<(pks_data+6)
        sta gp
        lda #>(pks_data+6)
        sta gp+1
        ldx #0                          ; the registers
@reg:   jsr get
        sta reg,x
        inx
        cpx n
        bne @reg
        ldx #0                          ; POKEY 1+2 at the start
@init:  jsr get
        sta POKEY,x
        inx
        cpx #4
        bne @init
        ldx #0                          ; intro and loop frames
@fr:    jsr get
        sta frames,x
        inx
        cpx #4
        bne @fr
        lda gp                          ; the offset table follows
        sta ofs
        lda gp+1
        sta ofs+1
        lda frames                      ; an intro?
        ora frames+1
        beq @loop
        lda #0
        beq @sec                        ; always
@loop:  lda #1
@sec:   jsr section
        lda #1
        rts

magic:  .byte $50, $4B, $53, $01        ; "PKS", version 1 (ASCII)

; A = the byte at gp, gp + 1
get:
gp = * + 1
        lda $FFFF
        inc gp
        bne :+
        inc gp+1
:       rts

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
        sta gp
        lda #0
        adc ofs+1
        sta gp+1
        ldx #0
@s:     jsr get
        clc
        adc #<pks_data
        sta st_lo,x
        jsr get
        adc #>pks_data
        sta st_hi,x
        lda #0
        sta cnt,x
        sta dur,x
        sta w,x
        inx
        cpx n
        bne @s
        rts

; ---------------------------------------------------------------------------
; one VBI.  The streams go from the last to the first.
pks_play:
        lda PAL
        and #$0E
        beq @pal
        dec ntsc                        ; NTSC: 5 song frames in 6 VBIs
        bne @pal
        lda #6
        sta ntsc
        rts
@pal:   lda left
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

; the next event of stream X: its value to the POKEY register
event:
        lda st_lo,x
        sta ev_rd+1
        lda st_hi,x
        sta ev_rd+2
        ldy #0
        lda cnt,x
        bne @have
        jsr ev_rd                       ; a token
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
        jsr ev_rd                       ; distance in events
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
        sta rg_rd+2
        sta rg_wr+2
        lda mode,x
        bne @ring
        jsr ev_rd                       ; a literal event
        sta val
        iny
        jsr ev_rd
        sta evf
        iny
        bne @adv                        ; always (Y <= 4)
@ring:  sty tmp
        ldy src,x
        jsr rg_rd
        sta val
        iny
        jsr rg_rd
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
        jsr rg_wr
        iny
        lda evf
        jsr rg_wr
        iny
        tya
        sta w,x
        ldy evf                         ; frames after this one
        dey
        tya
        sta dur,x
        ldy reg,x
        lda val
        sta POKEY,y
        rts

ev_rd:  lda $FFFF,y                     ; the stream (patched)
        rts
rg_rd:  lda ring,y                      ; the ring of the stream (patched)
        rts
rg_wr:  sta ring,y
        rts

; ---------------------------------------------------------------------------
pks_silence:
        lda #0
        sta POKEY+1
        sta POKEY+3
        rts
