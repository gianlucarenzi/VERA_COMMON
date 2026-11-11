#!/usr/bin/env python3
"""
rmt2psg.py - an RMT4 / RMT8 song as a VERA PSG register stream (.pds), made at
build time so that a slow host (C64) only writes PSG registers
(src/rmt/rmtpds.s) instead of running the RMT routine and the POKEY -> PSG
translation (psgrmt.s, ~1500 cycles a frame) every frame.  It sounds as
rmt_init() does: the song is played on sim65 by the RMT routine
(src/rmt/rmtplayr.s) and translated by src/rmt/psgrmt.s itself
(-D PSG_CAPTURE: the bytes it would send to the PSG are recorded).

    rmt2psg.py song.rmt out.pds [--frames N] [--ntsc-song]

The PSG registers of voices 0-3 (RMT4) or 0-7 (RMT8) are recorded every
song frame (as rmt_init plays them: pan L+R) and cut in
an intro and a loop (the shortest period after which they repeat); every
register that changes is a stream of events per section (a value and the
frames it lasts) coded as in rmt2sid.py, with a smaller ring: matches reach
back RING events at most (the player keeps the last RING events of each
stream: RING * 2 bytes a stream).

The .pds file (little endian):

    0   "PDS", 1                  magic, version
    4   ring                      events kept per stream (power of 2, <= 128)
    5   n                         number of streams (registers that change)
    6   size (2)                  bytes of the whole file
    8   rate                      song frames a second (50: PAL Atari song)
    9   0
    10  regs[n]                   PSG register (0..15: voice * 4 + byte) of
                                  each stream
    ..  init[16]                  every register at the start
    ..  frames (2) x 2            intro frames, loop frames (intro may be 0)
    ..  offsets (2) x n x 2       start of each stream, intro then loop,
                                  from the start of the file
    ..  streams

--raw writes a .pdr instead: one sequence of the frames where registers
change, no LZSS, read straight through (C64: the GeoRAM page at $DE00)
into a small queue; the player only counts frames and writes what changes:

    0   "PDR", 3                  magic, version
    4   rate                      song frames a second
    5   nreg                      PSG registers: 16 (RMT4, voices 0-3) or
                                  32 (RMT8, voices 0-7)
    6   size (2)                  bytes of the whole file (32 KB at most)
    8   init[nreg]                every register at the start
    ..  loop (2)                  offset of the first record of the loop
    ..  records                   intro, then loop, then $FF (back to loop)

A record: k (0..nreg), k x (register, value), d (1..255): the frames
until the next record.  The first loop record sets every register that
changes in the song (so the loop starts right after the intro and after
itself); a gap over 255 frames gets empty records (k = 0).

A stream is a list of events, a value and its frames (1..255):
    t = $00-$7F    t + 1 literal events follow: value, frames
    t = $80-$FF    the (t & $7F) + 2 events from d events before (next byte
                   d, 1..ring - 1)
Each section is encoded on its own (the loop never refers to the intro).
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rmt2sid                                          # noqa: E402  (loop search, events)

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools'
SRC = ROOT / 'src'
REC = 16                        # voices 0-3, 4 bytes each

GLUE = r"""
        .export pokey_shadow, rmt_ioactive, rmt_palnts, psg_put, psg_putx, _cap, _capn
        .export _rmt_init_core, _rmt_play_frame
        .export _psg_update
        .import RASTERMUSICTRACKER, psg_update
        .segment "BSS"
pokey_shadow:   .res 16
_cap:           .res 64
        .segment "DATA"
rmt_ioactive:   .byte 0
rmt_palnts:     .byte PAL_SONG
_capn:          .byte 0
        .segment "CODE"
_rmt_init_core:                         ; A/X = module
        pha
        txa
        tay
        pla
        tax
        lda #0
        jsr RASTERMUSICTRACKER+0
        ldx #0
        rts
_rmt_play_frame:
        jmp RASTERMUSICTRACKER+3
_psg_update:
        jmp psg_update
; psgrmt.s -D PSG_CAPTURE: a byte for the PSG (A, X, Y and flags kept)
psg_put:
        php
        pha
        stx save_x
        ldx _capn
        sta _cap,x
        inc _capn
        ldx save_x
        pla
        plp
        rts
psg_putx:
        php
        pha
        txa
        ldx _capn
        sta _cap,x
        inc _capn
        tax
        pla
        plp
        rts
        .segment "BSS"
save_x: .res 1
"""

CONV = r"""
#include <stdlib.h>
#include <unistd.h>
extern const unsigned char rmt_song[];
extern unsigned char cap[64], capn;
extern unsigned char psg_enable;
unsigned char __fastcall__ rmt_init_core(const void *m);
void rmt_play_frame(void);
void psg_init(void);
void psg_update(void);
int main(int argc, char **argv)
{
    unsigned n = (unsigned)atol(argv[1]), i;
    unsigned char k, sp;
    psg_init();
    sp = rmt_init_core(rmt_song);
    psg_enable = 1;
    for (i = 0; i < n; ++i) {
        for (k = 0; k < sp; ++k)
            rmt_play_frame();
        capn = 0;
        psg_update();
        if (capn != REC) return 1;
        write(1, cap, REC);
    }
    return 0;
}
"""


def die(msg):
    sys.stderr.write('rmt2psg: %s\n' % msg)
    sys.exit(1)


def render(song, ntsc_song, frames, tmp):
    """the PSG registers of voices 0-3 every song frame: 16 byte records"""
    head = song.read_bytes()[:10]
    if head[6:10] not in (b'RMT4', b'RMT8'):
        die('%s: not an RMT4 / RMT8 module' % song)
    nv = 8 if head[6:10] == b'RMT8' else 4
    subprocess.run([sys.executable, '-I', str(TOOLS / 'rmt2ca65.py'), str(song), str(tmp / 'song.s')],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([sys.executable, '-I', str(TOOLS / 'mkpsgtab.py'), str(tmp / 'psgtab.s'),
                    '--std', 'ntsc' if ntsc_song else 'pal', '--rmt', str(song)],
                   check=True, stdout=subprocess.DEVNULL)
    (tmp / 'glue.s').write_text(GLUE)
    (tmp / 'conv.c').write_text(CONV.replace('REC', str(4 * nv)))
    t = rmt2sid.sim_cfg()
    t = t.replace('    RMTTAB:   load = MAIN,   type = ro,  align = $100;',
                  '    RMTTAB:   load = MAIN,   type = ro,  align = $100;\n'
                  '    PSGTAB:   load = MAIN,   type = ro,  align = $100;')
    (tmp / 'sim.cfg').write_text(t)
    cmd = ['cl65', '-t', 'sim6502', '-C', str(tmp / 'sim.cfg'), '-Osir',
           '--asm-define', 'RMT_SHADOW', '--asm-define', 'RMT_VERA', '--asm-define', 'RMT_TUNED', '--asm-define', 'RMT_TRACKS=%d' % nv, '--asm-define', 'PSG_CAPTURE',
           '--asm-define', 'PAL_SONG=%d' % (0 if ntsc_song else 1),
           '--asm-include-dir', str(SRC / 'rmt'), '--asm-include-dir', str(ROOT / 'include'),
           '-o', str(tmp / 'conv'),
           str(tmp / 'conv.c'), str(tmp / 'glue.s'), str(SRC / 'rmt' / 'rmtplayr.s'),
           str(SRC / 'rmt' / 'psgrmt.s'), str(tmp / 'psgtab.s'), str(tmp / 'song.s')]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        die('cl65 failed:\n' + r.stdout + r.stderr)
    rec = 4 * nv
    p = subprocess.run(['sim65', str(tmp / 'conv'), str(frames)], capture_output=True)
    out = p.stdout
    if p.returncode or len(out) != frames * rec:
        die('sim65 gave %d bytes (exit %d), %d expected' % (len(out), p.returncode, frames * rec))
    return [out[i:i + rec] for i in range(0, len(out), rec)]


def lzss(ev, ring):
    """rmt2sid.lzss with matches at most ring - 1 events back"""
    out = bytearray()
    lit = []

    def flush():
        while lit:
            k = min(len(lit), 128)
            out.append(k - 1)
            for v, f in lit[:k]:
                out.extend((v, f))
            del lit[:k]

    i, n = 0, len(ev)
    while i < n:
        best, bd = 0, 0
        for d in range(1, min(ring - 1, i) + 1):
            l = 0
            while i + l < n and l < 129 and ev[i - d + l] == ev[i + l]:
                l += 1
            if l > best:
                best, bd = l, d
                if l == 129:
                    break
        if best >= 2:
            flush()
            out.append(0x80 | (best - 2))
            out.append(bd)
            i += best
        else:
            lit.append(ev[i])
            i += 1
    flush()
    return bytes(out)


def write_raw(a, recs, start, period, used, init):
    """the .pdr file (version 2): records of the frames that change"""
    out = bytearray()

    def section(frames, prev, full):
        """records for frames; prev = the registers before the first one"""
        recsec = []                             # (frame, changes)
        cur = list(prev)
        for i, f in enumerate(frames):
            ch = [(r, f[r]) for r in used if (full and i == 0) or f[r] != cur[r]]
            if ch or i == 0:
                recsec.append((i, ch))
            cur = list(f)
        for j, (i, ch) in enumerate(recsec):
            nxt = recsec[j + 1][0] if j + 1 < len(recsec) else len(frames)
            d = nxt - i
            out.append(len(ch))
            for r, v in ch:
                out.extend((r, v))
            while d > 255:
                out.append(255)
                out.append(0)                   # an empty record
                d -= 255
            out.append(d)

    nreg = len(init)
    head = bytearray(b'PDR\x03')
    head.append(a.rate)
    head.append(nreg)
    head += b'\0\0'
    head += init
    head += b'\0\0'
    if start:
        section(recs[:start], recs[0], False)
    loop = len(head) + len(out)
    section(recs[start:start + period], recs[start - 1] if start else recs[0], True)
    out.append(0xFF)
    blob = head + out
    if len(blob) > 0x8000:
        die('%d bytes: more than 32 KB (two GeoRAM blocks)' % len(blob))
    blob[6:8] = len(blob).to_bytes(2, 'little')
    blob[8 + nreg:10 + nreg] = loop.to_bytes(2, 'little')
    Path(a.out).write_bytes(blob)
    print('rmt2psg: %s -> %s: %d bytes (raw), %d registers change, intro %d frames, loop %d frames (%.1f s)'
          % (a.song, a.out, len(blob), len(used), start, period, period / a.rate))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('song')
    ap.add_argument('out')
    ap.add_argument('--frames', type=int, default=30000,
                    help='song frames rendered to find the loop (default 30000, 10 minutes)')
    ap.add_argument('--rate', type=int, default=50, help='song frames a second (default 50)')
    ap.add_argument('--ring', type=int, default=32, help='events kept per stream (2..128, power of 2; default 32)')
    ap.add_argument('--ntsc-song', action='store_true', help='the song was written on an NTSC Atari')
    ap.add_argument('--dump', help='write the frames rendered (16 bytes each) to this file (tests)')
    ap.add_argument('--raw', action='store_true', help='a .pdr: the events without LZSS (see above)')
    a = ap.parse_args()
    if a.ring not in (2, 4, 8, 16, 32, 64, 128):
        die('--ring: a power of 2, 2..128')
    for tool in ('cl65', 'sim65'):
        if not shutil.which(tool):
            die('%s not found (cc65)' % tool)

    with tempfile.TemporaryDirectory() as t:
        recs = render(Path(a.song), a.ntsc_song, a.frames, Path(t))
    global REC
    REC = len(recs[0])                          # 16 (RMT4) or 32 (RMT8)
    if a.dump:
        Path(a.dump).write_bytes(b''.join(recs))
    start, period = rmt2sid.find_loop(recs)
    if period == 0:
        sys.stderr.write('rmt2psg: no loop in %d frames: the song plays once, then silence\n' % a.frames)
        sil = bytearray(recs[-1])
        for v in range(REC // 4):
            sil[4 * v + 2] &= 0xC0                  # volume 0, the pan kept
        recs = recs[:start] + [bytes(sil)]
        start, period = len(recs) - 1, 1

    used = [r for r in range(REC) if len({x[r] for x in recs[:start + period]}) > 1]
    init = bytes(recs[0])
    if a.raw:
        write_raw(a, recs, start, period, used, init)
        return
    enc = []
    for lo, hi in ((0, start), (start, start + period)):
        for r in used:
            raw = bytes(x[r] for x in recs[lo:hi])
            e = lzss(rmt2sid.events(raw), a.ring) if raw else b''
            if raw and rmt2sid.unlzss(e, len(raw)) != raw:
                die('LZSS check failed (register %d)' % r)
            enc.append(e)

    n = len(used)
    head = bytearray(b'PDS\x01')
    head.append(a.ring)
    head.append(n)
    head += b'\0\0'
    head.append(a.rate)
    head.append(0)
    head += bytes(used)
    head += init
    head += start.to_bytes(2, 'little') + period.to_bytes(2, 'little')
    ofs_at = len(head)
    head += bytes(4 * n)
    data = bytearray()
    for k, e in enumerate(enc):
        o = len(head) + len(data) if e else 0
        head[ofs_at + 2 * k:ofs_at + 2 * k + 2] = o.to_bytes(2, 'little')
        data += e
    blob = head + data
    if len(blob) > 0xFFFF:
        die('%d bytes: too big' % len(blob))
    blob[6:8] = len(blob).to_bytes(2, 'little')
    Path(a.out).write_bytes(blob)
    print('rmt2psg: %s -> %s: %d bytes, %d streams, ring %d (%d B), intro %d frames, loop %d frames (%.1f s)'
          % (a.song, a.out, len(blob), n, a.ring, 2 * a.ring * n, start, period, period / a.rate))


if __name__ == '__main__':
    main()
