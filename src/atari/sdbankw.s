;-----------------------------------------------------------------------------
; sdbankw.s - libvera, Atari: the trampolines of the writing on the SD
; (sdfs.h: sd_create, sd_write, sd_write_vram, sd_delete, sd_rename,
; sd_mkdir, sd_rmdir) to the FAT32 code in its RAMbo bank (src/fat32/sdfsw.s),
; as sdbank.s for the rest.  A module of its own: only the programs that
; write link it (and sdfsw.s in the bank).
;-----------------------------------------------------------------------------

        .export _sd_create, _sd_write, _sd_write_vram, _sd_delete
        .export _sd_rename, _sd_mkdir, _sd_rmdir
        .import bk_sd_create, bk_sd_write, bk_sd_write_vram, bk_sd_delete
        .import bk_sd_rename, bk_sd_mkdir, bk_sd_rmdir
        .import sdb_copy_path, sdb_path
        .import sdb_save, sdb_ta, sdb_tx, sdb_bounce
        .import sdb_cl, sdb_ch, sdb_nl, sdb_nh
        .import popax, pushax
        .importzp ptr2

SAVE = sdb_save
TA   = sdb_ta
TX   = sdb_tx

        .include "sdbank.inc"

        .bss
path2_buf:  .res PATH_MAX               ; sd_rename: the new name

        .code

_sd_write_vram: CALL bk_sd_write_vram

_sd_delete:
        jsr sdb_copy_path
        CALL bk_sd_delete
_sd_mkdir:
        jsr sdb_copy_path
        CALL bk_sd_mkdir
_sd_rmdir:
        jsr sdb_copy_path
        CALL bk_sd_rmdir

; unsigned char __fastcall__ sd_create(const char *path, unsigned char overwrite)
_sd_create:
        sta sdb_cl                      ; overwrite
        jsr popax
        jsr sdb_copy_path
        jsr pushax
        lda sdb_cl
        ldx #0
        CALL bk_sd_create

; unsigned char __fastcall__ sd_rename(const char *from, const char *to)
_sd_rename:
        jsr sdb_copy_path               ; to -> path_buf, then path2_buf
        ldy #PATH_MAX - 1
:       lda sdb_path,y
        sta path2_buf,y
        dey
        bpl :-
        jsr popax                       ; from -> path_buf
        jsr sdb_copy_path
        jsr pushax
        lda #<path2_buf
        ldx #>path2_buf
        CALL bk_sd_rename

; unsigned char __fastcall__ sd_write(const void *src, unsigned n): 256 bytes
; at a time through bounce (src may be in the window of the bank); 1 = all
_sd_write:
        sta sdb_nl
        stx sdb_nh
        jsr popax                       ; src
        sta ptr2
        stx ptr2+1
@chunk: lda sdb_nl                      ; chunk = min(n, 256)
        ora sdb_nh
        beq @ok
        lda sdb_nh
        beq :+
        lda #0
        sta sdb_cl
        lda #1
        sta sdb_ch
        bne @copy
:       lda sdb_nl
        sta sdb_cl
        lda #0
        sta sdb_ch
@copy:  ldy #0                          ; src -> bounce
:       lda (ptr2),y
        sta sdb_bounce,y
        iny
        cpy sdb_cl
        bne :-
        lda #<sdb_bounce
        ldx #>sdb_bounce
        jsr pushax
        BANK_IN
        lda sdb_cl
        ldx sdb_ch
        jsr bk_sd_write                 ; 1 = written
        BANK_OUT
        cmp #0
        beq @fail
        lda sdb_cl                      ; src += chunk, n -= chunk
        clc                             ; (chunk = 256: cl = 0, ch = 1)
        adc ptr2
        sta ptr2
        lda sdb_ch
        adc ptr2+1
        sta ptr2+1
        lda sdb_nl
        sec
        sbc sdb_cl
        sta sdb_nl
        lda sdb_nh
        sbc sdb_ch
        sta sdb_nh
        jmp @chunk
@ok:    lda #1
        ldx #0
        rts
@fail:  lda #0
        tax
        rts

