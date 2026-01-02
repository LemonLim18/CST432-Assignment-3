/*
 * alarm.S - Alarm System for Raspberry Pi (ARM64 Assembly)
 *
 * Hardware Connections:
 * - LED: GPIO 17 (Output)
 * - Buzzer: GPIO 22 (Output)
 * - Push Button: GPIO 23 (Input, assumes pull-up/down handled externally or default)
 * - Sensor: GPIO 24 (Input)
 *
 * Logic:
 * - Monitor Button and Sensor.
 * - If detected (High), trigger alarm:
 *   - Blink LED and Beep Buzzer 5 times.
 *   - 0.5s ON, 0.5s OFF.
 */

.section .data
    // Device file for GPIO memory access
    dev_file:   .asciz  "/dev/gpiomem"
    
    // Time structure for nanosleep (0.5 seconds)
    // struct timespec { time_t tv_sec; long tv_nsec; };
    time_req:
        .quad   0           // tv_sec (0 seconds)
        .quad   500000000   // tv_nsec (500,000,000 ns = 0.5s)
    time_rem:
        .quad   0
        .quad   0

.section .text
    .global _start

    // Constants
    .equ    GPIO_BASE_RPi3, 0x3F200000
    .equ    GPIO_BASE_RPi4, 0xFE200000
    
    // Select the base address for your board. Defaulting to RPi 4 per common usage, 
    // but code uses offset mapping so we mainly need the size.
    // Actually, for /dev/gpiomem, offset 0 maps to the GPIO base, 
    // so we don't strictly need the physical address if using this driver effectively.
    // However, mmap needs proper arguments.
    
    .equ    BLOCK_SIZE,     4096
    .equ    PROT_READ,      1
    .equ    PROT_WRITE,     2
    .equ    MAP_SHARED,     1
    
    // GPIO Offsets
    .equ    GPFSEL1,        0x04    // GPIO 10-19
    .equ    GPFSEL2,        0x08    // GPIO 20-29
    .equ    GPSET0,         0x1C    // Set 0-31
    .equ    GPCLR0,         0x28    // Clear 0-31
    .equ    GPLEV0,         0x34    // Level 0-31

    // Syscall Numbers (AArch64)
    .equ    SYS_OPENAT,     56
    .equ    SYS_MMAP,       222
    .equ    SYS_EXIT,       93
    .equ    SYS_NANOSLEEP,  101

_start:
    // 1. Open /dev/gpiomem
    // int openat(int dirfd, const char *pathname, int flags, mode_t mode);
    mov     x0, #-100       // AT_FDCWD (current directory, ignored for absolute path)
    ldr     x1, =dev_file   // pathname
    mov     x2, #3          // O_RDWR | O_SYNC (typ. 0x101002 or min 3 for RDWR)
                            // Using O_RDWR (2) | O_SYNC (usually 0x101000 on ARM Linux? or 0x401000?)
                            // Simpler: O_RDWR (2) is often enough for /dev/gpiomem
    mov     x2, #2          // O_RDWR
    mov     x3, #0          // mode (not creating)
    mov     x8, #SYS_OPENAT
    svc     #0
    
    // Check for error (result < 0)
    cmp     x0, #0
    b.lt    exit_error
    
    mov     x4, x0          // Save file descriptor in x4

    // 2. Map Memory
    // void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
    mov     x0, #0          // addr = NULL (let kernel choose)
    mov     x1, #BLOCK_SIZE // length = 4KB
    mov     x2, #3          // prot = PROT_READ | PROT_WRITE (1|2)
    mov     x3, #1          // flags = MAP_SHARED
    // x4 already has fd
    mov     x5, #0          // offset = 0 (GPIO Base in /dev/gpiomem)
    mov     x8, #SYS_MMAP
    svc     #0
    
    // Check for error
    cmn     x0, #1          // compare with -1 (MAP_FAILED) aka 0xFF...FF
    b.eq    exit_error      // If equal to -1, exit
    
    mov     x19, x0         // x19 = GPIO Base Address (Base Pointer)
                            // Keep x19 safe as our global GPIO pointer

configure_gpio:
    // Configure GPIO 17 (LED) as Output
    // GPFSEL1 covers GPIO 10-19. Each pin has 3 bits.
    // GPIO 17 is bits 21-23. FSEL17 = 001 (Output).
    // Read GPFSEL1
    ldr     w0, [x19, #GPFSEL1]
    
    // Clear bits 21-23 (BIC is bit clear)
    mov     w1, #(7 << 21)  // Mask 111 at pos 21
    mvn     w1, w1          // Invert mask to 000 at pos 21, 1 elsewhere
    and     w0, w0, w1
    
    // Set bit 21 (001)
    mov     w1, #(1 << 21)
    orr     w0, w0, w1
    
    // Write back
    str     w0, [x19, #GPFSEL1]

    // Configure GPIO 22 (Buzzer) as Output
    // GPFSEL2 covers GPIO 20-29.
    // GPIO 22 is bits 6-8. FSEL22 = 001.
    ldr     w0, [x19, #GPFSEL2]
    
    // Clear bits 6-8
    mov     w1, #(7 << 6)
    mvn     w1, w1
    and     w0, w0, w1
    
    // Set bit 6
    mov     w1, #(1 << 6)
    orr     w0, w0, w1
    
    // Write back
    str     w0, [x19, #GPFSEL2] // Note: We need to write this back but wait, we also need to config 23 and 24.
                                // It's safer to read-modify-write separately or combine if we are careful.
                                // Let's write back now to be safe.

    // Configure GPIO 23 (Button) as Input
    // GPIO 23 is bits 9-11. FSEL23 = 000 (Input).
    ldr     w0, [x19, #GPFSEL2] // Read again (contains GPIO 22 config now)
    
    // Clear bits 9-11
    mov     w1, #(7 << 9)
    mvn     w1, w1
    and     w0, w0, w1
    // No need to set bits for Input (000), just clear.
    
    // Configure GPIO 24 (Sensor) as Input
    // GPIO 24 is bits 12-14. FSEL24 = 000 (Input).
    // Clear bits 12-14
    mov     w1, #(7 << 12)
    mvn     w1, w1
    and     w0, w0, w1
    
    // Write back GPFSEL2 (Configs for 22, 23, 24)
    str     w0, [x19, #GPFSEL2]

loop_main:
    // Read Input Levels (GPLEV0)
    ldr     w0, [x19, #GPLEV0]
    
    // Check GPIO 23 (Button) - Bit 23
    tst     w0, #(1 << 23)
    b.ne    trigger_alarm   // If bit 23 is High (non-zero result), trigger
    
    // Check GPIO 24 (Sensor) - Bit 24
    tst     w0, #(1 << 24)
    b.ne    trigger_alarm   // If bit 24 is High, trigger
    
    // Small delay to prevent 100% CPU usage looping (optional but good practice)
    // We'll skip for simplicity or add a tiny delay if needed.
    // For now, tight loop is fine for bare metal style assignment.
    
    b       loop_main

trigger_alarm:
    // Loop 5 times
    mov     x20, #5         // Counter = 5

loop_alarm:
    // 1. Turn ON LED (17) and Buzzer (22)
    // Write to GPSET0 (Sets bits to 1)
    mov     w0, #(1 << 17)
    orr     w0, w0, #(1 << 22)
    str     w0, [x19, #GPSET0]
    
    // 2. Delay 0.5s
    bl      delay_0_5s
    
    // 3. Turn OFF LED (17) and Buzzer (22)
    // Write to GPCLR0 (Clears bits to 0)
    mov     w0, #(1 << 17)
    orr     w0, w0, #(1 << 22)
    str     w0, [x19, #GPCLR0]
    
    // 4. Delay 0.5s
    bl      delay_0_5s
    
    // Decrement counter
    sub     x20, x20, #1
    cbnz    x20, loop_alarm // If not zero, continue loop
    
    // After 5 times, return to main loop
    b       loop_main

/* 
 * Subroutine: delay_0_5s
 * Uses nanosleep to pause for 0.5 seconds
 */
delay_0_5s:
    // Preserve link register (though we don't call anything else, good practice)
    str     x30, [sp, #-16]!
    
    ldr     x0, =time_req   // req
    ldr     x1, =time_rem   // rem
    mov     x8, #SYS_NANOSLEEP
    svc     #0
    
    ldr     x30, [sp], #16
    ret

exit_error:
    // Exit with status 1
    mov     x0, #1
    mov     x8, #SYS_EXIT
    svc     #0

exit_program:
    // Unreachable in infinite loop logic but standard exit
    mov     x0, #0
    mov     x8, #SYS_EXIT
    svc     #0
