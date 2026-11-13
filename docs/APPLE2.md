# Apple II: the VERA cards and the Slinky RAM

libvera runs on the Apple IIe (6502) and the enhanced IIe (65C02) with
`PLATFORM=apple2`. Two VERA cards are supported:

| Card | Slot / registers | What else it has | Emulator |
|---|---|---|---|
| A2VERA | any slot `n`, VERA at `$Cn00-$Cn1F` (default slot 4, `$C400`) | — | a2emu-vera, default (`A2_VERA_SLOT`) |
| VERA Module RBL-A2 (RetroBitLab) | any slot `n`; after a reset `$Cn00-$CnFF` show its ProDOS slot ROM, `$C0nF` bit 0 = 1 puts the VERA at `$Cn00-$Cn1F` | 256 KB Slinky-compatible RAM, the ProDOS volume `/SLINKY` | `A2_VERA_CARD=rbl`, a2run `--vera-card rbl` |

Build for the card's slot with `VERA_BASE=0xCn00` (default `0xC400`) and
rebuild the library with it. Slot 6 is usually the Disk II; `$C3xx`
belongs to the IIe 80-column firmware.

## RBL-A2: the VERA

The start-up code (`src/apple2/plat_apple2.s`, constructor `plat_startup`)
reads `$CnF0-$CnF4` of `VERA_BASE`'s slot; when it finds `"VERAS"` (the
RBL-A2 identification: VERA, card type `S`) it writes 1 into `$C0nF`. Any
other card is only read. After an Apple reset the VERA is hidden again: the
program must start again. Hardware details: `Vera-Module-RBL-A2/A2-SLINKY.md`.

## Slinky RAM (`slinky.h`, `src/apple2/slinky.s`)

A RAM card compatible with the Apple II Memory Expansion Card ("Slinky"):
the RBL-A2's 256 KB, or a separate card. It is not a memory window: the
address is a 24-bit counter in `$C0n0-$C0n2`, `$C0n3` reads or writes the
byte there and moves on by one. Use it as a store to copy blocks to and
from the main RAM (~17 cycles a byte).

```c
#include "slinky.h"

unsigned char slot = slinky_find();      /* the RBL-A2's slot, 0 = none (reads only) */
unsigned char size = slinky_open(slot);  /* 64 KB units: 4 on the RBL-A2, 0 = no card */
slinky_seek(0x10000ul);
slinky_write(buf, 1024);                 /* the address goes up by 1024 */
slinky_seek(0x10000ul);
slinky_read(buf, 1024);
```

- `slinky_open(slot)` checks that the address registers keep what is written,
  then measures the size by mirrors (the memory repeats after its size; 16 =
  1 MB or more) and puts back the bytes it touched. It writes `$C0n0-$C0n3`:
  call it only for a slot that holds such a card (`slinky_find`, or the
  user's setting), never blindly (the Disk II's `$C0E0-$C0E3` move the head).
- Every access is `LDA`/`STA (zp,X)`: an indexed store on an NMOS 6502 makes a
  dummy read of `$C0n3` first, which would advance the address.
- The RBL-A2 formats its RAM as `/SLINKY` at power-on and never clears it:
  what a program writes there replaces that volume's blocks.
- One address counter: do not use it from an interrupt while the main
  program does.

Test (`tests/test_slinky.c`: size, the bytes put back, a block across a
64 KB boundary, the wrap at the size):

```sh
make PLATFORM=apple2 test-slinky
a2run --model iie --vera-card rbl --frames 200 --text build/apple2/slinky.dsk
a2run --model iie --xmem 512 --xmem-slot 5 --frames 200 --text build/apple2/slinky.dsk
```

Checked 2026-11-13 with a2run: RBL-A2 on the IIe and the enhanced IIe (slot
4, 256 KB, `SLINKY PASS`; the `/SLINKY` volume changed only in the test's
block), a2emu's RAM card at 512 KB and 1 MB (`SLINKY PASS`), no card in the
slot (`size 0`). Not tried on real hardware.
