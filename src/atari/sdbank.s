; ============================================================================
; sdbank.s - libvera, Atari: the FAT32 code in a RAMbo bank (sdfs.h)
;
; The VERA board of the Atari carries a RAMbo 256K (atari800 -verax16 gives
; the machine 320 KB): PORTB bits 2, 3, 5, 6 select a 16 KB bank, bit 4 = 0
; shows it to the CPU at $4000-$7FFF instead of the main RAM.  The FAT32
; code and its buffers (src/fat32, assembled with -D FAT32_BANKED=1: the
; BANKCODE / BANKBSS segments, functions bk_sd_*) live in bank SD_BANK;
; these are the C functions of sdfs.h, which switch the bank in around the
; call and out again.  The OS stays on: the VBI, the IRQs and the music
; keep running while the bank is in, so nothing they use may be in
; $4000-$7FFF (cfg/atari-rambo.cfg: only the GAMECODE / GAMERODATA segments of
; the program go there).  What the FAT32 code reads from the caller is
; copied out of the window first:
;   the path         -> path_buf
;   sd_read to a dst in $4000-$7FFF -> through bounce (256 bytes a time)
;   sd_dirent        <- copied from the bank after sd_readdir
;
; Loading: chunks of the executable (cfg/atari-rambo.cfg) switch the bank in
; (and clear BANKBSS), load BANKCODE at $4000, switch it out; then the
; program loads at $4000 in the main RAM.
; ============================================================================

        .export _sd_mount, _sd_open, _sd_read, _sd_read_vram, _sd_close
        .export _sd_opendir, _sd_readdir, _sd_chdir, _sd_errno, _sd_dirent
        .export _sd_stream_start, _sd_stream_stop
        .import bk_sd_mount, bk_sd_open, bk_sd_read, bk_sd_read_vram
        .import bk_sd_close, bk_sd_opendir, bk_sd_readdir, bk_sd_chdir
        .import bk_sd_errno, bk_sd_dirent
        .import bk_sd_stream_start, bk_sd_stream_stop
        .import popax, pushax
        .importzp ptr1, ptr2
        .import __BANKON_LOAD__, __BANKON_SIZE__
        .import __BANKOFF_LOAD__, __BANKOFF_SIZE__
        .import __BANK_START__, __BANKCODE_LOAD__, __BANKCODE_SIZE__
        .import __BANKBSS_RUN__, __BANKBSS_SIZE__
        .forceimport __ATARI_RAMBO_CFG__ ; cfg/atari-rambo.cfg, not atari.cfg

PORTB       = $D301
INITAD      = $02E2
SD_BANK     = %00000000                 ; bits 2, 3, 5, 6; bit 4 = 0: CPU
KEEP        = %10000011                 ; self test, BASIC, OS ROM bits
PATH_MAX    = 128                       ; as NAME_MAX of sdfs.s
DIRENT_SIZE = 256 + 1 + 4 + 4 + 6       ; struct sd_dirent

        .bss
_sd_dirent: .res DIRENT_SIZE
path_buf:   .res PATH_MAX
bounce:     .res 256
save:       .res 1                      ; PORTB before the bank
ta:         .res 1
tx:         .res 1
nl:         .res 1                      ; sd_read: bytes still to read
nh:         .res 1
cl:         .res 1                      ; this chunk
ch:         .res 1
gl:         .res 1                      ; read so far
gh:         .res 1

.macro  BANK_IN                         ; A lost
        lda PORTB
        sta save
        and #KEEP
        ora #SD_BANK
        sta PORTB
.endmacro

.macro  BANK_OUT                        ; A, X kept
        ldy save
        sty PORTB
.endmacro

        .code

; call A/X -> bk function with the bank in, A/X back
.macro  CALL fn
        sta ta
        stx tx
        BANK_IN
        lda ta
        ldx tx
        jsr fn
        BANK_OUT
        rts
.endmacro

_sd_mount:      CALL bk_sd_mount
_sd_close:      CALL bk_sd_close
_sd_errno:      CALL bk_sd_errno
_sd_read_vram:  CALL bk_sd_read_vram
_sd_stream_start: CALL bk_sd_stream_start
_sd_stream_stop:  CALL bk_sd_stream_stop

; A/X = C string -> path_buf, A/X = path_buf
copy_path:
        sta ptr1
        stx ptr1+1
        ldy #0
:       lda (ptr1),y
        sta path_buf,y
        beq :+
        iny
        cpy #PATH_MAX - 1
        bne :-
        lda #0
        sta path_buf,y
:       lda #<path_buf
        ldx #>path_buf
        rts

_sd_open:
        jsr copy_path
        CALL bk_sd_open
_sd_opendir:
        jsr copy_path
        CALL bk_sd_opendir
_sd_chdir:
        jsr copy_path
        CALL bk_sd_chdir

_sd_readdir:
        BANK_IN
        jsr bk_sd_readdir
        sta ta
        ldy #0                          ; the entry out of the bank
:       lda bk_sd_dirent,y
        sta _sd_dirent,y
        iny
        bne :-
        ldy #DIRENT_SIZE - 256 - 1
:       lda bk_sd_dirent + 256,y
        sta _sd_dirent + 256,y
        dey
        bpl :-
        lda ta
        ldx #0
        BANK_OUT
        rts

; unsigned __fastcall__ sd_read(void *dst, unsigned n)
_sd_read:
        sta nl
        stx nh
        jsr popax                       ; dst
        sta ptr2
        stx ptr2+1
        cpx #$80                        ; dst .. dst + n - 1 outside $4000-$7FFF:
        bcs @direct                     ; straight there
        lda ptr2
        clc
        adc nl
        tay
        lda ptr2+1
        adc nh
        cpy #1                          ; high byte of dst + n - 1
        sbc #0
        cmp #$40
        bcs @bounce
@direct:
        lda ptr2
        ldx ptr2+1
        jsr pushax
        BANK_IN
        lda nl
        ldx nh
        jsr bk_sd_read
        BANK_OUT
        rts

@bounce:
        lda #0
        sta gl
        sta gh
@chunk: lda nl                          ; chunk = min(n, 256)
        ora nh
        bne :+
        jmp @done
:       lda nh
        beq :+
        lda #0
        sta cl
        lda #1
        sta ch
        bne @read
:       lda nl
        sta cl
        lda #0
        sta ch
@read:  lda #<bounce
        ldx #>bounce
        jsr pushax
        BANK_IN
        lda cl
        ldx ch
        jsr bk_sd_read                  ; A/X = got (<= chunk)
        BANK_OUT
        sta ta
        stx tx
        ora tx
        beq @done                       ; end of file / error
        ldy #0                          ; bounce -> dst, got bytes (1-256)
:       lda bounce,y
        sta (ptr2),y
        iny
        cpy ta
        bne :-
        lda ta                          ; dst += got, n -= got, g += got
        ldx tx                          ; (got = 256: ta = 0, tx = 1)
        clc
        adc ptr2
        sta ptr2
        txa
        adc ptr2+1
        sta ptr2+1
        lda nl
        sec
        sbc ta
        sta nl
        lda nh
        sbc tx
        sta nh
        lda gl
        clc
        adc ta
        sta gl
        lda gh
        adc tx
        sta gh
        lda ta                          ; got < chunk: end of file
        cmp cl
        bne @done
        lda tx
        cmp ch
        bne @done
        jmp @chunk
@done:  lda gl
        ldx gh
        rts

; ---------------------------------------------------------------------------
; load chunks (cfg/atari-rambo.cfg): bank in + BANKBSS cleared, BANKCODE, bank out

        .segment "BANKONHDR"
        .word __BANKON_LOAD__
        .word __BANKON_LOAD__ + __BANKON_SIZE__ - 1

        .segment "BANKON"
bank_on:
        lda PORTB
        sta load_portb
        and #KEEP
        ora #SD_BANK
        sta PORTB
        lda #>__BANKBSS_RUN__           ; clear BANKBSS (whole pages from its
        sta @dst+2                      ; start: it is at the end of the bank)
        ldx #>(__BANKBSS_SIZE__ + (__BANKBSS_RUN__ & $FF) + 255)
        lda #0
        ldy #<__BANKBSS_RUN__
@dst:   sta $FF00,y
        iny
        bne @dst
        inc @dst+2
        dex
        bne @dst
        rts
load_portb: .byte 0

        .segment "BANKONTRL"
        .word INITAD
        .word INITAD + 1
        .word bank_on

        .segment "BANKHDR"
        .word __BANK_START__
        .word __BANKCODE_LOAD__ + __BANKCODE_SIZE__ - 1

        .segment "BANKOFFHDR"
        .word __BANKOFF_LOAD__
        .word __BANKOFF_LOAD__ + __BANKOFF_SIZE__ - 1

        .segment "BANKOFF"
bank_off:
        lda load_portb
        sta PORTB
        rts

        .segment "BANKOFFTRL"
        .word INITAD
        .word INITAD + 1
        .word bank_off
