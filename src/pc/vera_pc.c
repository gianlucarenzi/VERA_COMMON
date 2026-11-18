#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vera.h"
#include "vmem.h"
#include "vera_irq.h"
#include "vera_detect.h"
#include "plat.h"

volatile unsigned char vera_pc_registers[0x20];
static unsigned char vram[0x20000];
static unsigned char key_state;
static unsigned char key_queue[32], key_read, key_write;
static void (*frame_callback)(void);
static unsigned vaddr[2], vinc[2];
volatile unsigned char vera_irq_count[4];
unsigned char plat_ntsc = 1;
unsigned char vera_version[3];

static SDL_Window *window;
static SDL_Renderer *renderer;
static SDL_Texture *texture;
static Uint32 last_frame;

static unsigned address(unsigned port)
{
    return vaddr[port] & 0x1ffffu;
}

static unsigned increment(unsigned port)
{
    return vinc[port];
}

static unsigned increment_value(unsigned long v)
{
    unsigned code = ((unsigned)(v >> 16) >> 4) & 15u;
    return code ? 1u << (code - 1) : 0u;
}

static void queue_key(unsigned char key)
{
    unsigned char next = (unsigned char)((key_write + 1u) & 31u);
    if (next != key_read) {
        key_queue[key_write] = key;
        key_write = next;
    }
}

volatile unsigned char *vera_pc_data0(void)
{
    unsigned at = address(0);
    vaddr[0] = (at + increment(0)) & 0x1ffffu;
    return &vram[at];
}

volatile unsigned char *vera_pc_data1(void)
{
    unsigned at = address(1);
    vaddr[1] = (at + increment(1)) & 0x1ffffu;
    return &vram[at];
}

static Uint32 pixels[320 * 240];

Uint32 vera_pc_test_pixel(unsigned x, unsigned y)
{
    return x < 320 && y < 240 ? pixels[y * 320u + x] : 0;
}

static Uint32 color(unsigned index)
{
    unsigned address = 0x1fa00u + index * 2u;
    unsigned lo = vram[address], hi = vram[address + 1];
    return 0xff000000u | ((hi & 15u) * 17u << 16)
        | ((lo >> 4) * 17u << 8) | ((lo & 15u) * 17u);
}

static void draw_layer(unsigned layer)
{
    unsigned reg = layer ? 0x14u : 0x0du;
    unsigned map = vera_pc_registers[reg + 1] * 512u;
    unsigned tiles = (vera_pc_registers[reg + 2] >> 2) * 2048u;
    unsigned sx = vera_pc_registers[reg + 3] | (vera_pc_registers[reg + 4] << 8);
    unsigned sy = vera_pc_registers[reg + 5] | (vera_pc_registers[reg + 6] << 8);
    unsigned x, y;
    for (y = 0; y < 240; ++y) {
        unsigned wy = (y + sy) & 511u;
        for (x = 0; x < 320; ++x) {
            unsigned wx = (x + sx) & 511u;
            unsigned ma = map + ((wy >> 3) * 64u + (wx >> 3)) * 2u;
            unsigned entry = vram[ma] | (vram[ma + 1] << 8);
            unsigned tx = wx & 7u, ty = wy & 7u;
            if (entry & 0x1000u) tx = 7u - tx;
            if (entry & 0x2000u) ty = 7u - ty;
            unsigned tile = entry & 0x0fffu;
            unsigned ta = (tiles + tile * 32u + ty * 4u + (tx >> 1)) & 0x1ffffu;
            unsigned packed = vram[ta];
            unsigned pen = (tx & 1u) ? packed >> 4 : packed & 15u;
            unsigned palette = ((entry >> 14) & 3u) * 16u + pen;
            if (pen)
                pixels[y * 320u + x] = color(palette);
        }
    }
}

static int sprite_coord(unsigned low, unsigned high)
{
    int value = (int)(low | ((high & 3u) << 8));
    return value & 0x200 ? value - 0x400 : value;
}

static void draw_sprites(unsigned z)
{
    int index;
    for (index = 127; index >= 0; --index) {
        unsigned at = VERA_SPRITE_BASE + (unsigned)index * 8u;
        unsigned char *a = vram + at;
        unsigned depth = (a[6] >> 2) & 3u;
        unsigned width, height, row_bytes, base, palette;
        int sx, sy, x, y;
        if (depth != z)
            continue;
        width = 8u << ((a[7] >> 4) & 3u);
        height = 8u << ((a[7] >> 6) & 3u);
        row_bytes = width >> 1;
        base = ((unsigned)a[0] | ((unsigned)(a[1] & 15u) << 8)) << 5;
        palette = (a[7] & 15u) << 4;
        sx = sprite_coord(a[2], a[3]);
        sy = sprite_coord(a[4], a[5]);
        for (y = 0; y < (int)height; ++y) {
            int py = sy + y;
            unsigned ty = (a[6] & 2u) ? height - 1u - (unsigned)y : (unsigned)y;
            if (py < 0 || py >= 240)
                continue;
            for (x = 0; x < (int)width; ++x) {
                int px = sx + x;
                unsigned tx, packed, pen;
                if (px < 0 || px >= 320)
                    continue;
                tx = (a[6] & 1u) ? width - 1u - (unsigned)x : (unsigned)x;
                packed = vram[(base + ty * row_bytes + (tx >> 1)) & 0x1ffffu];
                pen = (tx & 1u) ? packed >> 4 : packed & 15u;
                if (pen)
                    pixels[(unsigned)py * 320u + (unsigned)px] =
                        color(palette + pen);
            }
        }
    }
}

static void present(void)
{
    unsigned x, y;
    if (!renderer)
        return;
    for (y = 0; y < 240; ++y)
        for (x = 0; x < 320; ++x)
            pixels[y * 320u + x] = 0xff000000u;
    if (vera_pc_registers[9] & VERA_VIDEO_LAYER0)
        draw_layer(0);
    if (vera_pc_registers[9] & VERA_VIDEO_SPRITES)
        draw_sprites(1);
    if (vera_pc_registers[9] & VERA_VIDEO_LAYER1)
        draw_layer(1);
    if (vera_pc_registers[9] & VERA_VIDEO_SPRITES) {
        draw_sprites(2);
        draw_sprites(3);
    }
    if (!texture)
        return;
    SDL_UpdateTexture(texture, NULL, pixels, 320 * (int)sizeof(Uint32));
    SDL_RenderClear(renderer);
    SDL_RenderCopy(renderer, texture, NULL, NULL);
    SDL_RenderPresent(renderer);
}

void vera_irq_install(void) {}
void vera_irq_remove(void) { frame_callback = 0; }
void vera_irq_enable(unsigned char mask) { (void)mask; }
void vera_irq_disable(unsigned char mask) { (void)mask; }
unsigned char vera_irq_take(void) { return 0; }
void vera_irq_set_line(unsigned line) { (void)line; }
void vera_irq_set_callback(void (*callback)(void))
{
    frame_callback = callback;
}

void vera_frame_init(void)
{
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) < 0) {
        fprintf(stderr, "libvera SDL init: %s\n", SDL_GetError());
        exit(EXIT_FAILURE);
    }
    window = SDL_CreateWindow("Rastan SDL / libvera", SDL_WINDOWPOS_CENTERED,
                              SDL_WINDOWPOS_CENTERED, 640, 480, SDL_WINDOW_RESIZABLE);
    if (!window) {
        fprintf(stderr, "libvera SDL window: %s\n", SDL_GetError());
        SDL_Quit();
        exit(EXIT_FAILURE);
    }
    if (window)
        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    if (!renderer && window)
        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
    if (!renderer) {
        fprintf(stderr, "libvera SDL renderer: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        window = NULL;
        SDL_Quit();
        exit(EXIT_FAILURE);
    }
    if (renderer) {
        SDL_RenderSetLogicalSize(renderer, 320, 240);
        texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                    SDL_TEXTUREACCESS_STREAMING, 320, 240);
        if (!texture) {
            fprintf(stderr, "libvera SDL texture: %s\n", SDL_GetError());
            SDL_DestroyRenderer(renderer);
            SDL_DestroyWindow(window);
            renderer = NULL;
            window = NULL;
            SDL_Quit();
            exit(EXIT_FAILURE);
        }
    }
    last_frame = SDL_GetTicks();
}

unsigned char vera_frame_wait(void)
{
    SDL_Event event;
    Uint32 now, delay;
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_QUIT) {
            key_state = 0;
            queue_key(PLAT_KEY_EXIT);
        }
        if (event.type == SDL_KEYDOWN || event.type == SDL_KEYUP) {
            unsigned char down = event.type == SDL_KEYDOWN;
            SDL_Scancode code = event.key.keysym.scancode;
            if (code == SDL_SCANCODE_UP) key_state = (key_state & ~PAD_UP) | (down ? PAD_UP : 0);
            if (code == SDL_SCANCODE_DOWN) key_state = (key_state & ~PAD_DOWN) | (down ? PAD_DOWN : 0);
            if (code == SDL_SCANCODE_LEFT) key_state = (key_state & ~PAD_LEFT) | (down ? PAD_LEFT : 0);
            if (code == SDL_SCANCODE_RIGHT) key_state = (key_state & ~PAD_RIGHT) | (down ? PAD_RIGHT : 0);
            if (code == SDL_SCANCODE_SPACE || code == SDL_SCANCODE_Z)
                key_state = (key_state & ~PAD_FIRE) | (down ? PAD_FIRE : 0);
            if (down && !event.key.repeat && code != SDL_SCANCODE_UP
                && code != SDL_SCANCODE_DOWN && code != SDL_SCANCODE_LEFT
                && code != SDL_SCANCODE_RIGHT && code != SDL_SCANCODE_SPACE
                && code != SDL_SCANCODE_Z) {
                SDL_Keycode key = SDL_GetKeyFromScancode(code);
                if (key >= 0x20 && key <= 0x7e)
                    queue_key((unsigned char)key);
                else if (code == SDL_SCANCODE_ESCAPE)
                    queue_key(PLAT_KEY_EXIT);
            }
        }
    }
    now = SDL_GetTicks();
    delay = now - last_frame;
    if (delay < 17u)
        SDL_Delay(17u - delay);
    last_frame = SDL_GetTicks();
    ++vera_irq_count[0];
    if (frame_callback)
        frame_callback();
    present();
    return 1;
}

unsigned vera_scanline(void) { return (SDL_GetTicks() % 17u) * 30u; }
unsigned vera_lines_since(unsigned start)
{
    unsigned now = vera_scanline();
    return now >= start ? now - start : 525u - start + now;
}
unsigned char plat_joy(void) { return key_state; }
unsigned char plat_key_hit(void) { return key_read != key_write; }
unsigned char plat_key_get(void)
{
    unsigned char key = key_queue[key_read];
    if (key_read != key_write)
        key_read = (unsigned char)((key_read + 1u) & 31u);
    return key;
}
unsigned char plat_rtc(struct sd_time *t) { (void)t; return 0; }

unsigned int vera_detect(void)
{
    vera_version[0] = 48;
    vera_version[1] = 0;
    vera_version[2] = 0;
    return VERA_CARD_ID;
}

unsigned int vera_require(void) { return vera_detect(); }

void vram_seek(unsigned long v)
{
    vaddr[0] = (unsigned)v & 0x1ffffu;
    vera_pc_registers[0] = (unsigned char)v;
    vera_pc_registers[1] = (unsigned char)(v >> 8);
    vera_pc_registers[2] = (unsigned char)(v >> 16);
    vinc[0] = increment_value(v);
}
void vram_seek1(unsigned long v)
{
    vaddr[1] = (unsigned)v & 0x1ffffu;
    vinc[1] = increment_value(v);
}
void vram_write(const void *src, unsigned n)
{
    const unsigned char *p = src;
    while (n--) { vram[address(0)] = *p++; vaddr[0] = (vaddr[0] + increment(0)) & 0x1ffffu; }
}
void vram_read(void *dst, unsigned n)
{
    unsigned char *p = dst;
    while (n--) { *p++ = vram[address(0)]; vaddr[0] = (vaddr[0] + increment(0)) & 0x1ffffu; }
}
void vram_fill(unsigned char value, unsigned n)
{
    while (n--) { vram[address(0)] = value; vaddr[0] = (vaddr[0] + increment(0)) & 0x1ffffu; }
}
void vram_fill32(unsigned char value, unsigned n)
{
    vram_fill(value, n * 4u);
}
void vram_copy(unsigned n)
{
    while (n--) {
        vram[address(0)] = vram[address(1)];
        vaddr[0] = (vaddr[0] + increment(0)) & 0x1ffffu;
        vaddr[1] = (vaddr[1] + increment(1)) & 0x1ffffu;
    }
}

void sfx_init(const void *bank) { (void)bank; }
void sfx_play(unsigned char id) { (void)id; }
void sfx_stop(void) {}
unsigned char sfx_busy(void) { return 0; }
void pcm_play(const void *sound) { (void)sound; }
void pcm_stop(void) {}
unsigned char pcm_busy(void) { return 0; }
