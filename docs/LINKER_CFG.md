# Linker configurations

The `cfg/` of libvera holds one linker configuration per host:
`c64.cfg`, `atari.cfg`, `atari-rambo.cfg` (the FAT32 code of the SD in a
RAMbo bank), `cx16.cfg`, `apple2.cfg` and `apple2-hgr.cfg` (the HGR page 1
kept free). `mk/libvera.mk` picks one from `PLATFORM`, `LIBVERA_RAMBO` and
`LIBVERA_HGR` (`LIBVERA_CFG`) and links with it (`LIBVERA_LDFLAGS`).

**They stay generic.** They hold the cc65 layout and only the segments
libvera itself uses: the RMT player's (`RMTZP`, `RMTTAB`, `PSGTAB`), `XBSS`,
the RAMbo window and bank of the Atari's SD (`GAMECODE`, `GAMERODATA`,
`LOWRODATA`, `WIN`, `LOW`, `BANK*`), the card selection of the Atari and the
C64 (`__VERA_SELECT__`). The areas of one game do not go into them.

## A game's own configurations: `LIBVERA_CFG_DIR`

A game that needs more (overlays, buffers in banked RAM, a smaller C stack,
load chunks of its own...) keeps its own copies, **with the same names**, in
its tree and points libvera at them before including `libvera.mk`:

```make
LIBVERA_CFG_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/cfg
include $(VERA_COMMON)/mk/libvera.mk
```

`LIBVERA_CFG_DIR` defaults to `$(VERA_COMMON)/cfg`. The game then links with
`$(LIBVERA_LDFLAGS)` as before; its programs no longer depend on changes to
libvera's `cfg/`, and libvera's cfgs never change for one game.

Today:

| Project | Its `cfg/` |
|---|---|
| RastanRIP | `proto/cfg/`: libvera's with Rastan's areas (COLL / BOOTOVL, GeoRAM pages, KHI / KHO / KHM overlays, AUX, LC1 / LCO, GAMEBSS, HICODE / HIRO3, BANK2) |
| PacManRIP | `cfg/`: a 1 KB stack on the C64 and the Apple, the Atari's loader and VRAM chunks, the RAM of the host screen |

## When a cfg changes

The programs do not depend on the cfg in make (they only name it): after
changing one, delete the program (`.prg`, `.xex`, `.bin`) so that it is
linked again.
