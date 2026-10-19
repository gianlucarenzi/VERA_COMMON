;-----------------------------------------------------------------------------
; fat32_vars.s - libvera: what the X16 DOS gives the FAT32 code
; (x16-rom dos/declare.s): the shared variables and the zero page.
;-----------------------------------------------------------------------------

.include "seg.inc"
.include "lib.inc"

.export fat32_dirent, fat32_size, fat32_errno, fat32_readonly, skip_mask

.segment "ZEROPAGE"
fat32_bufptr:       .res 2      ; in the sector buffer
fat32_lfn_bufptr:   .res 2      ; long name being decoded
fat32_ptr:          .res 2      ; argument: name, data
fat32_ptr2:         .res 2      ; second argument
nmos_t0:            .res 1      ; nmos.inc
nmos_t1:            .res 1

FAT32_BSS
fat32_dirent:       .tag dirent ; decoded directory entry
fat32_size:         .res 4      ; fat32_read, fat32_write, get_offset, get_free_space
fat32_errno:        .res 1      ; last error (ERRNO_*)
fat32_readonly:     .res 1      ; 1 = no writes
skip_mask:          .res 1      ; match_type: attributes to skip
