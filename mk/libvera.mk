# libvera.mk - build a program with libvera, for one host.
#
#   VERA_COMMON = /path/to/VERA_COMMON
#   PLATFORM    = atari            # or c64, cx16, apple2
#   include $(VERA_COMMON)/mk/libvera.mk
#
#   game.xex: main.o $(LIBVERA_LIB)
#   	$(LD65) $(LIBVERA_LDFLAGS) -o $@ main.o $(LIBVERA_LIB) $(PLATFORM).lib
#
# The library is built by `make -C $(VERA_COMMON)` (both hosts).
# C64: the card at $DF00 (IO2, its GeoRAM at $DE00); VERA_BASE=0xDE00 for a
# card in IO1 without GeoRAM (rebuild the library with it too).
# C64_CARD_SEL=0: no write of 1 to the RBL-C64 select latch at $DFFD at
# start-up (a card without the latch, or $DFFD left alone); on the RBL-C64
# the VERA is then not selected by the program and does not answer (its
# GeoRAM is always active) (the library rebuilds plat_c64.o by itself when
# it changes).
# Apple II: the A2VERA card in slot 4, $C400 (a2emu A2_VERA_SLOT=4);
# VERA_BASE=0xCn00 for slot n (rebuild the library with it too).

PLATFORM ?= atari
ifeq ($(filter atari c64 cx16 apple2,$(PLATFORM)),)
$(error PLATFORM must be atari, c64, cx16 or apple2, not '$(PLATFORM)')
endif

ifeq ($(PLATFORM),c64)
VERA_BASE ?= 0xDF00
C64_CARD_SEL ?= 1
LIBVERA_C64_ASM = -D C64_CARD_SEL=$(C64_CARD_SEL)
else ifeq ($(PLATFORM),apple2)
VERA_BASE ?= 0xC400
endif
ifneq ($(filter c64 apple2,$(PLATFORM)),)
LIBVERA_BASE_C   = -DVERA_BASE=$(VERA_BASE)u
LIBVERA_BASE_ASM = -D 'VERA_BASE=$$$(patsubst 0x%,%,$(patsubst 0X%,%,$(VERA_BASE)))'
endif

LIBVERA_DIR     = $(VERA_COMMON)/build/$(PLATFORM)
LIBVERA_LIB     = $(LIBVERA_DIR)/libvera.lib
LIBVERA_LZS     = $(LIBVERA_DIR)/lzsplayr.o     # link before the lib: SAP/XEX songs
LIBVERA_SD_LIB  = $(LIBVERA_DIR)/libvera_sd.lib # link before the lib: asset.h from the microSD (Atari, C64, Apple II)
LIBVERA_DSK_LIB = $(LIBVERA_DIR)/libvera_dsk.lib # link before the lib: asset.h from a DOS 2 disk, music safe (Atari)
LIBVERA_RMT8_LIB = $(LIBVERA_DIR)/libvera_rmt8.lib # link before the lib: RMT8 (stereo) songs, Atari rmt_init_hybrid
# Atari: LIBVERA_RAMBO = 1 (needed with LIBVERA_SD_LIB) -> cfg/atari-rambo.cfg,
# the FAT32 code in a RAMbo bank (src/atari/sdbank.s)
# Apple II: LIBVERA_HGR = 1 -> cfg/apple2-hgr.cfg, the HGR page 1 kept free
# (the program in two pieces around $2000-$3FFF, for a loader of its own)
LIBVERA_CFG     = $(VERA_COMMON)/cfg/$(PLATFORM)$(if $(filter atari,$(PLATFORM)),$(if $(filter 1,$(LIBVERA_RAMBO)),-rambo))$(if $(filter apple2,$(PLATFORM)),$(if $(filter 1,$(LIBVERA_HGR)),-hgr)).cfg

LIBVERA_CFLAGS  = -t $(PLATFORM) -I $(VERA_COMMON)/include $(LIBVERA_BASE_C)
LIBVERA_ASFLAGS = -t $(PLATFORM) -I $(VERA_COMMON)/include $(LIBVERA_BASE_ASM) $(LIBVERA_C64_ASM)
LIBVERA_LDFLAGS = -C $(LIBVERA_CFG) $(LIBVERA_START)

# Atari: the program starts at $2400, above the MEMLO of DOS 2.5 with its
# buffers (cc65's default $2000 is too close)
ifeq ($(PLATFORM),atari)
LIBVERA_START = --start-addr 0x2400
endif

# executable suffix: XEX on the Atari, PRG on the C64 and the X16, BIN on
# the Apple II (a raw image at $0900 for the a2fs boot sector)
ifeq ($(PLATFORM),atari)
EXE = xex
else ifeq ($(PLATFORM),apple2)
EXE = bin
else
EXE = prg
endif
