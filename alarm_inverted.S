/*
 * alarm_inverted.S - Alarm System (Active Low Inputs) with PWM Volume Control
 *
 * This program implements a security alarm system on a Raspberry Pi 4.
 *
 * Hardware Connections:
 * - LED: GPIO 17 (Output)
 * - Buzzer: GPIO 22 (Output)
 * - Push Button: GPIO 23 (Input, Active Low)
 * - Sensor: GPIO 24 (Input, Active Low)
 *
 * Features:
 * - Memory Mapped GPIO for high-speed direct hardware access.
 * - Active Low Logic: Triggers when inputs go to 0V (Ground).
 * - Software PWM: Modulates the buzzer pin to lower the volume without extra resistors.
 */

.section .data
    // Path to the GPIO memory device file.
    // We open this file to get a "handle" to the physical hardware memory.
    filename: .asciz "/dev/gpiomem"
    
    // --- Timing Structures for nanosleep ---
    // struct timespec { time_t tv_sec; long tv_nsec; };
    
    // 0.5s Delay (Used for the silence interval between beeps)
    ts_500ms: .quad 0, 500000000
    
    // PWM "ON" Time (1ms)
    // Short pulse to briefly energize the buzzer
    ts_pwm_on: .quad 0, 1000000 
    
    // PWM "OFF" Time (9ms)
    // Longer pause to lower the average power (duty cycle ~10%)
    ts_pwm_off: .quad 0, 9000000

.section .text
    .global _start

    // --- Constants ---
    .equ GPIO_BASE, 0xFE200000 // Base Address for RPi 4 GPIO
    .equ PROT_RDWR, 3          // PROT_READ | PROT_WRITE
    .equ MAP_SHARED, 1         // Share changes
    
    // Register Offsets from GPIO Base
    .equ GPFSEL1, 0x04         // Function Select 1 (Pins 10-19)
    .equ GPFSEL2, 0x08         // Function Select 2 (Pins 20-29)
    .equ GPSET0,  0x1C         // Set Pin High (Output 1)
    .equ GPCLR0,  0x28         // Clear Pin Low (Output 0)
    .equ GPLEV0,  0x34         // Read Pin Level (Input 0/1)

    // System Call Numbers (AArch64)
    .equ SYS_OPENAT, 56
    .equ SYS_MMAP, 222
    .equ SYS_EXIT, 93
    .equ SYS_NANOSLEEP, 101

_start:
    // ----------------------------------------------------
    // 1. Open /dev/gpiomem to access GPIO hardware
    // ----------------------------------------------------
    mov x0, #-100       // AT_FDCWD (Use current working dir logic, ignored for abs path)
    ldr x1, =filename   // Path string "/dev/gpiomem"
    mov x2, #2          // O_RDWR (Read and Write access)
    mov x8, #SYS_OPENAT // Syscall 56
    svc #0              // Call Kernel
    mov x4, x0          // Save File Descriptor (FD) to x4

    // ----------------------------------------------------
    // 2. Map Memory (mmap)
    // Maps the physical GPIO address into our virtual memory
    // ----------------------------------------------------
    mov x0, #0          // Address = 0 (Let OS choose)
    mov x1, #4096       // Length = 4KB (One Page)
    mov x2, #PROT_RDWR  // Protection = Read/Write
    mov x3, #MAP_SHARED // Flags = Shared
    // x4 holds the FD from the open call
    mov x5, #0          // Offset = 0 (Start of file/device)
    mov x8, #SYS_MMAP   // Syscall 222
    svc #0              // Call Kernel
    mov x19, x0         // Safe Keep: x19 now holds the Base Address of GPIO

    // ----------------------------------------------------
    // 3. Configure GPIO 17 (LED) as Output
    // ----------------------------------------------------
    ldr w0, [x19, #GPFSEL1] // Read GPFSEL1 (Controls GPIO 10-19)
    mov w1, #(7 << 21)      // Create mask 111 at bits 21-23 (GPIO 17 pos)
    mvn w1, w1              // Invert to 000 at pos 21-23, 1s elsewhere
    and w0, w0, w1          // Clear current bits for GPIO 17
    orr w0, w0, #(1<<21)    // Set bit 21 (001 = Output)
    str w0, [x19, #GPFSEL1] // Write back config

    // ----------------------------------------------------
    // 4. Configure GPIO 22(Out), 23(In), 24(In)
    // ----------------------------------------------------
    ldr w0, [x19, #GPFSEL2] // Read GPFSEL2 (Controls GPIO 20-29)
    mov w1, #(0x1FF << 6)   // Create mask for 9 bits (Pins 22, 23, 24)
    mvn w1, w1              // Invert mask
    and w0, w0, w1          // Clear bits for 22, 23, 24
    orr w0, w0, #(1<<6)     // Set GPIO 22 to Output (001). 23/24 remain 000 (Input)
    str w0, [x19, #GPFSEL2] // Write back config

loop:
    // ----------------------------------------------------
    // 5. Main Polling Loop
    // Reads Inputs and checks for Active Low (0) state
    // ----------------------------------------------------
    ldr w0, [x19, #GPLEV0] // Read current state of all pins (0-31)
    
    // Check Button (GPIO 23)
    tst w0, #(1<<23)       // Bitwise AND to isolate bit 23
    b.eq trigger           // If Result is ZERO (Eq), Button is Pressed
    
    // Check Sensor (GPIO 24)
    tst w0, #(1<<24)       // Bitwise AND to isolate bit 24
    b.eq trigger           // If Result is ZERO (Eq), Sensor Triggered
    
    b loop                 // Repeat loop if nothing triggered

trigger:
    mov x20, #5          // Set Alarm Counter to 5 cycles

alarm_cycle:
    // ----------------------------------------------------
    // 6. Alarm: LED ON
    // ----------------------------------------------------
    mov w0, #(1<<17)
    str w0, [x19, #GPSET0] // GPSET0 sets bit 17 to High (LED ON)

    // ----------------------------------------------------
    // 7. Alarm: Buzzer PWM (Software Volume Control)
    // ----------------------------------------------------
    mov x21, #50           // Run 50 PWM cycles (approx 0.5 sec)

pwm_loop:
    // Buzzer ON
    mov w0, #(1<<22)
    str w0, [x19, #GPSET0] // Turn Buzzer ON
    
    // Wait Short duration (1ms)
    ldr x0, =ts_pwm_on
    bl do_sleep

    // Buzzer OFF
    mov w0, #(1<<22)
    str w0, [x19, #GPCLR0] // Turn Buzzer OFF

    // Wait Long duration (9ms)
    ldr x0, =ts_pwm_off
    bl do_sleep

    subs x21, x21, #1
    b.ne pwm_loop          // Continue PWM loop

    // ----------------------------------------------------
    // 8. Alarm: LED OFF
    // ----------------------------------------------------
    mov w0, #(1<<17)
    str w0, [x19, #GPCLR0] // GPCLR0 sets bit 17 to Low (LED OFF)

    // ----------------------------------------------------
    // 9. Alarm: Silence Delay
    // ----------------------------------------------------
    ldr x0, =ts_500ms
    bl do_sleep            // Wait 0.5s Silence

    subs x20, x20, #1      // Decrement Cycle Counter
    b.ne alarm_cycle       // Repeat 5 times
    b loop                 // Return to monitoring inputs

// --- Subroutine: do_sleep ---
// Executes nanosleep syscall
// Input: x0 = address of timespec structure
do_sleep:
    str x30, [sp, #-16]!   // Push Link Register (LR) to stack
    
    mov x1, #0             // Remainder buffer (NULL)
    mov x8, #SYS_NANOSLEEP // Syscall 101
    svc #0                 // Call Kernel
    
    ldr x30, [sp], #16     // Pop LR from stack
    ret                    // Return
