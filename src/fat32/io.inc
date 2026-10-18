;-----------------------------------------------------------------------------
; io.inc - libvera: the X16 io.inc symbols the FAT32 code uses, for every
; host.  The SPI of the SD card is in the VERA (VERA_BASE + $1E / $1F, $9F3E
; / $9F3F on the X16); VERA_BASE comes from the command line (-D), these
; sources are assembled with -t none so that character constants stay ASCII.
;-----------------------------------------------------------------------------

.ifndef VERA_BASE
.error "fat32: assemble with -D VERA_BASE=$xxxx"
.endif

VERA_SPI_DATA = VERA_BASE + $1E
VERA_SPI_CTRL = VERA_BASE + $1F

.include "nmos.inc"
