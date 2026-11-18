#include <stdio.h>
#include <string.h>

#include "vera.h"
#include "vmem.h"
#include "vera_irq.h"

extern unsigned vera_pc_test_pixel(unsigned x, unsigned y);

int main(void)
{
    static const unsigned char expected[] = { 0x12, 0x34, 0x56, 0x78 };
    static const unsigned char sprite_pixels[32] = {
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11
    };
    static const unsigned char sprite_attr[8] = {
        0x80, 0x00, 10, 0, 10, 0, 0x0C, 0x00
    };
    static const unsigned char sprite_color[2] = { 0x0F, 0x00 };
    unsigned char actual[sizeof expected];

    vera_frame_init();
    vram_seek(VRAM(0x1234, VERA_INC1));
    vram_write(expected, sizeof expected);
    vram_seek(VRAM(0x1234, VERA_INC1));
    vram_read(actual, sizeof actual);
    if (memcmp(expected, actual, sizeof expected)) {
        fputs("libvera PC VRAM transfer failed\n", stderr);
        return 1;
    }
    vram_seek(VRAM(0x1000, VERA_INC1));
    vram_write(sprite_pixels, sizeof sprite_pixels);
    vram_seek(VRAM(VERA_PALETTE_BASE + 2, VERA_INC1));
    vram_write(sprite_color, sizeof sprite_color);
    vram_seek(VRAM(VERA_SPRITE_BASE, VERA_INC1));
    vram_write(sprite_attr, sizeof sprite_attr);
    VERA_DC_VIDEO = VERA_VIDEO_SPRITES;
    if (vera_frame_wait() != 1) {
        fputs("libvera PC frame clock failed\n", stderr);
        return 1;
    }
    if (vera_pc_test_pixel(10, 10) != 0xff0000ffu) {
        fputs("libvera PC sprite rendering failed\n", stderr);
        return 1;
    }
    vera_irq_remove();
    return 0;
}
