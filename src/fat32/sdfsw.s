;-----------------------------------------------------------------------------
; sdfsw.s - libvera: the C interface of the FAT32 code, writing (sdfs.h):
; sd_create, sd_write, sd_write_vram, sd_delete, sd_rename, sd_mkdir,
; sd_rmdir.  A module of its own, so that only the programs that write link
; it; nothing at all with FAT32_READONLY (libvera_sdro.lib).
;-----------------------------------------------------------------------------

.ifndef FAT32_READONLY

.include "seg.inc"
.include "lib.inc"

.import fat32_create, fat32_write, fat32_delete, fat32_rename
.import fat32_mkdir, fat32_rmdir, fat32_size
.import sd_set_name, sd_name_buf, sd_ret_carry
.import popax

.ifdef FAT32_BANKED
; in the RAMbo bank: called by the trampolines of src/atari/sdbankw.s
.export bk_sd_create := _sd_create, bk_sd_write := _sd_write
.export bk_sd_write_vram := _sd_write_vram, bk_sd_delete := _sd_delete
.export bk_sd_rename := _sd_rename, bk_sd_mkdir := _sd_mkdir
.export bk_sd_rmdir := _sd_rmdir
.else
.export _sd_create, _sd_write, _sd_write_vram, _sd_delete, _sd_rename
.export _sd_mkdir, _sd_rmdir
.endif

VERA_DATA0  = VERA_BASE + $03
NAME_MAX    = 128                   ; as sdfs.s

FAT32_BSS
name2_buf:  .res NAME_MAX           ; sd_rename: the new name
ret_tmp:    .res 1                  ; sd_create: overwrite

FAT32_CODE

;-----------------------------------------------------------------------------
; unsigned char __fastcall__ sd_create(const char *path, unsigned char overwrite)
; a new file, open to write (an existing one replaced if overwrite, else
; SD_ERR_EXISTS)
;-----------------------------------------------------------------------------
_sd_create:
	sta ret_tmp                     ; overwrite
	jsr popax
	jsr sd_set_name
	lda ret_tmp
	cmp #1                          ; C = overwrite != 0
	jsr fat32_create
	jmp sd_ret_carry

;-----------------------------------------------------------------------------
; unsigned char __fastcall__ sd_write(const void *src, unsigned n)
; unsigned char __fastcall__ sd_write_vram(unsigned n)
; n bytes to the file open to write (sd_write_vram: from the VERA data port
; 0, the address set by the caller); 1 = all written
;-----------------------------------------------------------------------------
_sd_write:
	sta fat32_size
	stx fat32_size + 1
	jsr popax
	sta fat32_ptr
	stx fat32_ptr + 1
	clc                             ; from memory
	bcc write

_sd_write_vram:
	sta fat32_size
	stx fat32_size + 1
	lda #<VERA_DATA0
	sta fat32_ptr
	lda #>VERA_DATA0
	sta fat32_ptr + 1
	sec                             ; every byte from the same address

write:
	lda fat32_size                  ; nothing to write: done
	ora fat32_size + 1
	beq @ok
	jsr fat32_write
	jmp sd_ret_carry
@ok:	sec
	jmp sd_ret_carry

;-----------------------------------------------------------------------------
; unsigned char __fastcall__ sd_delete(const char *path)
; unsigned char __fastcall__ sd_mkdir(const char *path)
; unsigned char __fastcall__ sd_rmdir(const char *path)  (an empty directory)
; unsigned char __fastcall__ sd_rename(const char *from, const char *to)
;-----------------------------------------------------------------------------
_sd_delete:
	jsr sd_set_name
	jsr fat32_delete
	jmp sd_ret_carry

_sd_mkdir:
	jsr sd_set_name
	jsr fat32_mkdir
	jmp sd_ret_carry

_sd_rmdir:
	jsr sd_set_name
	jsr fat32_rmdir
	jmp sd_ret_carry

_sd_rename:
	jsr sd_set_name                 ; to -> name_buf, then name2_buf
	ldy #NAME_MAX - 1
@cp:	lda sd_name_buf,y
	sta name2_buf,y
	dey
	bpl @cp
	lda #<name2_buf
	sta fat32_ptr2
	lda #>name2_buf
	sta fat32_ptr2 + 1
	jsr popax                       ; from -> name_buf, fat32_ptr
	jsr sd_set_name
	jsr fat32_rename
	jmp sd_ret_carry
.endif
