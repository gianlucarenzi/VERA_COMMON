/* test_sdfs_minimal.c - Minimal FAT32 test: just check if sd_mount() works.
 *
 * This is a debug version to see if the FAT32 driver initializes at all.
 */

#include <stdio.h>

extern unsigned char sd_mount(void);
extern unsigned char sd_errno(void);

int main(void) {
    unsigned char result;
    
    printf("FAT32 Test START\n");
    fflush(stdout);
    
    printf("Calling sd_mount()...\n");
    fflush(stdout);
    
    result = sd_mount();
    
    printf("sd_mount() returned: %d\n", result);
    printf("sd_errno = %d\n", sd_errno());
    fflush(stdout);
    
    if (result) {
        printf("SUCCESS: Card mounted\n");
    } else {
        printf("FAIL: Mount failed\n");
    }
    fflush(stdout);
    
    printf("\nProgram halted. Press RUN/STOP to exit.\n");
    fflush(stdout);
    
    while (1) {
        /* Infinite loop - output stays on screen */
    }
    
    return 0;
}
