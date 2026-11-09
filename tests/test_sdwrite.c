/* test_sdwrite.c - writing on the microSD of the VERA (sdfs.h, FAT32 code
 * of libvera_sd.lib): create, write, close, read back, rename, delete, a
 * directory.
 *
 * Build: make PLATFORM=<host> test-sdwrite; run it with a FAT32 image as the
 * card (tests/gen_test_image.py), then look at the image on the PC:
 *   mdir -i <img> ::  ->  WTEST2.BIN (1000 bytes), WDIR, no WTEST.BIN, no GONE.BIN;
 *   LongerName.text and a+b.c with mangled short names (LOxxxx~1.TEX,
 *   A_xxxx~1.C), the 8.3 ones as they are (WTEST2.BIN, WDIR); their date
 *   the one of the RTC adapter ("time rtc ..." on the screen), else
 *   2001-02-03 04:05 (sd_set_time)
 *   the bytes of WTEST2.BIN: i * 7 + (i >> 8) for i = 0..999
 * The last line on the screen is "SDWRITE OK" or "SDWRITE FAIL <step> <errno>".
 */

#include <stdio.h>
#include <string.h>
#include "sdfs.h"

#define N 1000

static unsigned char out[N], in[N];

static void fail(const char *step)
{
    printf("SDWRITE FAIL %s %u\n", step, sd_errno());
    for (;;)
        ;
}

int main(void)
{
    unsigned i;

    printf("sd write test\n");
    for (i = 0; i < N; ++i) out[i] = (unsigned char)(i * 7 + (i >> 8));

    if (!sd_mount()) fail("mount");

    /* the time of the files: the RTC adapter if there is one, else this */
    {
        static struct sd_time t = { 2001, 2, 3, 4, 5, 6 };
        unsigned char rtc;
        sd_set_time(&t);
        rtc = sd_get_time(&t);
        printf("time %s %u-%02u-%02u %02u:%02u:%02u\n", rtc ? "rtc" : "set",
               t.year, t.month, t.day, t.hour, t.minute, t.second);
    }

    /* a file in two writes, across a sector */
    if (!sd_create("wtest.bin", 1)) fail("create");
    if (!sd_write(out, 300)) fail("write1");
    if (!sd_write(out + 300, N - 300)) fail("write2");
    if (!sd_close()) fail("close");
    printf("written %u\n", N);

    /* back */
    if (!sd_open("wtest.bin")) fail("open");
    memset(in, 0, N);
    if (sd_read(in, N) != N) fail("read");
    sd_close();
    if (memcmp(in, out, N)) fail("compare");
    printf("read back ok\n");

    /* no overwrite: SD_ERR_EXISTS */
    if (sd_create("wtest.bin", 0)) fail("noover");
    if (sd_errno() != SD_ERR_EXISTS) fail("exists");

    /* a file deleted, one renamed, a directory */
    if (!sd_create("gone.bin", 1)) fail("create2");
    if (!sd_write(out, 10)) fail("write3");
    if (!sd_close()) fail("close2");
    if (!sd_delete("gone.bin")) fail("delete");
    if (sd_open("gone.bin")) fail("deleted");
    sd_rmdir("wdir");                   /* from an earlier run */
    sd_delete("wtest2.bin");
    if (!sd_rename("wtest.bin", "wtest2.bin")) fail("rename");
    if (!sd_mkdir("wdir")) fail("mkdir");
    /* names that are not 8.3: a mangled short name, the long one kept */
    sd_delete("LongerName.text");
    sd_delete("a+b.c");
    if (!sd_create("LongerName.text", 1)) fail("long");
    if (!sd_close()) fail("close3");
    if (!sd_create("a+b.c", 1)) fail("plus");
    if (!sd_close()) fail("close4");
    printf("SDWRITE OK\n");
    for (;;)
        ;
}
