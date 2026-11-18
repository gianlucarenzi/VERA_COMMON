#include <stdio.h>
#include <string.h>

#include "asset.h"
#include "vmem.h"

unsigned char asset_buf[ASSET_BUF_SIZE];
void (*asset_progress)(unsigned);
static FILE *asset_file;

unsigned char asset_open(const char *name)
{
    char path[256];
    asset_close();
    asset_file = fopen(name, "rb");
    if (!asset_file) {
        if (snprintf(path, sizeof path, "data/%s", name) >= (int)sizeof path)
            return 0;
        asset_file = fopen(path, "rb");
    }
    return asset_file != NULL;
}

unsigned char asset_read(void *dst, unsigned n)
{
    if (!asset_file || fread(dst, 1, n, asset_file) != n)
        return 0;
    if (asset_progress)
        asset_progress(n);
    return 1;
}

unsigned char asset_skip(unsigned long n)
{
    return asset_file && fseek(asset_file, (long)n, SEEK_CUR) == 0;
}

unsigned char asset_vram(unsigned long n)
{
    while (n) {
        unsigned size = n > sizeof asset_buf ? sizeof asset_buf : (unsigned)n;
        if (!asset_read(asset_buf, size))
            return 0;
        vram_write(asset_buf, size);
        n -= size;
    }
    return 1;
}

void asset_close(void)
{
    if (asset_file)
        fclose(asset_file);
    asset_file = NULL;
}

unsigned char asset_stream(void) { return 0; }

unsigned char asset_load(const char *name, void *dst, unsigned n)
{
    unsigned char ok = asset_open(name) && asset_read(dst, n);
    asset_close();
    return ok;
}
