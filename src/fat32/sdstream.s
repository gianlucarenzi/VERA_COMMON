;-----------------------------------------------------------------------------
; sdstream.s - libvera: reading a file as one stream of sectors (sdfs.h).
;
; sd_stream_start (sdfs.s) checks that the open file is contiguous on the
; card and sends READ_MULTIPLE_BLOCK (CMD18) from its first sector, with the
; auto-tx of the VERA SPI on (sdcard_stream_start).  From then on the card
; sends the whole file, block after block, as fast as SPI_DATA is read:
;   [$FF ...] $FE  512 bytes  2 CRC bytes  [$FF ...] $FE  512 bytes ...
; Here the bytes go straight from SPI_DATA to the caller's memory or to
; VERA_DATA0: no command per sector, no copy out of sector_buffer, no FAT.
; About 14 cycles a byte (lda SPI_DATA / sta abs,y / iny / bne), against
; ~45 of fat32_read + sdcard_read_sector.
;
; Not in the FAT32 bank of the Atari (seg.inc): these functions touch only
; the SPI registers, their state and the destination.  The code is in
; LOWRODATA: on the Atari (cfg/atari-rambo.cfg) that is RAM below $4000,
; outside the bank window and out of the full MAIN area; elsewhere it is
; in MAIN like CODE.  It patches itself (sta base,y): RAM on every host.
; The SPI byte takes < 1 us (VERA 48.0.1): it is always there by the next
; read on a 1-2 MHz 6502.
;-----------------------------------------------------------------------------

.include "io.inc"

.import popax
.export _sd_stream_reset, _sd_stream_read, _sd_stream_vram

SPI_DATA    = VERA_SPI_DATA
VERA_DATA0  = VERA_BASE + $03

.segment "BSS"
blkl:   .res 1                          ; bytes left in this block, 0 = the next one
blkh:   .res 1
skip:   .res 1                          ; CRC bytes before the next token
mode:   .res 1                          ; 0 memory, 1 VERA_DATA0
nl:     .res 1                          ; bytes still to read
nh:     .res 1
totl:   .res 1                          ; the request, returned
toth:   .res 1
dstl:   .res 1
dsth:   .res 1
cl:     .res 1                          ; this chunk: 1-256 (min of n, blk, 256)
ch:     .res 1
ytmp:   .res 1

.segment "LOWRODATA"

;-----------------------------------------------------------------------------
; void sd_stream_reset(void): after sd_stream_start, before the first read
;-----------------------------------------------------------------------------
_sd_stream_reset:
        lda #0
        sta blkl
        sta blkh
        sta skip
        rts

;-----------------------------------------------------------------------------
; unsigned __fastcall__ sd_stream_read(void *dst, unsigned n)
; unsigned __fastcall__ sd_stream_vram(unsigned n)   (to VERA_DATA0)
; -> n, or 0 if the card sent no data token
;-----------------------------------------------------------------------------
_sd_stream_read:
        sta nl
        sta totl
        stx nh
        stx toth
        jsr popax
        sta dstl
        stx dsth
        lda #0
        beq run                         ; always

_sd_stream_vram:
        sta nl
        sta totl
        stx nh
        stx toth
        lda #1

run:    sta mode
@loop:  lda nl
        ora nh
        bne @more
        lda totl
        ldx toth
        rts

@more:  lda blkl
        ora blkh
        bne @have
        jsr next_block
        bcs @have
        lda #0                          ; no token: error
        tax
        rts

@have:  lda #0                          ; c = 256
        sta cl
        lda #1
        sta ch
        lda nl                          ; n < c: c = n
        cmp cl
        lda nh
        sbc ch
        bcs :+
        lda nl
        sta cl
        lda nh
        sta ch
:       lda blkl                        ; blk < c: c = blk
        cmp cl
        lda blkh
        sbc ch
        bcs :+
        lda blkl
        sta cl
        lda blkh
        sta ch
:       lda #0                          ; Y = 256 - c (c = 256: 0), up to 0
        sec
        sbc cl
        tay
        lda mode
        bne @vram

        sty ytmp                        ; sta base,y with base = dst - Y
        lda dstl
        sec
        sbc ytmp
        sta @sta + 1
        lda dsth
        sbc #0
        sta @sta + 2
@copy:  lda SPI_DATA                    ; 4  (auto-tx: starts the next byte)
@sta:   sta $FFFF,y                     ; 5
        iny                             ; 2
        bne @copy                       ; 3
        lda dstl                        ; dst += c
        clc
        adc cl
        sta dstl
        lda dsth
        adc ch
        sta dsth
        jmp @count

@vram:  lda SPI_DATA
        sta VERA_DATA0
        iny
        bne @vram

@count: lda nl                          ; n -= c, blk -= c
        sec
        sbc cl
        sta nl
        lda nh
        sbc ch
        sta nh
        lda blkl
        sec
        sbc cl
        sta blkl
        lda blkh
        sbc ch
        sta blkh
        jmp @loop

; the CRC of the block before, then the bytes up to the data token $FE
; C = 1: blk = 512; C = 0: no token in 65536 bytes
next_block:
        ldx skip
        beq @tok
@crc:   lda SPI_DATA
        dex
        bne @crc
@tok:   ldx #0
        ldy #0
@t:     lda SPI_DATA
        cmp #$FE
        beq @ok
        dey
        bne @t
        dex
        bne @t
        clc
        rts
@ok:    lda #<512
        sta blkl
        lda #>512
        sta blkh
        lda #2
        sta skip
        sec
        rts
