# The microSD of the VERA

The FAT32 code of the X16 KERNAL (x16-rom `fat32/`, Frank van den Hoef and
Michael Steil, 2-clause BSD) ported to the NMOS 6502 (`src/fat32/`), with a
C interface (`include/sdfs.h`) and the asset functions on top of it
(`asset.h`, `src/common/asset_sd.c`). Atari, C64 and Apple IIe; the X16 reads
its card through the KERNAL instead.

## Two libraries

| | `LIBVERA_SD_LIB` (`libvera_sd.lib`) | `LIBVERA_SDRO_LIB` (`libvera_sdro.lib`) |
|---|---|---|
| | the default | for the programs short of memory |
| reading | yes | yes |
| writing | yes | no (`FAT32_READONLY`: the FAT32 code ~3.3 KB smaller) |
| where the code is | main RAM; Atari: a RAMbo bank (`atari-rambo.cfg`) | the same |

Link one of them before `libvera.lib`. A program that calls a write
function and links the read only one does not link (unresolved symbol).
The C functions of the writing are modules of their own
(`src/fat32/sdfsw.s`, Atari `src/atari/sdbankw.s`): a program that only
reads does not pay for them even with `libvera_sd.lib`.

RastanRIP never writes: it links `libvera_sdro.lib` on the C64, the Apple and
the Atari.

## Reading (`sdfs.h`)

`sd_mount`, `sd_open`, `sd_read`, `sd_read_vram` (straight to the VERA's
data port), `sd_close`; one file as one stream (`sd_stream_*`, a contiguous
file: ~3x faster); `sd_opendir`, `sd_readdir`, `sd_chdir`; `sd_errno`.
One file or directory open at a time.

## Writing (`sdfs.h`, `libvera_sd.lib`)

- `sd_create(path, overwrite)`: a new file, open to write; an existing one
  replaced if `overwrite`, else `SD_ERR_EXISTS`.
- `sd_write(src, n)`, `sd_write_vram(n)` (from the VERA's data port).
- `sd_close()`: the file is complete on the card only now (its last sector,
  its directory entry, the FAT): 1 = ok.
- `sd_delete`, `sd_rename` (also a move), `sd_mkdir`, `sd_rmdir` (empty).

Short names (8.3) are made as Windows makes them: the name itself in capitals
when it is an 8.3 one already (`wtest2.bin` -> `WTEST2.BIN`); otherwise 2 of
its characters, 4 hex digits of the place of the entry and `~1`, then its
extension cut to 3 (`LongerName.text` -> `LO82C0~1.TEX`). The long name is
always written too.

## The date of the files

Every file or directory made (`sd_create`, `sd_mkdir`) gets, in this order:

1. the time of an **RTC adapter**, when there is one (`plat_rtc`, `plat.h`);
2. else the time set with `sd_set_time(&t)` (`struct sd_time`: year, month,
   day, hour, minute, second);
3. else **1980-01-01 00:00:00**, the first date FAT has.

`sd_get_time(&t)` gives the time the next file gets (1 = from the adapter).
The code is `src/common/sdtime.s`, in the main RAM.

### The RTC adapters (`plat_rtc`, `src/<host>/rtc.s`)

| Host | Adapter | How it is found | Emulator |
|---|---|---|---|
| Atari | ICD R-Time 8 cartridge, `$D5B8` (register number written, two reads: the BCD digits) | the digits read are BCD and in range (the floating bus is not) | atari800 `-rtime` (on by default) |
| C64 | DS1307 on the user port: SDA PB0, SCL PB1 (CIA 2), I2C address `$D0` | the chip acknowledges its address; the clock is not halted | VICE `-userportdevice 17` |
| Apple IIe | No-Slot Clock (DS1216E) under the CD ROM, through the internal ROM page `$C300` (64-bit recognition pattern on A0, the registers on D0) | the values are BCD and in range, the oscillator runs | a2emu-vera (`A2_NSC`): a clock that runs with the emulated machine, starts from the date saved by the last run (`A2_NSC_FILE`) and never goes back |
| X16 | the clock on the board (KERNAL `clock_get_date_time`) | always there | x16emu `-rtc` (from the host's clock; else it starts at 2000-01-01) |

No probe writes where another device could be hurt: the C64's DS12C887
cartridge was left out because it sits in `$DExx` / `$DFxx`, with the VERA
and the GeoRAM.

## Tests

`make PLATFORM=<host> test-sdfs` (reading) and `test-sdwrite`
(`tests/test_sdwrite.c`): create, write in two pieces, close, read back, no
overwrite, delete, rename, mkdir, two names that are not 8.3, the time
(`sd_set_time` 2001-02-03 04:05:06, the adapter's if there is one). Run it
with a FAT32 image as the card (`tests/gen_test_image.py`), then look at the
image on the PC (the partition starts at 1 MB):

```sh
mdir -i card.img@@1048576 ::
```
