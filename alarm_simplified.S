/*
 * alarm_simplified.S - Simplified Alarm System
 *
 * GPIO 17 (LED), 22 (Buzzer) -> Output
 * GPIO 23 (Button), 24 (Sensor) -> Input
 */

#
.section .data
    filename: .asciz "/dev/gpiomem"
    timespec: .quad 0, 500000000 // 0.5s

.section .text
    .global _start

    .equ GPIO_BASE, 0xFE200000 // RPi 4 Base
    .equ PROT_RDWR, 3
    .equ MAP_SHARED, 1
    
    .equ GPFSEL1, 0x04
    .equ GPFSEL2, 0x08
    .equ GPSET0,  0x1C
    .equ GPCLR0,  0x28
    .equ GPLEV0,  0x34

    .equ SYS_OPENAT, 56
    .equ SYS_MMAP, 222
    .equ SYS_EXIT, 93
    .equ SYS_NANOSLEEP, 101

_start:
    // Open /dev/gpiomem
    mov x0, #-100       // AT_FDCWD
    ldr x1, =filename
    mov x2, #2          // O_RDWR
    mov x8, #SYS_OPENAT
    svc #0
    mov x4, x0          // fd

    // Mmap GPIO memory
    mov x0, #0
    mov x1, #4096       // Size
    mov x2, #PROT_RDWR
    mov x3, #MAP_SHARED
    mov x5, #0
    mov x8, #SYS_MMAP
    svc #0
    mov x19, x0         // Base Address

    // Configure GPIO 17 (LED) -> Output
    // Setup GPFSEL1 (bits 21-23)
    ldr w0, [x19, #GPFSEL1]
    mov w1, #(7 << 21)
    mvn w1, w1
    and w0, w0, w1      // Clear bits
    orr w0, w0, #(1<<21)// Set Output (001)
    str w0, [x19, #GPFSEL1]

    // Configure GPIO 22(Out), 23(In), 24(In)
    // All in GPFSEL2
    // 22: bits 6-8, 23: 9-11, 24: 12-14
    ldr w0, [x19, #GPFSEL2]
    mov w1, #(0x1FF << 6) // Mask for bits 6-14 (111 111 111)
    mvn w1, w1
    and w0, w0, w1       // Clear all three
    orr w0, w0, #(1<<6)  // Set 22 to Output (001), others 000 (Input)
    str w0, [x19, #GPFSEL2]

loop:
    ldr w0, [x19, #GPLEV0]
    tst w0, #(1<<23)     // Check Button (23)
    b.ne trigger
    tst w0, #(1<<24)     // Check Sensor (24)
    b.ne trigger
    b loop

trigger:
    mov x20, #5          // Counter

blink:
    // ON (17, 22)
    mov w0, #(1<<17)
    orr w0, w0, #(1<<22)
    str w0, [x19, #GPSET0]
    bl delay

    // OFF (17, 22)
    mov w0, #(1<<17)
    orr w0, w0, #(1<<22)
    str w0, [x19, #GPCLR0]
    bl delay

    subs x20, x20, #1
    b.ne blink
    b loop

delay:
    ldr x0, =timespec
    mov x1, #0
    mov x8, #SYS_NANOSLEEP
    svc #0
    ret
