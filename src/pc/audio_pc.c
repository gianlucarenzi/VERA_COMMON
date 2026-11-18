/* audio_pc.c - libvera PC (SDL2): the VERA audio.
 *
 * The PSG (16 voices, registers at VERA_PSG_BASE in the VRAM array: the
 * game writes them as on the VERA) and the PCM channel, mixed into SDL
 * audio; sfx.s (sfx.h) and pcm.s (pcm.h) in C.  The frame clock
 * (vera_frame_wait) calls vera_pc_audio_frame once a VSYNC, as vera_irq.s
 * calls the sound callbacks: first vera_pc_sound (a game's music player),
 * then the effects, then the PCM.
 *
 * sfx bank on PC (RastanRIP pc/s2c.py --blob): .byte count, .word the
 * offset of each effect FROM THE START OF THE BANK (the 6502 hosts have
 * the address), an effect: .byte frames, then 4 bytes a frame. */
#include <SDL.h>
#include <string.h>

#include "vera.h"
#include "pcm.h"
#include "sfx.h"

#define VERA_HZ 48828.125
#define SFX_V0 12
#define SFX_NV 4

unsigned char *vera_pc_vram(void);
void (*vera_pc_sound)(void); /* the music player's frame (e.g. RastanRIP pc/music.c) */

static SDL_AudioDeviceID dev;
static double step; /* VERA samples per output sample */
static unsigned phase[16];
static unsigned short noise = 1;
static unsigned char noise_bit;

/* the PCM channel: samples from VRAM at rate * 48828 / 128 Hz */
static unsigned long pcm_at;
static unsigned pcm_left;
static double pcm_pos, pcm_inc;
static signed char pcm_cur;

/* VERA's logarithmic volume (x16emu) */
static const unsigned char vol_log[64] = {0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3,
                                          4, 4, 4, 4, 5, 5, 5, 6, 6, 7, 7, 7, 8, 8, 9, 9,
                                          10, 11, 11, 12, 13, 14, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25,
                                          26, 28, 29, 31, 33, 35, 37, 39, 42, 44, 47, 50, 52, 56, 59, 63};

/* one VERA sample of the PSG: left and right */
static void psg_sample(int *l, int *r)
{
    const unsigned char *reg = vera_pc_vram() + VERA_PSG_BASE;
    int k;
    *l = *r = 0;
    for (k = 0; k < 16; ++k, reg += 4)
    {
        unsigned f = reg[0] | reg[1] << 8, vol = reg[2] & 63, wave = reg[3] >> 6, pw = reg[3] & 63;
        unsigned old = phase[k];
        int v;
        if (!vol || !(reg[2] & 0xC0))
        {
            phase[k] = (phase[k] + f) & 0x1FFFF;
            continue;
        }
        phase[k] = (phase[k] + f) & 0x1FFFF;
        /* as the VERA (x16emu audio.c): a 6-bit unsigned level, then signed */
        switch (wave)
        {
            case 0: /* pulse: high while phase[16:10] <= width (63 = 50%) */
                v = (phase[k] >> 10) > pw ? 0 : 63;
                break;
            case 1: /* sawtooth */
                v = (int)(phase[k] >> 11);
                break;
            case 2: /* triangle */
                v = phase[k] & 0x10000 ? (int)(~(phase[k] >> 10) & 0x3F) : (int)((phase[k] >> 10) & 0x3F);
                break;
            default: /* noise: a new value when the phase wraps */
                if (phase[k] < old)
                {
                    noise_bit = (unsigned char)(((noise >> 0) ^ (noise >> 1)) & 1);
                    noise = (unsigned short)((noise >> 1) | (noise_bit << 15));
                }
                v = noise & 0x3F;
                break;
        }
        v -= 32; /* -32 .. 31 */
        v *= vol_log[vol];
        if (reg[2] & 0x40)
            *l += v;
        if (reg[2] & 0x80)
            *r += v;
    }
}

static void callback(void *ud, Uint8 *stream, int len)
{
    Sint16 *out = (Sint16 *)stream;
    int n = len / 4, i;
    static double acc;
    static int sl, sr;
    (void)ud;
    for (i = 0; i < n; ++i)
    {
        int l, r, p = 0;
        for (acc += step; acc >= 1.0; acc -= 1.0)
        {
            psg_sample(&sl, &sr);
            if (pcm_left)
            {
                pcm_pos += pcm_inc;
                while (pcm_pos >= 1.0 && pcm_left)
                {
                    pcm_cur = (signed char)vera_pc_vram()[pcm_at & 0x1FFFF];
                    ++pcm_at;
                    --pcm_left;
                    pcm_pos -= 1.0;
                }
            }
            else
                pcm_cur = 0;
        }
        p = pcm_cur * 64;
        l = (sl >> 1) + p;
        r = (sr >> 1) + p;
        out[i * 2] = (Sint16)(l > 32767 ? 32767 : l < -32768 ? -32768
                                                             : l);
        out[i * 2 + 1] = (Sint16)(r > 32767 ? 32767 : r < -32768 ? -32768
                                                                 : r);
    }
}

void vera_pc_audio_open(void)
{
    SDL_AudioSpec want, have;
    if (dev || SDL_InitSubSystem(SDL_INIT_AUDIO) < 0)
        return;
    memset(&want, 0, sizeof want);
    want.freq = 48000;
    want.format = AUDIO_S16SYS;
    want.channels = 2;
    want.samples = 1024;
    want.callback = callback;
    dev = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
    if (!dev)
        return;
    step = VERA_HZ / have.freq;
    SDL_PauseAudioDevice(dev, 0);
}

/* --- sfx.s -------------------------------------------------------------- */

static const unsigned char *bank;
static const unsigned char *vptr[SFX_NV];
static unsigned char vcnt[SFX_NV], vage[SFX_NV], age;

static unsigned char *voice(unsigned char x)
{
    return vera_pc_vram() + VERA_PSG_BASE + 4 * (SFX_V0 + x);
}

void sfx_init(const void *b)
{
    bank = b;
    sfx_stop();
}

unsigned char sfx_busy(void)
{
    unsigned char x;
    for (x = 0; x < SFX_NV; ++x)
        if (vcnt[x])
            return 1;
    return 0;
}

void sfx_play(unsigned char id)
{
    unsigned char x, best;
    const unsigned char *p;
    if (!bank)
        return;
    for (x = 0; x < SFX_NV && vcnt[x]; ++x)
        ;
    if (x == SFX_NV)
    { /* the oldest */
        unsigned char y;
        best = (unsigned char)(age - vage[0]);
        x = 0;
        for (y = 1; y < SFX_NV; ++y)
            if ((unsigned char)(age - vage[y]) >= best)
            {
                best = (unsigned char)(age - vage[y]);
                x = y;
            }
    }
    p = bank + (bank[1 + id * 2] | bank[2 + id * 2] << 8);
    vcnt[x] = (unsigned char)(p[0] + 1);
    vptr[x] = p + 1;
    vage[x] = ++age;
}

void sfx_stop(void)
{
    unsigned char x;
    for (x = 0; x < SFX_NV; ++x)
        vcnt[x] = 1; /* silenced by the next tick */
}

static void sfx_tick(void)
{
    unsigned char x;
    for (x = 0; x < SFX_NV; ++x)
    {
        unsigned char *v;
        if (!vcnt[x])
            continue;
        v = voice(x);
        if (!--vcnt[x])
        {
            v[0] = v[1] = v[2] = v[3] = 0;
            continue;
        }
        memcpy(v, vptr[x], 4);
        vptr[x] += 4;
    }
}

/* --- pcm.s -------------------------------------------------------------- */

void pcm_play(const pcm_sound *s)
{
    if (dev)
        SDL_LockAudioDevice(dev);
    pcm_at = s->vram;
    pcm_left = s->len;
    pcm_pos = 0;
    pcm_inc = s->rate / 128.0;
    if (dev)
        SDL_UnlockAudioDevice(dev);
}

void pcm_stop(void)
{
    if (dev)
        SDL_LockAudioDevice(dev);
    pcm_left = 0;
    if (dev)
        SDL_UnlockAudioDevice(dev);
}

unsigned char pcm_busy(void)
{
    return pcm_left != 0;
}

/* once a VSYNC (vera_frame_wait): the music, the effects */
void vera_pc_audio_frame(void)
{
    if (vera_pc_sound)
        vera_pc_sound();
    sfx_tick();
}
