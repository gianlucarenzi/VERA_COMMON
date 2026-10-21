;-----------------------------------------------------------------------------
; sdfs.s - libvera: the C interface of the FAT32 code (sdfs.h).
;
; Assembled with -t none like the rest of src/fat32 (character constants in
; ASCII); -D PETSCII=1 on the C64 and the X16, where cc65 C strings are
; PETSCII: the names are converted to ASCII on the way in.
;-----------------------------------------------------------------------------

.include "seg.inc"
.include "lib.inc"

.import sdcard_init, sdcard_set_fast_mode
.import fat32_init, fat32_alloc_context, fat32_set_context
.import fat32_open, fat32_read, fat32_close
.import fat32_open_dir, fat32_read_dirent, fat32_chdir
.import fat32_dirent, fat32_size, fat32_errno
.import fat32_contiguous, fat32_stream_lba, sector_lba
.import sdcard_stream_start, sdcard_stream_stop
.import popax

.ifdef FAT32_BANKED
; in the RAMbo bank (seg.inc): the C names are the trampolines of
; src/atari/sdbank.s, which call these with the bank in
.export bk_sd_mount := _sd_mount, bk_sd_open := _sd_open, bk_sd_read := _sd_read
.export bk_sd_read_vram := _sd_read_vram, bk_sd_close := _sd_close
.export bk_sd_opendir := _sd_opendir, bk_sd_readdir := _sd_readdir
.export bk_sd_chdir := _sd_chdir, bk_sd_errno := _sd_errno
.export bk_sd_stream_start := _sd_stream_start, bk_sd_stream_stop := _sd_stream_stop
.export bk_sd_dirent := fat32_dirent
.else
.export _sd_mount, _sd_open, _sd_read, _sd_read_vram, _sd_close
.export _sd_opendir, _sd_readdir, _sd_chdir, _sd_errno
.export _sd_stream_start, _sd_stream_stop
.export _sd_dirent := fat32_dirent
.endif

VERA_DATA0  = VERA_BASE + $03
NAME_MAX    = 128

FAT32_BSS
name_buf:   .res NAME_MAX           ; the name, in ASCII

FAT32_CODE

; C = 1 -> A/X = 1, else 0
ret_carry:
	lda #0
	tax
	rol a
	rts

;-----------------------------------------------------------------------------
; unsigned char sd_mount(void)
;-----------------------------------------------------------------------------
_sd_mount:
	jsr sdcard_init                 ; as the X16 DOS does before fat32_init
	bcc ret_carry
	lda #1                          ; sector reads with SPI auto-tx (the
	jsr sdcard_set_fast_mode        ; VERA boards: bitstream 48.0.1)
	jsr fat32_init
	bcc ret_carry
	lda #0                          ; volume 0
	jsr fat32_alloc_context
	bcc ret_carry
	jsr fat32_set_context
	jmp ret_carry

;-----------------------------------------------------------------------------
; A/X = C string -> fat32_ptr = name_buf (ASCII, at most NAME_MAX - 1)
;-----------------------------------------------------------------------------
set_name:
	sta fat32_ptr
	stx fat32_ptr + 1
	ldy #0
@l:	lda (fat32_ptr),y
	beq @end
.ifdef PETSCII
	cmp #$41                        ; PETSCII a-z ($41-$5A) -> ASCII $61-$7A
	bcc @put
	cmp #$5B
	bcs @hi
	ora #$20
	bne @put                        ; always
@hi:	cmp #$C1                        ; PETSCII A-Z ($C1-$DA) -> ASCII $41-$5A
	bcc @put
	cmp #$DB
	bcs @put
	and #$7F
.endif
@put:	sta name_buf,y
	iny
	cpy #NAME_MAX - 1
	bne @l
@end:	lda #0
	sta name_buf,y
	lda #<name_buf
	sta fat32_ptr
	lda #>name_buf
	sta fat32_ptr + 1
	rts

;-----------------------------------------------------------------------------
; unsigned char __fastcall__ sd_open(const char *path)
;-----------------------------------------------------------------------------
_sd_open:
	jsr set_name
	jsr fat32_open
	jmp ret_carry

;-----------------------------------------------------------------------------
; unsigned __fastcall__ sd_read(void *dst, unsigned n)
; unsigned __fastcall__ sd_read_vram(unsigned n)
;-----------------------------------------------------------------------------
_sd_read:
	sta fat32_size
	stx fat32_size + 1
	jsr popax
	sta fat32_ptr
	stx fat32_ptr + 1
	clc                             ; to memory
	bcc read

_sd_read_vram:
	sta fat32_size
	stx fat32_size + 1
	lda #<VERA_DATA0
	sta fat32_ptr
	lda #>VERA_DATA0
	sta fat32_ptr + 1
	sec                             ; stream: every byte to the same address

read:
	lda #0
	sta fat32_size + 2
	sta fat32_size + 3
	jsr fat32_read                  ; fat32_size = bytes read
	lda fat32_size
	ldx fat32_size + 1
	rts

;-----------------------------------------------------------------------------
; void sd_close(void)
;-----------------------------------------------------------------------------
_sd_close:
	jmp fat32_close

;-----------------------------------------------------------------------------
; unsigned char sd_stream_start(void)
; void sd_stream_stop(void)
; (the reads in between: src/fat32/sdstream.s)
;-----------------------------------------------------------------------------
_sd_stream_start:
	jsr fat32_contiguous            ; one run of sectors?
	bcc @no
	ldx #3
@lba:	lda fat32_stream_lba,x
	sta sector_lba,x
	dex
	bpl @lba
	jsr sdcard_stream_start
@no:	jmp ret_carry

_sd_stream_stop:
	jmp sdcard_stream_stop

;-----------------------------------------------------------------------------
; unsigned char __fastcall__ sd_opendir(const char *path)
; unsigned char sd_readdir(void)
; unsigned char __fastcall__ sd_chdir(const char *path)
;-----------------------------------------------------------------------------
_sd_opendir:
	jsr set_name
	lda name_buf                    ; "" -> fat32_ptr = 0: the current one
	bne @open
	sta fat32_ptr
	sta fat32_ptr + 1
@open:	jsr fat32_open_dir
	jmp ret_carry

_sd_readdir:
	jsr fat32_read_dirent
	jmp ret_carry

_sd_chdir:
	jsr set_name
	jsr fat32_chdir
	jmp ret_carry

;-----------------------------------------------------------------------------
; unsigned char sd_errno(void)
;-----------------------------------------------------------------------------
_sd_errno:
	lda fat32_errno
	ldx #0
	rts
