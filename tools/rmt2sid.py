#!/usr/bin/env python3
"""
rmt2sid.py - an RMT song as a SID register stream for the C64 (.sds), made
at build time so that the C64 only writes registers (src/c64/rmtsds.s)
instead of running the RMT routine and the POKEY -> SID translation every
frame.

    rmt2sid.py song.rmt out.sds [--ntsc] [--frames N]

The song is played on sim65 by the RMT routine (src/rmt/rmtplayr.s, or
lzsplayr.s for a .sap/.xex) and translated by src/c64/rmtsid.s, the code
the C64 runs today (-D RMTSID_LASTLINE: PAL or NTSC without a VIC-II), so
the stream sounds as rmt_init_host() does.  The 25 SID registers are
recorded every song frame, with the voices whose envelope was restarted
(gate off then on in the same frame, -D RMTSID_TRACE); the frames are cut
in an intro and a loop (the shortest period after which they repeat), and
every register that changes is one stream of events per section: a value
and how many frames it lasts, LZSS coded (the patterns of a song repeat).
Needs cl65 and sim65 (cc65), RMT4 songs only (one SID).

The .sds file (little endian):

    0   "SDS", 2                  magic, version
    4   flags                     bit 0: NTSC (SID frequencies for 1022727 Hz)
    5   n                         number of streams (registers that change)
    6   size (2)                  bytes of the whole file
    8   rate                      song frames a second (50: PAL Atari song)
    9   0
    10  regs[n]                   SID register of each stream, in reverse write
                                  order (the player goes from the last; the
                                  control register is the last written of
                                  its voice)
    ..  init[25]                  every register at the start
    ..  frames (2) x 2            intro frames, loop frames (intro may be 0)
    ..  offsets (2) x n x 2       start of each stream, intro then loop,
                                  from the start of the file
    ..  streams

A stream is a list of events, a value and its frames (1..255):
    t = $00-$7F    t + 1 literal events follow: value, frames
    t = $80-$FF    the (t & $7F) + 2 events from d events before (next byte
                   d, 1..127: the decoder keeps the last 128 events)
Each section is encoded on its own (the loop never refers to the intro).
The player works only when a register changes: a frame without events
costs a counter decrement per stream.
In a control register stream ($04, $0B, $12) bit 3 (TEST, never set by
rmtsid.s) means "restart the envelope": the player writes the byte with the
gate off first, then the byte without bit 3.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools'
SRC = ROOT / 'src'
CTRL = (0x04, 0x0B, 0x12)
REC = 26                        # bytes recorded a frame: 25 registers + restarts

GLUE = r"""
        .export pokey_shadow, rmt_ioactive, out_update, out_silence
        .export rmt_init_core, _rmt_stop, _do_update, _rmt_play_frame
        .import RASTERMUSICTRACKER
        .segment "BSS"
pokey_shadow:   .res 16
        .segment "DATA"
rmt_ioactive:   .byte 0
        .segment "CODE"
rmt_init_core:                          ; A/X = module
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
_rmt_stop:
no_out: rts
out_update:
        jmp no_out
out_silence:
        jmp no_out
_do_update:
        jmp out_update
"""

CONV = r"""
#include <stdlib.h>
#include <unistd.h>
extern const unsigned char rmt_song[];
extern unsigned char sid_restart;
unsigned char __fastcall__ rmt_init_host(const void *m);
void do_update(void);
void rmt_play_frame(void);
static unsigned char buf[26];
int main(int argc, char **argv)
{
    unsigned n = (unsigned)atol(argv[1]), i, sp;
    unsigned char k;
    const unsigned char *sid = (const unsigned char *)0xD400;
    sp = rmt_init_host(rmt_song);
    for (i = 0; i < n; ++i) {
        for (k = 0; k < sp; ++k)
            rmt_play_frame();
        sid_restart = 0;
        do_update();
        for (k = 0; k < 25; ++k)
            buf[k] = sid[k];
        buf[25] = sid_restart;
        write(1, buf, 26);
    }
    return 0;
}
"""


def die(msg):
    sys.stderr.write('rmt2sid: %s\n' % msg)
    sys.exit(1)


def sim_cfg():
    """cc65's sim6502.cfg plus the RMT segments"""
    out = subprocess.run(['cl65', '--print-target-path'], capture_output=True, text=True)
    cands = [Path(out.stdout.strip()).parent / 'cfg' / 'sim6502.cfg',
             Path('/usr/share/cc65/cfg/sim6502.cfg')]
    for c in cands:
        if c.exists():
            t = c.read_text()
            break
    else:
        die('sim6502.cfg not found')
    t = t.replace('    ZEROPAGE: load = ZP,     type = zp;',
                  '    ZEROPAGE: load = ZP,     type = zp;\n    RMTZP:    load = ZP,     type = zp;')
    t = t.replace('    RODATA:   load = MAIN,   type = ro;',
                  '    RODATA:   load = MAIN,   type = ro;\n'
                  '    RMTTAB:   load = MAIN,   type = ro,  align = $100;')
    return t


def render(song, ntsc, frames, tmp):
    """the SID registers of every song frame: a list of 26 byte records"""
    sap = song.suffix.lower() in ('.sap', '.xex')
    if sap:
        tracks = subprocess.run([sys.executable, '-I', str(TOOLS / 'sap2ca65.py'), str(song), '--tracks'],
                                capture_output=True, text=True, check=True).stdout.strip()
        if tracks != '4':
            die('%s: stereo SAP/XEX: one SID plays 4 POKEY channels only' % song)
        subprocess.run([sys.executable, '-I', str(TOOLS / 'sap2ca65.py'), str(song), str(tmp / 'song.s')],
                       check=True, stdout=subprocess.DEVNULL)
        player = SRC / 'rmt' / 'lzsplayr.s'
    else:
        head = song.read_bytes()[:10]
        if head[6:10] != b'RMT4':
            die('%s: not an RMT4 module (one SID plays 4 POKEY channels)' % song)
        subprocess.run([sys.executable, '-I', str(TOOLS / 'rmt2ca65.py'), str(song), str(tmp / 'song.s')],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        player = SRC / 'rmt' / 'rmtplayr.s'
    subprocess.run([sys.executable, '-I', str(TOOLS / 'mksidtab.py'), str(tmp / 'sidtab.s')],
                   check=True, stdout=subprocess.DEVNULL)
    (tmp / 'glue.s').write_text(GLUE)
    (tmp / 'conv.c').write_text(CONV)
    (tmp / 'sim.cfg').write_text(sim_cfg())
    cmd = ['cl65', '-t', 'sim6502', '-C', str(tmp / 'sim.cfg'), '-Osir',
           '--asm-define', 'RMT_SHADOW', '--asm-define', 'RMTSID_TRACE',
           '--asm-define', 'RMTSID_LASTLINE=%d' % (0x06 if ntsc else 0x37),
           '--asm-include-dir', str(SRC / 'rmt'), '-o', str(tmp / 'conv'),
           str(tmp / 'conv.c'), str(tmp / 'glue.s'), str(player),
           str(SRC / 'c64' / 'rmtsid.s'), str(tmp / 'sidtab.s'), str(tmp / 'song.s')]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        die('cl65 failed:\n' + r.stdout + r.stderr)
    out = subprocess.run(['sim65', str(tmp / 'conv'), str(frames)], capture_output=True, check=True).stdout
    if len(out) != frames * REC:
        die('sim65 gave %d bytes, %d expected' % (len(out), frames * REC))
    return [out[i:i + REC] for i in range(0, len(out), REC)]


def find_loop(recs):
    """(start, period): the shortest period after which the frames repeat,
    seen repeating for at least a period and a quarter of the frames
    rendered (a tail of silence is not a loop); (len, 0) when there is none"""
    n = len(recs)
    check = n // 4
    ids = {}
    h = [ids.setdefault(r, len(ids)) for r in recs]
    try:
        import numpy as np
        a = np.array(h, dtype=np.int32)
        for p in range(1, n // 2 + 1):
            diff = np.nonzero(a[:n - p] != a[p:])[0]
            s = int(diff[-1]) + 1 if len(diff) else 0
            if n - s - p >= max(p, check):
                return s, p
    except ImportError:
        for p in range(1, n // 2 + 1):
            s = 0
            for i in range(n - p - 1, -1, -1):
                if h[i] != h[i + p]:
                    s = i + 1
                    break
            if n - s - p >= max(p, check):
                return s, p
    return n, 0


def events(seq):
    """(value, frames 1..255) runs of a register"""
    ev = []
    i = 0
    while i < len(seq):
        j = i
        while j < len(seq) and seq[j] == seq[i] and j - i < 255:
            j += 1
        ev.append((seq[i], j - i))
        i = j
    return ev


def lzss(ev):
    """the events of one stream: literal blocks and matches in the last 127"""
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
        for d in range(1, min(127, i) + 1):
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


def unlzss(enc, frames):
    """decode one stream to its frames, as src/c64/rmtsds.s does (check)"""
    ev = []
    i = 0
    while sum(f for _, f in ev) < frames:
        t = enc[i]
        i += 1
        if t < 0x80:
            for _ in range(t + 1):
                ev.append((enc[i], enc[i + 1]))
                i += 2
        else:
            d = enc[i]
            i += 1
            for _ in range((t & 0x7F) + 2):
                ev.append(ev[-d])
    return bytes(v for v, f in ev for _ in range(f))[:frames]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('song')
    ap.add_argument('out')
    ap.add_argument('--ntsc', action='store_true', help='SID frequencies for an NTSC C64')
    ap.add_argument('--frames', type=int, default=30000,
                    help='song frames rendered to find the loop (default 30000, 10 minutes)')
    ap.add_argument('--rate', type=int, default=50, help='song frames a second (default 50)')
    ap.add_argument('--dump', help='write the frames rendered (26 bytes each: the SID registers, '
                    'the restarted voices) to this file (tests)')
    a = ap.parse_args()
    for tool in ('cl65', 'sim65'):
        if not shutil.which(tool):
            die('%s not found (cc65)' % tool)

    with tempfile.TemporaryDirectory() as t:
        recs = render(Path(a.song), a.ntsc, a.frames, Path(t))

    if a.dump:
        Path(a.dump).write_bytes(b''.join(recs))
    start, period = find_loop(recs)
    if period == 0:
        sys.stderr.write('rmt2sid: no loop in %d frames: the song plays once, then silence\n' % a.frames)
        recs = recs[:start] + [bytes(REC)]          # the loop: one silent frame
        start, period = len(recs) - 1, 1

    def value(rec, reg):
        v = rec[reg]
        if reg in CTRL and rec[25] & (1 << CTRL.index(reg)):
            v |= 0x08                               # restart
        return v

    used = [r for r in range(25) if len({value(x, r) for x in recs[:start + period]}) > 1]
    order = []
    for v in range(3):
        order += [r for r in range(7 * v, 7 * v + 7) if r in used and r != CTRL[v]]
        if CTRL[v] in used:
            order.append(CTRL[v])
    order += [r for r in range(21, 25) if r in used]
    order.reverse()                                 # the player goes from the last
    init = bytes(recs[0][r] for r in range(25))

    sections = [(0, start), (start, start + period)]
    enc = []
    for lo, hi in sections:
        for r in order:
            raw = bytes(value(x, r) for x in recs[lo:hi])
            e = lzss(events(raw)) if raw else b''
            if raw and unlzss(e, len(raw)) != raw:
                die('LZSS check failed (register $%02X)' % r)
            enc.append(e)

    n = len(order)
    head = bytearray(b'SDS\x02')
    head.append(1 if a.ntsc else 0)
    head.append(n)
    head += b'\0\0'                                 # size, below
    head.append(a.rate)
    head.append(0)
    head += bytes(order)
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
    print('rmt2sid: %s -> %s (%s): %d bytes, %d streams, intro %d frames, loop %d frames (%.1f s)'
          % (a.song, a.out, 'NTSC' if a.ntsc else 'PAL', len(blob), n, start, period, period / a.rate))


if __name__ == '__main__':
    main()
