#!/usr/bin/env python3
"""
psgsfx.py - sound effects for the VERA PSG (src/common/sfx.s, sfx.h)

    python3 tools/psgsfx.py effects.py bank.s [--header ids.h] [--wav dir]

effects.py defines EFFECTS = [(name, frames), ...]; a frame is one VERA
frame (59.5 Hz) of a PSG voice: frame(freq Hz, volume 0..63, wave, pw, pan)
with wave 'pulse' | 'saw' | 'tri' | 'noise', pw 0..63 (pulse width, 63 = 50%),
pan 'LR' | 'L' | 'R'.  At most 63 frames an effect.  The helpers below
(sweep, env, ...) make the frame lists.

bank.s (ca65): the bank of sfx_init: .byte count, .word effect..; each
effect .byte frames, then 4 bytes a frame (the PSG voice registers).
ids.h: #define SFX_<NAME> id.  --wav: a preview of every effect, rendered
with the PSG of x16emu (vera_psg.c: 17 bit phase at 25 MHz / 512, the
shared noise LFSR, its volume table).
"""
import argparse
import math
import random
import runpy
import struct
import wave

PSG_RATE = 25e6 / 512                    # sample rate of the VERA PSG
WORD_HZ = PSG_RATE / 2 ** 17             # Hz per frequency word step
FRAME_HZ = 25e6 / 800 / 525              # VERA frame rate (59.52 Hz)
WAVES = {'pulse': 0, 'saw': 1, 'tri': 2, 'noise': 3}
PANS = {'LR': 0xC0, 'L': 0x40, 'R': 0x80}


def frame(freq, vol, wave='pulse', pw=63, pan='LR'):
    return (float(freq), int(max(0, min(63, round(vol)))), wave, int(max(0, min(63, pw))), pan)


def regs(f):
    freq, vol, wv, pw, pan = f
    w = max(0, min(65535, round(freq / WORD_HZ)))
    return bytes([w & 0xFF, w >> 8, (PANS[pan] if vol else 0) | vol, (WAVES[wv] << 6) | pw])


# -- helpers ------------------------------------------------------------------
def sweep(f0, f1, n, curve='exp'):
    """n frequencies from f0 to f1 (exponential or linear)"""
    if n == 1:
        return [f0]
    if curve == 'exp':
        return [f0 * (f1 / f0) ** (i / (n - 1)) for i in range(n)]
    return [f0 + (f1 - f0) * i / (n - 1) for i in range(n)]


def env(points, n):
    """n volumes along the (frame, volume) points, linear in between"""
    out = []
    for i in range(n):
        for (a, va), (b, vb) in zip(points, points[1:]):
            if a <= i <= b:
                out.append(va + (vb - va) * (i - a) / max(1, b - a))
                break
        else:
            out.append(points[-1][1])
    return out


def vibrato(freqs, depth, rate_hz):
    """frequency vibrato: depth (fraction), rate in Hz"""
    return [f * (1 + depth * math.sin(2 * math.pi * rate_hz * i / FRAME_HZ)) for i, f in enumerate(freqs)]


# -- PSG model (previews) -----------------------------------------------------
# x16emu vera_psg.c (the FPGA 48.0.1 behaviour): 17 bit phase, a voice runs
# only with pan bits set; noise from ONE 16 bit LFSR shared by the 16 voices,
# stepped once per voice every sample, a voice takes (state >> 1) & 63 when
# bit 16 of its phase falls (the noise is not random: a model with random
# values sounded different from the emulator, 2026-10-21); pulse high while
# phase >> 10 <= pw; 6 bit signed samples times volume_lut, >> 3.
VOLUME_LUT = [0, 4, 8, 12, 16, 17, 18, 20, 21, 22, 23, 25, 26, 28, 30, 31,
              33, 35, 37, 40, 42, 45, 47, 50, 53, 56, 60, 63, 67, 71, 75, 80,
              85, 90, 95, 101, 107, 113, 120, 127, 135, 143, 151, 160, 170, 180, 191, 202,
              214, 227, 241, 255, 270, 286, 303, 321, 341, 361, 382, 405, 429, 455, 482, 511]
VOICE = 12                               # sfx.s plays from voice 12


def render(frames, seed=1):
    out = []
    phase = 0
    noiseval = 0
    noise = 1
    spf = PSG_RATE / FRAME_HZ
    acc = 0.0
    for f in frames + [frame(0, 0)] * 6:
        r = regs(f)
        w = r[0] | r[1] << 8
        vol = VOLUME_LUT[r[2] & 63]
        on = r[2] & 0xC0
        wv = r[3] >> 6
        pw = r[3] & 63
        acc += spf
        n = int(acc)
        acc -= n
        for _ in range(n):
            for ch in range(16):
                noise = ((noise << 1) | (((noise >> 1) ^ (noise >> 2) ^ (noise >> 4) ^ (noise >> 15)) & 1)) & 0xFFFF
                if ch != VOICE:
                    continue
                new = (phase + w) & 0x1FFFF if on else 0
                if (phase & 0x10000) and not (new & 0x10000):
                    noiseval = (noise >> 1) & 0x3F
                phase = new
                if wv == 0:
                    v = 0 if (phase >> 10) > pw else 0x3F
                elif wv == 1:
                    v = (phase >> 11) ^ ((pw ^ 0x3F) & 0x3F)
                elif wv == 2:
                    v = ((~(phase >> 10) & 0x3F) if phase & 0x10000 else ((phase >> 10) & 0x3F)) ^ ((pw ^ 0x3F) & 0x3F)
                else:
                    v = noiseval
                sv = v ^ 0x20
                if sv & 0x20:
                    sv -= 64
                out.append((sv * vol >> 3) / 2048.0)
    return out


def write_wav(path, samples):
    w = wave.open(path, 'wb')
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(int(PSG_RATE))
    w.writeframes(struct.pack('<%dh' % len(samples), *(int(s * 30000) for s in samples)))
    w.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('effects')
    ap.add_argument('out')
    ap.add_argument('--header')
    ap.add_argument('--label', default='sfx_bank')
    ap.add_argument('--wav')
    a = ap.parse_args()
    fx = runpy.run_path(a.effects)['EFFECTS']
    src = ['; generated by tools/psgsfx.py from %s - do not edit' % a.effects,
           '        .export _%s' % a.label, '        .segment "RODATA"',
           '_%s:' % a.label, '        .byte %d' % len(fx)]
    src += ['        .word fx_%s' % name for name, _ in fx]
    total = 1 + 2 * len(fx)
    for name, frames in fx:
        if not 1 <= len(frames) <= 63:
            raise SystemExit('%s: %d frames (1..63)' % (name, len(frames)))
        data = b''.join(regs(f) for f in frames)
        src.append('fx_%s:   ; %d frames, %.2f s' % (name, len(frames), len(frames) / FRAME_HZ))
        src.append('        .byte %d' % len(frames))
        for i in range(0, len(data), 16):
            src.append('        .byte ' + ','.join('$%02X' % b for b in data[i:i + 16]))
        total += 1 + len(data)
    open(a.out, 'w').write('\n'.join(src) + '\n')
    if a.header:
        guard = '__%s_H__' % a.label.upper()
        h = ['/* generated by tools/psgsfx.py from %s - do not edit */' % a.effects,
             '#ifndef %s' % guard, '#define %s' % guard,
             'extern const unsigned char %s[];' % a.label]
        h += ['#define SFX_%s %d' % (name.upper(), i) for i, (name, _) in enumerate(fx)]
        h.append('#endif')
        open(a.header, 'w').write('\n'.join(h) + '\n')
    if a.wav:
        for name, frames in fx:
            write_wav('%s/%s.wav' % (a.wav, name), render(frames))
    print('%s: %d effects, %d bytes' % (a.out, len(fx), total))


if __name__ == '__main__':
    main()
