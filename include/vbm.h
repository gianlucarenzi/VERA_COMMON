/* vbm.h - a VBM2 full screen bitmap (320x240, 8 bpp, layer 0) on the VERA
 * (src/common/vbm.c).  See docs/vera-asset-format.md for the file layout
 * and tools/img2vbm.py for the converter.
 */
#ifndef VBM_H
#define VBM_H

/* Layer 0 as a 320x240 8 bpp bitmap at VRAM $00000, layer 1 off, 2x scale.
 * The display state found is saved for vbm_done(). */
void vbm_init(void);

/* Restore the display state vbm_init() found and the default palette
 * entries 0-15 (the image's palette replaced all 256). */
void vbm_done(void);

/* Optional progress callback of vbm_load(): called once when the name is
 * known (loaded = 0), then after every chunk. */
typedef void (*vbm_progress_cb)(const char *name, unsigned char name_len,
                                unsigned long loaded, unsigned long total);

/* Stream a .vbm asset (asset.h name) to VRAM: pixels first, never buffered
 * in RAM, then the palette (512 bytes of heap meanwhile): the screen on
 * display keeps its colours until the image is complete.  Before or after
 * vbm_init().  progress may be 0.
 * Returns 1 on success, 0 on I/O error or bad magic. */
unsigned char __fastcall__ vbm_load(const char *name, vbm_progress_cb progress);

#endif /* VBM_H */
