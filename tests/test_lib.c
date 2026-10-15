/* test_lib.c - libvera on every host, one source.
 *
 *   VERA screen   demo.vbm (320x240, 8 bpp, layer 0) streamed from the disk
 *                 through the asset layer, a text line over it (layer 1,
 *                 colour 0 = transparent), a 16x16 sprite moved by the
 *                 joystick
 *   VERA PSG      the RMT song linked in, from the VERA frame clock
 *   host screen   the second monitor (ANTIC / VIC-II, conio): frames,
 *                 dropped frames, music frames, joystick, PSG levels
 *
 * Q or ESC (Atari) / RUN/STOP (C64) leaves.
 */

#include <conio.h>

#include "vera_detect.h"
#include "vera_irq.h"
#include "vmem.h"
#include "vtext.h"
#include "vbm.h"
#include "rmt.h"
#include "plat.h"
#include "hud.h"

#define SPR_DATA   0x13000ul            /* after the 320x240 bitmap ($12C00) */
#define SPR_ATTR0  VERA_SPRITE_BASE

static unsigned int px = 152, py = 112; /* sprite position (320x240) */
static unsigned int frames, dropped;

static void load_progress(const char *name, unsigned char name_len,
                          unsigned long loaded, unsigned long total)
{
    unsigned char i;

    if (loaded == 0) {
        gotoxy(0, 4);
        cputs("Image: ");
        for (i = 0; i < name_len && i < 32; ++i)
            cputc(name[i]);
    }
    gotoxy(0, 5);
    cprintf("Loading %3u%%", (unsigned)(loaded * 100ul / total));
}

/* the sprite: a 16x16 white and black ring (colours 1 and 255 of the
 * image), made in VRAM */
static void make_sprite(void)
{
    unsigned char r;
    static const unsigned char attr[8] = {
        (unsigned char)(SPR_DATA >> 5),                 /* address 12:5 */
        0x80 | (unsigned char)(SPR_DATA >> 13),         /* 8 bpp, address 16:13 */
        0, 0, 0, 0,                                     /* X, Y */
        0x0C,                                           /* Z = 3: in front */
        0x50                                            /* 16x16, palette 0 */
    };

    vram_seek(VRAM(SPR_DATA, VERA_INC4));               /* 256 bytes, 32 bit fill */
    vram_fill32(1, 256 / 4);                            /* white (image colour 1) */
    for (r = 2; r < 14; ++r) {                          /* black ring inside */
        vram_seek(VRAM(SPR_DATA + r * 16u + 2, VERA_INC1));
        vram_fill(255, 12);                             /* image colour 255 */
    }
    for (r = 4; r < 12; ++r) {                          /* hollow inside */
        vram_seek(VRAM(SPR_DATA + r * 16u + 4, VERA_INC1));
        vram_fill(0, 8);
    }
    vram_seek(VRAM(SPR_ATTR0, VERA_INC1));
    vram_write(attr, sizeof attr);
    VERA_CTRL = 0;
    VERA_DC_VIDEO |= VERA_VIDEO_SPRITES;
}

static void move_sprite(void)
{
    vram_seek(VRAM(SPR_ATTR0 + 2, VERA_INC1));
    VERA_DATA0 = (unsigned char)px;
    VERA_DATA0 = (unsigned char)(px >> 8);
    VERA_DATA0 = (unsigned char)py;
    VERA_DATA0 = (unsigned char)(py >> 8);
}

/* the VERA line being drawn (0-524) */
static unsigned scanline(void)
{
    VERA_CTRL = 0;
    return VERA_SCANLINE_L | ((VERA_IEN & 0x40) << 2);
}

static unsigned start_line, cur_lines, max_lines;

/* one line of the host screen per frame: never more than a few hundred
 * cycles (hud.h) */
static void status(unsigned char row, unsigned char joy)
{
    unsigned char i;

    switch (row) {
    case 0:
        hud_u16(12, 8, frames, 5);
        hud_u16(27, 8, dropped, 5);
        break;
    case 1:
        hud_u16(6, 9, rmt_frames, 5);
        hud_u16(18, 9, cur_lines, 3);
        hud_u16(26, 9, max_lines, 3);
        break;
    case 2:
        hud_puts(9, 10, joy & PAD_UP ? "u" : "-");
        hud_puts(10, 10, joy & PAD_DOWN ? "d" : "-");
        hud_puts(11, 10, joy & PAD_LEFT ? "l" : "-");
        hud_puts(12, 10, joy & PAD_RIGHT ? "r" : "-");
        hud_puts(13, 10, joy & PAD_FIRE ? "f" : "-");
        hud_u16(22, 10, px, 3);
        hud_u16(26, 10, py, 3);
        break;
    default:
        for (i = 0; i < 4; ++i)
            hud_u16((unsigned char)(4 + 3 * i), 11, psg_volume[i], 2);
        break;
    }
}

int main(void)
{
    unsigned char n, joy = 0, tick = 0, k, have_image;

    clrscr();
    cputs("libvera test - " PLAT_NAME "\r\n");
    vera_require();
    cprintf("VERA %u.%u.%u  %s host\r\n", vera_version[0], vera_version[1],
            vera_version[2], plat_ntsc ? "NTSC" : "PAL");

    have_image = vbm_load("demo.vbm", load_progress);
    gotoxy(0, 5);
    cputs(have_image ? "Image loaded.   " : "No demo.vbm.    ");

    vbm_init();
    vt_color = 0x01;                    /* bg 0: the bitmap shows through */
    vt_init(VT_40X30);
    vt_gotoxy(1, 28);
    vt_puts("libvera on " PLAT_NAME);
    make_sprite();

    vera_frame_init();
    rmt_init(rmt_song);
    rmt_start();

    gotoxy(0, 8);
    cputs("VERA frames        dropped\r\n");
    cputs("Music       work      max      lines\r\n");
    cputs("Joystick       sprite    ,\r\n");
    cputs("PSG\r\n\r\n");
    cputs("Joystick moves the sprite, Q quits.");
    hud_init();

    vera_frame_wait();                  /* the start-up is not a dropped frame */
    for (;;) {
        n = vera_frame_wait();
        start_line = scanline();
        frames += n;
        dropped += n - 1;

        joy = plat_joy();
        if ((joy & PAD_LEFT) && px >= n)        px -= n;
        if ((joy & PAD_RIGHT) && px < 304)      px += n;
        if ((joy & PAD_UP) && py >= n)          py -= n;
        if ((joy & PAD_DOWN) && py < 224)       py += n;
        move_sprite();

        status((unsigned char)(++tick & 3), joy);
        cur_lines = scanline() + 525 - start_line;    /* VERA lines of work */
        if (cur_lines >= 525)
            cur_lines -= 525;
        if (frames > 60 && cur_lines > max_lines)   /* not the start-up */
            max_lines = cur_lines;

        if (kbhit()) {
            k = cgetc();
            if (k == PLAT_KEY_EXIT || k == 'q' || k == 'Q')
                break;
        }
    }

    rmt_stop();
    vera_irq_remove();
    VERA_CTRL = 0;
    VERA_DC_VIDEO &= (unsigned char)~(VERA_VIDEO_SPRITES | VERA_VIDEO_LAYER0);
    vbm_done();
    vt_color = VT_COLOR;
    vt_init(VT_80X30);
    gotoxy(0, 15);
    cputs("Bye.\r\n");
    return 0;
}
