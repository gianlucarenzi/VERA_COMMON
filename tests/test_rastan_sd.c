/* test_rastan_sd.c - load a real Rastan asset from the SD card and report it
 * on the HUD. This is a direct smoke test for microSD-based asset streaming.
 */

#include <stdio.h>
#include <string.h>
#include "hud.h"

extern unsigned char sd_mount(void);
extern unsigned char __fastcall__ sd_open(const char *path);
extern unsigned __fastcall__ sd_read(void *dst, unsigned n);
extern void sd_close(void);
extern unsigned char sd_errno(void);

static char buf[128];

int main(void) {
    unsigned char ok;
    unsigned nread;

    hud_init();
    hud_puts(0, 0, "Loading Rastan from microSD");
    hud_puts(0, 1, "mounting...");

    ok = sd_mount();
    if (!ok) {
        hud_puts(0, 2, "FAIL: mount");
        printf("sd_mount() failed: %d\n", sd_errno());
        fflush(stdout);
        while (1) {
            /* keep screen visible */
        }
    }

    hud_puts(0, 2, "mounted OK");
    hud_puts(0, 3, "opening /rastan/r1field/level.json");

    ok = sd_open("/rastan/r1field/level.json");
    if (!ok) {
        hud_puts(0, 4, "FAIL: open level.json");
        printf("sd_open() failed: %d\n", sd_errno());
        fflush(stdout);
        while (1) {
            /* keep screen visible */
        }
    }

    nread = sd_read(buf, sizeof(buf) - 1);
    buf[nread] = '\0';
    printf("Read %u bytes from /rastan/r1field/level.json\n", nread);
    printf("Header: %s\n", buf);
    fflush(stdout);

    hud_puts(0, 4, "level.json read OK");
    hud_puts(0, 5, "streaming from microSD");
    hud_puts(0, 6, "Rastan assets ready");

    sd_close();

    while (1) {
        /* hold on screen for visual verification */
    }

    return 0;
}
