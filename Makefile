# Makefile - libvera: the VERA library shared by the Atari XL/XE (PBI), the
# C64 (expansion port), the Commander X16 and the Apple IIe (A2VERA card in
# slot 4), and its test program.
#
#   make                      every host: build/<host>/libvera.lib, the test,
#                             the disk images (vera-atari.atr, vera-c64.d64,
#                             vera-apple2.dsk + its microSD vera-apple2-sd.img;
#                             X16: the directory build/cx16/disk)
#   make PLATFORM=atari one   one host only
#   make run-atari | run-c64 | run-x16 | run-apple2   start the emulator on the test
#   make clean
#
# VICE: virtual drive 8 (+drive8truedrive -trapdevice8): the KERNAL file
# calls are trapped, the data files load in a moment instead of minutes.
# The host window is small: it is the second monitor; the VERA window is
# the game screen.
#
# Tools: cc65 (cl65, ca65, ar65), python3, dir2atr (Atari), c1541 (C64),
# a2fs (Apple: a2emu-vera's make install), mkfs.fat + mtools (microSD images).

VERA_COMMON := $(abspath .)
include mk/libvera.mk

CC65     ?= cc65
CA65     ?= ca65
CL65     ?= cl65
AR65     ?= ar65
PYTHON   ?= python3
DIR2ATR  ?= dir2atr
C1541    ?= c1541
ATARI800 ?= atari800
VICE     ?= x64sc
X16EMU   ?= x16emu
A2EMU    ?= a2emu
A2FS     ?= a2fs
# a2emu: unenhanced IIe (6502), the A2VERA card's slot from VERA_BASE ($Cn00)
A2_MODEL ?= iie
A2_SLOT   = $(shell printf %d $$(( ($(or $(VERA_BASE),0xC400) >> 8) & 7 )))
# x16emu CPU clock: 4 MHz, at 8 x16emu is below real time on our PCs
X16_MHZ  ?= 4
# Projects dir: ~/Progetti, or ~/Progetti-CVS when ~/Progetti is a symlink
ifndef PROJECTS
PROJECTS := $(shell if [ -L $(HOME)/Progetti ]; then echo $(HOME)/Progetti-CVS; else echo $(HOME)/Progetti; fi)
endif
# the PBI ROM of the card (atari800 needs it to map the card)
VERA_ROM ?= $(PROJECTS)/ATARI/VERA_ATARI_PBI/vera_pbi_handler.rom

B        = build/$(PLATFORM)
RMT_TRACKS = 4

CFLAGS  = $(LIBVERA_CFLAGS) -Osir
ASFLAGS = $(LIBVERA_ASFLAGS) -I src/rmt --bin-include-dir fonts \
          -D RMT_SHADOW -D RMT_VERA
ASFLAGS4 = -D RMT_TRACKS=$(RMT_TRACKS) -D RMT_TUNED

C_SRC   = src/common/asset.c src/common/vera_detect.c src/common/vtext.c \
          src/common/vbm.c src/common/vtm_loader.c src/common/pcm_load.c
AS_SRC  = src/common/vera_irq.s src/common/vmem.s src/common/vtm_player.s \
          src/common/vtfont.s src/common/hud.s src/common/bcd.s src/common/sfx.s src/common/pcm.s src/$(PLATFORM)/plat_$(PLATFORM).s \
          src/rmt/rmtplayr.s src/rmt/psgrmt.s src/rmt/rmtdrv.s src/rmt/rmtrmt.s src/rmt/rmtpsg.s src/rmt/rmtio.s
# rmt_out_host: the music on the host chip (Atari POKEY, C64 SID)
ifeq ($(PLATFORM),atari)
AS_SRC += src/atari/rmtpokey.s src/atari/basicoff.s src/atari/xexchunks.s src/atari/osram.s
else ifeq ($(PLATFORM),c64)
AS_SRC += src/c64/rmtsid.s src/c64/rmtsds.s
HOST_OBJS = $(B)/sidtab.o
else ifeq ($(PLATFORM),cx16)
AS_SRC += src/cx16/macptr.s
endif
OBJS    = $(patsubst src/%.c,$(B)/%.o,$(C_SRC)) $(patsubst src/%.s,$(B)/%.o,$(AS_SRC)) \
          $(B)/psgtab.o $(HOST_OBJS)

# libvera_rmt8.lib: the RMT player and its outputs built for 8 tracks (RMT8,
# stereo songs), linked before libvera.lib.  Both players use the tuned
# pure tone table (RMT_TUNED, rmtplayr.s: A = 440 Hz on a PAL POKEY).  Atari: + rmt_init_hybrid
# (tracks 1-4 on POKEY, 5-8 on the VERA PSG)
RMT8_SRC = src/rmt/rmtplayr.s src/rmt/psgrmt.s src/rmt/rmtdrv.s src/rmt/rmtrmt.s \
           src/rmt/rmtpsg.s src/rmt/rmtio.s
ifeq ($(PLATFORM),atari)
RMT8_SRC += src/atari/rmtpokey.s src/atari/rmthyb.s
endif
RMT8_OBJS = $(patsubst src/%.s,$(B)/rmt8/%.o,$(RMT8_SRC))

# FAT32 assembly modules (must be assembled with -t none to keep ASCII chars)
# VERA_BASE: $D100 on Atari, $DF00 on C64 (default), $9F20 on X16
# PETSCII: only on C64 and X16 (Atari uses ASCII natively)
# Atari: in a RAMbo bank (FAT32_BANKED, src/fat32/seg.inc), called through
# the trampolines of src/atari/sdbank.s
ifeq ($(PLATFORM),atari)
FAT32_VERA_BASE = 0xD100
FAT32_PETSCII =
FAT32_BANK = -D FAT32_BANKED=1
else ifeq ($(PLATFORM),c64)
FAT32_VERA_BASE = $(VERA_BASE)
FAT32_PETSCII = -D PETSCII=1
else ifeq ($(PLATFORM),apple2)
FAT32_VERA_BASE = $(VERA_BASE)
FAT32_PETSCII =
else
FAT32_VERA_BASE = 0x9F20
FAT32_PETSCII = -D PETSCII=1
endif

FAT32_OBJS = $(patsubst src/fat32/%.s,$(B)/fat32_%.o,$(wildcard src/fat32/*.s))
ifeq ($(PLATFORM),atari)
FAT32_OBJS += $(B)/atari/sdbank.o
endif

$(B)/fat32_%.o: src/fat32/%.s $(wildcard src/fat32/*.inc)
	@mkdir -p $(B)
	$(CA65) -t none --cpu 6502 -D VERA_BASE=$(FAT32_VERA_BASE) $(FAT32_PETSCII) $(FAT32_BANK) \
	    -I src/fat32 -I include -o $@ $<

HEADERS = $(wildcard include/*.h)
ASINC   = include/vera.inc include/plat.inc src/rmt/rmt_feat.inc

.PHONY: all one lib test disk run-atari run-c64 run-x16 run-apple2 clean prof-pcm prof-sfx

all:
	$(MAKE) PLATFORM=atari one
	$(MAKE) PLATFORM=c64 one
	$(MAKE) PLATFORM=cx16 one
	$(MAKE) PLATFORM=apple2 one

one: lib test disk

lib: $(LIBVERA_LIB) $(LIBVERA_LZS) $(if $(filter cx16,$(PLATFORM)),,$(LIBVERA_SD_LIB)) \
     $(if $(filter atari,$(PLATFORM)),$(LIBVERA_DSK_LIB)) $(LIBVERA_RMT8_LIB)

$(LIBVERA_LIB): $(OBJS)
	rm -f $@
	$(AR65) a $@ $^

# Atari: the asset.h functions on the raw sectors of a DOS 2 disk, own SIO
# The modules of libvera.lib that call asset.h (ASSET_USERS) are in the asset
# libraries too: ld65 does not go back to a library, so a program that calls
# them but not asset_* itself would otherwise get the asset.o of libvera.lib
# (the disk of the OS) instead of the one of the library it links first.
ASSET_USERS = $(B)/common/pcm_load.o $(B)/common/vbm.o $(B)/common/vtm_loader.o

$(LIBVERA_DSK_LIB): $(B)/atari/asset_dsk.o $(B)/atari/sio.o $(ASSET_USERS)
	rm -f $@
	$(AR65) a $@ $^

$(LIBVERA_RMT8_LIB): $(RMT8_OBJS)
	rm -f $@
	$(AR65) a $@ $^

$(B)/rmt8/%.o: src/%.s $(ASINC)
	@mkdir -p $(dir $@)
	$(CA65) $(ASFLAGS) -D RMT_TRACKS=8 -D RMT_TUNED -o $@ $<

# the asset.h functions on the microSD and the FAT32 code they use
$(LIBVERA_SD_LIB): $(B)/common/asset_sd.o $(FAT32_OBJS) $(ASSET_USERS)
	rm -f $@
	$(AR65) a $@ $^

$(B)/%.o: src/%.c $(HEADERS)
	@mkdir -p $(dir $@)
	$(CC65) $(CFLAGS) -o $(B)/$*.s $<
	$(CA65) $(LIBVERA_ASFLAGS) -o $@ $(B)/$*.s

$(B)/%.o: src/%.s $(ASINC)
	@mkdir -p $(dir $@)
	$(CA65) $(ASFLAGS) $(ASFLAGS4) -o $@ $<

$(B)/psgtab.s: tools/mkpsgtab.py
	@mkdir -p $(B)
	$(PYTHON) $< $@

$(B)/sidtab.s: tools/mksidtab.py
	@mkdir -p $(B)
	$(PYTHON) $< $@

$(B)/sidtab.o: $(B)/sidtab.s
	$(CA65) $(ASFLAGS) -o $@ $<

$(B)/psgtab.o: $(B)/psgtab.s
	$(CA65) $(ASFLAGS) -o $@ $<

$(LIBVERA_LZS): src/rmt/lzsplayr.s $(ASINC)
	$(CA65) $(ASFLAGS) -o $@ $<

# --- the test program -------------------------------------------------------

TEST_SONG = tests/data/gemx.rmt
TEST_EXE  = $(B)/testlib.$(EXE)

test: $(TEST_EXE)

$(B)/song.s: $(TEST_SONG) tools/rmt2ca65.py
	@mkdir -p $(B)
	$(PYTHON) tools/rmt2ca65.py $< $@

$(B)/song.o: $(B)/song.s
	$(CA65) $(ASFLAGS) -o $@ $<

$(B)/test_lib.o: tests/test_lib.c $(HEADERS)
	$(CC65) $(CFLAGS) -o $(B)/test_lib.s $<
	$(CA65) $(LIBVERA_ASFLAGS) -o $@ $(B)/test_lib.s

# Apple II: no DOS, the data from the microSD
TEST_ASSET_LIB = $(if $(filter apple2,$(PLATFORM)),$(LIBVERA_SD_LIB))

$(TEST_EXE): $(B)/test_lib.o $(B)/song.o $(TEST_ASSET_LIB) $(LIBVERA_LIB) $(LIBVERA_CFG)
	$(CL65) -t $(PLATFORM) $(LIBVERA_LDFLAGS) -m $(B)/testlib.map -o $@ \
	    $(B)/test_lib.o $(B)/song.o $(TEST_ASSET_LIB) $(LIBVERA_LIB)

# --- disk images: the same data files on both -------------------------------

TEST_DATA = tests/data/demo.vbm

ifeq ($(PLATFORM),atari)
DISK = vera-atari.atr
$(DISK): $(TEST_EXE) $(TEST_DATA)
	rm -rf $(B)/disk && mkdir -p $(B)/disk
	cp tools/dos/dos25/DOS.SYS $(B)/disk/DOS.SYS
	cp $(TEST_EXE) $(B)/disk/AUTORUN.SYS
	for f in $(TEST_DATA); do n=$$(basename $$f | tr a-z A-Z); cp $$f $(B)/disk/$$n; done
	$(DIR2ATR) -E -b Dos25 $@ $(B)/disk > /dev/null
else ifeq ($(PLATFORM),cx16)
# the X16 reads a host directory as drive 8 (x16emu -fsroot)
DISK = $(B)/disk/TESTLIB.PRG
$(DISK): $(TEST_EXE) $(TEST_DATA)
	rm -rf $(B)/disk && mkdir -p $(B)/disk
	cp $(TEST_EXE) $@
	cp $(TEST_DATA) $(B)/disk/
else ifeq ($(PLATFORM),apple2)
# a Disk II floppy that boots the program (a2fs: the a2emu-vera SDK boot
# sector, no DOS), the data on the microSD
DISK = vera-apple2.dsk
TEST_SD = vera-apple2-sd.img
$(DISK): $(TEST_EXE) $(TEST_SD)
	$(A2FS) mkimage $@ $(TEST_EXE) --himem 0xBF00
$(TEST_SD): $(TEST_DATA) tools/mksdimg.py
	$(PYTHON) tools/mksdimg.py $@ $(TEST_DATA)
else
DISK = vera-c64.d64
$(DISK): $(TEST_EXE) $(TEST_DATA)
	rm -f $@
	$(C1541) -format "libvera,lv" d64 $@ -write $(TEST_EXE) testlib \
	    $(foreach f,$(TEST_DATA),-write $(f) $(notdir $(f))) > /dev/null
	$(C1541) -attach $@ -list
endif

disk: $(DISK)

run-atari:
	$(MAKE) PLATFORM=atari one
	$(ATARI800) -xl -verax16 -verax16-rom $(VERA_ROM) -windowed -win-width 384 -win-height 240 vera-atari.atr

run-c64:
	$(MAKE) PLATFORM=c64 one
	$(VICE) -vera -verabase $(or $(VERA_BASE),0xDF00) +VICIIdsize -windowwidth 400 -windowheight 300 \
	    +drive8truedrive -trapdevice8 -autostart vera-c64.d64

run-x16:
	$(MAKE) PLATFORM=cx16 one
	$(X16EMU) -mhz $(X16_MHZ) -scale 2 -fsroot build/cx16/disk -prg build/cx16/disk/TESTLIB.PRG -run

run-apple2:
	$(MAKE) PLATFORM=apple2 one
	A2_MODEL=$(A2_MODEL) A2_VERA_SLOT=$(A2_SLOT) A2_SDCARD=$(abspath vera-apple2-sd.img) \
	    $(A2EMU) $(abspath vera-apple2.dsk)

# --- FAT32 SD test -----------------------------------------------------------

SD_TEST_EXE = $(B)/test_sdfs.$(EXE)
SD_IMG      = tests/test_fat32.img

test-sdfs: $(SD_TEST_EXE)

tests/test_fat32.img:
	@mkdir -p tests
	python3 tests/gen_test_image.py $@

$(B)/test_sdfs.o: tests/test_sdfs.c $(HEADERS)
	$(CC65) $(CFLAGS) -o $(B)/test_sdfs.s $<
	$(CA65) $(LIBVERA_ASFLAGS) -o $@ $(B)/test_sdfs.s

$(B)/test_sdfs_minimal.o: tests/test_sdfs_minimal.c $(HEADERS)
	$(CC65) $(CFLAGS) -o $(B)/test_sdfs_minimal.s $<
	$(CA65) $(LIBVERA_ASFLAGS) -o $@ $(B)/test_sdfs_minimal.s

# the FAT32 code: on the Atari in a RAMbo bank, cfg/atari-rambo.cfg
$(SD_TEST_EXE) $(B)/test_sdfs_minimal.$(EXE) $(B)/test_rastan_sd.$(EXE): LIBVERA_RAMBO = 1

$(SD_TEST_EXE): $(B)/test_sdfs.o $(FAT32_OBJS) $(LIBVERA_LIB) $(LIBVERA_CFG)
	$(CL65) -t $(PLATFORM) $(LIBVERA_LDFLAGS) -m $(B)/test_sdfs.map -o $@ \
	    $(B)/test_sdfs.o $(FAT32_OBJS) $(LIBVERA_LIB)

$(B)/test_sdfs_minimal.$(EXE): $(B)/test_sdfs_minimal.o $(FAT32_OBJS) $(LIBVERA_LIB) $(LIBVERA_CFG)
	$(CL65) -t $(PLATFORM) $(LIBVERA_LDFLAGS) -m $(B)/test_sdfs_minimal.map -o $@ \
	    $(B)/test_sdfs_minimal.o $(FAT32_OBJS) $(LIBVERA_LIB)

$(B)/test_rastan_sd.$(EXE): $(B)/test_rastan_sd.o $(FAT32_OBJS) $(LIBVERA_LIB) $(LIBVERA_CFG)
	$(CL65) -t $(PLATFORM) $(LIBVERA_LDFLAGS) -m $(B)/test_rastan_sd.map -o $@ \
	    $(B)/test_rastan_sd.o $(FAT32_OBJS) $(LIBVERA_LIB)

$(B)/test_rastan_sd.o: tests/test_rastan_sd.c $(HEADERS)
	$(CC65) $(CFLAGS) -o $(B)/test_rastan_sd.s $<
	$(CA65) $(LIBVERA_ASFLAGS) -o $@ $(B)/test_rastan_sd.s

run-test-sdfs: PLATFORM ?= atari
run-test-sdfs: test-sdfs $(SD_IMG)
	$(ATARI800) -xl -verax16 -verax16-rom $(VERA_ROM) -verax16-sdcard $(SD_IMG) \
	    -windowed -win-width 384 -win-height 240 build/atari/test_sdfs.xex

run-test-sdfs-minimal: PLATFORM ?= atari
run-test-sdfs-minimal: $(B)/test_sdfs_minimal.$(EXE) $(SD_IMG)
	$(ATARI800) -xl -verax16 -verax16-rom $(VERA_ROM) -verax16-sdcard $(SD_IMG) \
	    -windowed -win-width 384 -win-height 240 build/atari/test_sdfs_minimal.xex

run-test-rastan-sd: PLATFORM ?= atari
run-test-rastan-sd: $(B)/test_rastan_sd.$(EXE) $(SD_IMG)
	$(ATARI800) -xl -verax16 -verax16-rom $(VERA_ROM) -verax16-sdcard $(SD_IMG) \
	    -windowed -win-width 384 -win-height 240 build/atari/test_rastan_sd.xex

clean:
	rm -rf build vera-atari.atr vera-c64.d64 vera-apple2.dsk vera-apple2-sd.img tests/test_fat32.img

# --- CPU cycles of the sound callbacks on sim65 ------------------------------

SIM_FLAGS = -t sim6502 -Osir -I include --asm-include-dir include

prof-pcm:
	@mkdir -p build/sim
	$(CL65) $(SIM_FLAGS) -o build/sim/prof_pcm tests/prof_pcm.c src/common/pcm.s tests/sim_pcm_stub.s
	sim65 build/sim/prof_pcm

prof-sfx:
	@mkdir -p build/sim
	$(PYTHON) tools/psgsfx.py tests/sfx_test.py build/sim/sfx_test.s
	$(CL65) $(SIM_FLAGS) -o build/sim/prof_sfx tests/prof_sfx.c src/common/sfx.s tests/sim_sfx_stub.s build/sim/sfx_test.s
	sim65 build/sim/prof_sfx
