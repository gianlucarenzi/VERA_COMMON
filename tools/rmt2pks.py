#!/usr/bin/env python3
"""
rmt2pks.py - an RMT song as a POKEY register stream for an Atari boot
loader (.pks): the music goes on while the loader reads the disk with the
SIO, so only POKEY channels 1+2 (channels 3+4 and AUDCTL are the serial
clock, src/atari/sio.s), and the player (src/atari/pksplay.s) only writes
4 registers a frame instead of running the RMT routine.

    rmt2pks.py song.rmt out.pks [--frames N]

The song is played on sim65 by the RMT routine (src/rmt/rmtplayr.s, or
lzsplayr.s for a .sap/.xex) with rmt_ioactive = 1, as the game plays it
during a SIO transfer (rmtpokey.s), and AUDF1 AUDC1 AUDF2 AUDC2 are
recorded every song frame; then the same coding as tools/rmt2sid.py: an
intro and a loop, every register that changes one stream of (value,
frames) events per section, LZSS coded.  RMT4 songs only.

The .pks file (little endian):

    0   "PKS", 1                  magic, version
    4   n                         number of streams (registers that change)
    5   rate                      song frames a second (50: PAL Atari song)
    6   regs[n]                   POKEY register (0-3) of each stream, the
                                  player goes from the last
    ..  init[4]                   AUDF1 AUDC1 AUDF2 AUDC2 at the start
    ..  frames (2) x 2            intro frames, loop frames (intro may be 0)
    ..  offsets (2) x n x 2       start of each stream, intro then loop,
                                  from the start of the file (0 = empty)
    ..  streams                   as in rmt2sid.py
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rmt2sid                                   # noqa: E402  (the coding)

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools'
SRC = ROOT / 'src'
REGS = 4                        # AUDF1 AUDC1 AUDF2 AUDC2
REC = 5                         # + AUDCTL (checked only)

GLUE = rmt2sid.GLUE.replace('rmt_ioactive:   .byte 0', 'rmt_ioactive:   .byte 1') + r"""
        .export _pokey_shadow := pokey_shadow, _rmt_init_core := rmt_init_core
"""

CONV = r"""
#include <unistd.h>
#include <stdlib.h>
extern const unsigned char rmt_song[];
extern unsigned char pokey_shadow[];
unsigned char __fastcall__ rmt_init_core(const void *m);
void rmt_play_frame(void);
static unsigned char buf[5];
int main(int argc, char **argv)
{
    unsigned n = (unsigned)atol(argv[1]), i;
    unsigned char k, sp;
    sp = rmt_init_core(rmt_song);
    for (i = 0; i < n; ++i) {
        for (k = 0; k < sp; ++k)
            rmt_play_frame();
        for (k = 0; k < 4; ++k)
            buf[k] = pokey_shadow[k];
        buf[4] = pokey_shadow[8];
        write(1, buf, 5);
    }
    return 0;
}
"""


def die(msg):
    sys.stderr.write('rmt2pks: %s\n' % msg)
    sys.exit(1)


def render(song, frames, tmp):
    """AUDF1 AUDC1 AUDF2 AUDC2 AUDCTL of every song frame"""
    sap = song.suffix.lower() in ('.sap', '.xex')
    if sap:
        subprocess.run([sys.executable, '-I', str(TOOLS / 'sap2ca65.py'), str(song), str(tmp / 'song.s')],
                       check=True, stdout=subprocess.DEVNULL)
        player = SRC / 'rmt' / 'lzsplayr.s'
    else:
        if song.read_bytes()[6:10] != b'RMT4':
            die('%s: not an RMT4 module' % song)
        subprocess.run([sys.executable, '-I', str(TOOLS / 'rmt2ca65.py'), str(song), str(tmp / 'song.s')],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        player = SRC / 'rmt' / 'rmtplayr.s'
    (tmp / 'glue.s').write_text(GLUE)
    (tmp / 'conv.c').write_text(CONV)
    (tmp / 'sim.cfg').write_text(rmt2sid.sim_cfg())
    cmd = ['cl65', '-t', 'sim6502', '-C', str(tmp / 'sim.cfg'), '-Osir',
           '--asm-define', 'RMT_SHADOW', '--asm-include-dir', str(SRC / 'rmt'),
           '-o', str(tmp / 'conv'), str(tmp / 'conv.c'), str(tmp / 'glue.s'),
           str(player), str(tmp / 'song.s')]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        die('cl65 failed:\n' + r.stdout + r.stderr)
    out = subprocess.run(['sim65', str(tmp / 'conv'), str(frames)], capture_output=True, check=True).stdout
    if len(out) != frames * REC:
        die('sim65 gave %d bytes, %d expected' % (len(out), frames * REC))
    return [out[i:i + REC] for i in range(0, len(out), REC)]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('song')
    ap.add_argument('out')
    ap.add_argument('--frames', type=int, default=30000,
                    help='song frames rendered to find the loop (default 30000, 10 minutes)')
    ap.add_argument('--rate', type=int, default=50, help='song frames a second (default 50)')
    ap.add_argument('--dump', help='write the frames rendered (AUDF1 AUDC1 AUDF2 AUDC2 each) '
                    'to this file (tests)')
    a = ap.parse_args()
    for tool in ('cl65', 'sim65'):
        if not shutil.which(tool):
            die('%s not found (cc65)' % tool)

    with tempfile.TemporaryDirectory() as t:
        full = render(Path(a.song), a.frames, Path(t))

    # AUDCTL is the SIO's ($28) while the loader runs: bits that change
    # channels 1+2 (15 kHz base, 1.79 MHz, 1+2 joined, filters, 9 bit poly)
    # are lost
    ctl = 0
    for x in full:
        ctl |= x[4]
    if ctl & 0xD7:
        sys.stderr.write('rmt2pks: warning: the song sets AUDCTL $%02X, channels 1+2 '
                         'sound different with the SIO one ($28)\n' % ctl)
    recs = [x[:REGS] for x in full]
    if a.dump:
        Path(a.dump).write_bytes(b''.join(recs))
    start, period = rmt2sid.find_loop(recs)
    if period == 0:
        sys.stderr.write('rmt2pks: no loop in %d frames: the song plays once, then silence\n' % a.frames)
        recs = recs[:start] + [bytes(REGS)]
        start, period = len(recs) - 1, 1

    used = [r for r in range(REGS) if len({x[r] for x in recs[:start + period]}) > 1]
    order = list(reversed(used))                    # the player goes from the last
    init = bytes(recs[0])

    enc = []
    for lo, hi in ((0, start), (start, start + period)):
        for r in order:
            raw = bytes(x[r] for x in recs[lo:hi])
            e = rmt2sid.lzss(rmt2sid.events(raw)) if raw else b''
            if raw and rmt2sid.unlzss(e, len(raw)) != raw:
                die('LZSS check failed (register %d)' % r)
            enc.append(e)

    n = len(order)
    head = bytearray(b'PKS\x01')
    head.append(n)
    head.append(a.rate)
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
    Path(a.out).write_bytes(blob)
    print('rmt2pks: %s -> %s: %d bytes, %d streams, intro %d frames, loop %d frames (%.1f s)'
          % (a.song, a.out, len(blob), n, start, period, period / a.rate))


if __name__ == '__main__':
    main()
