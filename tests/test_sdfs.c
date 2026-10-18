/* test_sdfs.c - FAT32 SD card reading via VERA (libvera/src/fat32).
 *
 * Build: make -C VERA_COMMON test-sdfs
 *
 * Tests:
 * 1. sd_mount() on a test FAT32 image
 * 2. sd_open() and sd_read() each file
 * 3. sd_opendir() and sd_readdir() for entries
 *
 * Emulator hooks: x64sc -verasdcard <img>, atari800 -verax16-sdcard <img>,
 * x16emu -sdcard <img>
 */

#include <stdio.h>
#include <string.h>

/* Declarations we'll need from the asm fat32 code (linked in via libvera) */
extern unsigned char sd_mount(void);
extern unsigned char __fastcall__ sd_open(const char *path);
extern unsigned __fastcall__ sd_read(void *dst, unsigned n);
extern void sd_close(void);
extern unsigned char __fastcall__ sd_opendir(const char *path);
extern unsigned char sd_readdir(void);
extern unsigned char __fastcall__ sd_chdir(const char *path);
extern unsigned char sd_errno(void);

struct sd_dirent {
    char          name[256];
    unsigned char attributes;
    unsigned long start;
    unsigned long size;
    unsigned char mtime[6];
};
extern struct sd_dirent sd_dirent;

#define SD_ATTR_DIR         0x10

/* Global test results (C89: avoid stack overflow) */
static unsigned pass_count = 0;
static unsigned fail_count = 0;
static char buf[256];
static unsigned nread;
static unsigned char ok;

static void test_pass(const char *name) {
    printf("  [PASS] %s\n", name);
    ++pass_count;
}

static void test_fail(const char *name, const char *reason) {
    printf("  [FAIL] %s: %s\n", name, reason);
    ++fail_count;
}

int main(void) {
    printf("\n=== FAT32 SD Card Test ===\n");

    /* Test 1: Mount */
    printf("Test 1: sd_mount()\n");
    ok = sd_mount();
    if (ok) {
        test_pass("Mount");
    } else {
        test_fail("Mount", "sd_mount() failed");
        printf("  sd_errno = %d\n", sd_errno());
        while (1) {
        }
    }

    /* Test 2: List root directory */
    printf("\nTest 2: sd_opendir() and sd_readdir()\n");
    ok = sd_opendir("");
    if (ok) {
        test_pass("Open root directory");
        printf("  Files in root:\n");
        while (sd_readdir()) {
            printf("    %s (%lu bytes)\n", sd_dirent.name, sd_dirent.size);
        }
        sd_close();
    } else {
        test_fail("Open root directory", "error");
        printf("  sd_errno = %d\n", sd_errno());
    }

    /* Test 3: Open and read a file */
    printf("\nTest 3: sd_open() and sd_read()\n");
    ok = sd_open("/sector.bin");
    if (ok) {
        test_pass("Open /sector.bin");
        nread = sd_read(buf, sizeof(buf));
        printf("  Read %u bytes\n", nread);
        if (nread > 0) {
            test_pass("Read /sector.bin");
        } else {
            test_fail("Read /sector.bin", "read returned 0");
        }
        sd_close();
    } else {
        test_fail("Open /sector.bin", "not found");
        printf("  sd_errno = %d\n", sd_errno());
    }

    /* Test 4: Subdirectory */
    printf("\nTest 4: sd_chdir() and subdirectory\n");
    ok = sd_chdir("/subdir");
    if (ok) {
        test_pass("chdir to /subdir");
        ok = sd_opendir("");
        if (ok) {
            printf("  Files in /subdir:\n");
            while (sd_readdir()) {
                printf("    %s (%lu bytes)\n", sd_dirent.name, sd_dirent.size);
            }
            sd_close();
        }
    } else {
        printf("  (Subdirectory not found; skipping)\n");
    }

    printf("\n=== Test Summary ===\n");
    printf("PASS: %u, FAIL: %u\n", pass_count, fail_count);

    printf(fail_count == 0 ? "All tests passed!\n" : "Some tests failed.\n");
    while (1) {
        /* keep the results on screen (cc65 on the Atari clears it on exit) */
    }
    return 0;
}


