/* vtm_loader.c - read a compiled .vtm asset into a malloc'd buffer (see
 * vtm.h, docs/vtm_format.md).
 *
 * The size is never guessed: the header, title, order list, instruments
 * and pattern table come first, and the pattern table says where the last
 * pattern ends, so the buffer is sized exactly before the patterns are read.
 */

#include <stdlib.h>
#include <string.h>

#include "asset.h"
#include "vtm.h"

#define HEADER_SIZE        13u   /* magic(4) + n_channels + frames_per_row +
                                  * n_instruments + n_patterns + order_len +
                                  * loop_pos + reserved(2) + title_len */
#define INSTR_SIZE          3u
#define PATTBL_ENTRY_SIZE   3u
#define READ_CHUNK        512u   /* progress granularity */

void * __fastcall__ vtm_load(const char *name, vtm_progress_cb progress)
{
    unsigned char hdr[HEADER_SIZE];
    unsigned char *buf = 0, *grown;
    unsigned char n_channels, n_instruments, n_patterns;
    unsigned order_len, title_len, pt_off, i, prefix_size, total_size, len, want;

    if (!asset_open(name))
        return 0;
    if (!asset_read(hdr, HEADER_SIZE))
        goto fail;
    /* "VTM3" in ASCII (not '...': PETSCII on the C64) */
    if (hdr[0] != 0x56 || hdr[1] != 0x54 || hdr[2] != 0x4D || hdr[3] != 0x33)
        goto fail;

    n_channels    = hdr[4];
    n_instruments = hdr[6];
    n_patterns    = hdr[7];
    order_len     = hdr[8];
    title_len     = hdr[12];

    prefix_size = HEADER_SIZE + title_len + order_len
                + (unsigned)n_instruments * INSTR_SIZE
                + (unsigned)n_patterns * PATTBL_ENTRY_SIZE;

    buf = malloc(prefix_size);
    if (!buf)
        goto fail;
    memcpy(buf, hdr, HEADER_SIZE);
    if (!asset_read(buf + HEADER_SIZE, prefix_size - HEADER_SIZE))
        goto fail;

    /* pattern table entry: n_rows(1) + data_offset(2); the file ends where
     * the furthest pattern ends */
    pt_off = HEADER_SIZE + title_len + order_len + (unsigned)n_instruments * INSTR_SIZE;
    total_size = prefix_size;
    for (i = 0; i < n_patterns; ++i) {
        const unsigned char *e = buf + pt_off + i * PATTBL_ENTRY_SIZE;
        unsigned end = (e[1] | (e[2] << 8)) + (unsigned)e[0] * n_channels * 2;
        if (end > total_size)
            total_size = end;
    }

    grown = realloc(buf, total_size);
    if (!grown)
        goto fail;
    buf = grown;

    len = prefix_size;
    if (progress)
        progress(buf, len, total_size);         /* the title is valid now */
    while (len < total_size) {
        want = total_size - len;
        if (want > READ_CHUNK)
            want = READ_CHUNK;
        if (!asset_read(buf + len, want))
            goto fail;
        len += want;
        if (progress)
            progress(buf, len, total_size);
    }
    asset_close();
    return buf;

fail:
    free(buf);
    asset_close();
    return 0;
}
