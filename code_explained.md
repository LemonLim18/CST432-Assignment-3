# Code Explanation: `alarm_inverted.S`

This document provides a line-by-line breakdown of the assembly code used for the Alarm System.

## Data Section
Defines constants and data structures used by the program.

```asm
.section .data
    filename: .asciz "/dev/gpiomem"
```
*   `.asciz`: Defines a null-terminated string.
*   `filename`: Stores the path to the GPIO memory device file (`/dev/gpiomem`). We need to "open" this file to access the hardware.

```asm
    // Delays
    // 0.5s (Main Delay)
    ts_500ms: .quad 0, 500000000
```
*   `ts_500ms`: Defines a `timespec` structure for the `nanosleep` system call.
    *   First `.quad 0`: Seconds (0s).
    *   Second `.quad 500000000`: Nanoseconds (500 million ns = 0.5s).

```asm
    // PWM High Time (1ms) - Reduces "ON" time for lower volume
    ts_pwm_on: .quad 0, 1000000 
    
    // PWM Low Time (9ms) - Increases "OFF" time
    ts_pwm_off: .quad 0, 9000000
```
*   `ts_pwm_on`: Defines a 1ms delay (1 million ns). Used to keep the buzzer momentarily ON.
*   `ts_pwm_off`: Defines a 9ms delay (9 million ns). Used to keep the buzzer momentarily OFF.
*   **Why?**: Toggling ON (1ms) and OFF (9ms) creates a 10% Duty Cycle PWM signal, lowering the volume.

## Text Section (Code)
Contains the executable instructions.

```asm
.section .text
    .global _start

    // Constants (Memory Addresses & Offsets)
    .equ GPIO_BASE, 0xFE200000 // Base address for Raspberry Pi 4 GPIO
    .equ PROT_RDWR, 3          // Permission: Read & Write
    .equ MAP_SHARED, 1         // Map Mode: Shared
    
    .equ GPFSEL1, 0x04         // Offset for Function Select 1 (GPIO 10-19)
    .equ GPFSEL2, 0x08         // Offset for Function Select 2 (GPIO 20-29)
    .equ GPSET0,  0x1C         // Offset to turn pins ON (Set)
    .equ GPCLR0,  0x28         // Offset to turn pins OFF (Clear)
    .equ GPLEV0,  0x34         // Offset to READ pin levels
```
*   `.equ`: Defines symbolic constants (like `#define` in C) to make code readable. Instead of writing `0x04`, we write `GPFSEL1`.

### Initialization: Opening HW Access

```asm
_start:
    // Open /dev/gpiomem
    mov x0, #-100       // Argument 1: AT_FDCWD (Ignore directory, use full path)
    ldr x1, =filename   // Argument 2: Pointer to "/dev/gpiomem" string
    mov x2, #2          // Argument 3: O_RDWR (Read/Write mode)
    mov x8, #56         // Syscall Number: 56 (openat)
    svc #0              // Execute System Call (Call Linux Kernel)
    mov x4, x0          // Save the File Descriptor (returned in x0) to register x4
```

```asm
    // Mmap GPIO memory
    mov x0, #0          // Arg 1: Address (0 = Let OS choose)
    mov x1, #4096       // Arg 2: Length (4KB, size of a memory page)
    mov x2, #3          // Arg 3: Prot (Read & Write)
    mov x3, #1          // Arg 4: Flags (Shared)
    // x4 contains fd   // Arg 5: File Descriptor (from openat)
    mov x5, #0          // Arg 6: Offset (Start at 0)
    mov x8, #222        // Syscall Number: 222 (mmap)
    svc #0              // Execute Syscall
    mov x19, x0         // Save Base Address of GPIO memory to x19
```
*   **Goal**: We now have the memory address of the GPIO controller in register `x19`. We can read/write to `[x19, #Offset]` to control pins.

### Configuration

```asm
    // Configure GPIO 17 (LED) -> Output
    ldr w0, [x19, #GPFSEL1] // Read current settings of GPIO 10-19
    mov w1, #(7 << 21)      // Create mask 111 at bits 21-23 (GPIO 17 pos)
    mvn w1, w1              // Invert mask to 000 at bits 21-23
    and w0, w0, w1          // Clear old bits for GPIO 17
    orr w0, w0, #(1<<21)    // Set bit 21 to 1 (Binary 001 = Output)
    str w0, [x19, #GPFSEL1] // Write new settings back
```

```asm
    // Configure GPIO 22(Out), 23(In), 24(In)
    ldr w0, [x19, #GPFSEL2] // Read settings for GPIO 20-29
    mov w1, #(0x1FF << 6)   // Mask for pins 22(6-8), 23(9-11), 24(12-14)
    mvn w1, w1              // Invert mask
    and w0, w0, w1          // Clear bits for all three pins
    orr w0, w0, #(1<<6)     // Set GPIO 22 to Output (001). 23/24 stay 000 (Input)
    str w0, [x19, #GPFSEL2] // Write back
```

### Main Loop

```asm
loop:
    ldr w0, [x19, #GPLEV0] // Read the Level Register (Current state of all pins)
    
    // Check Button (23) - ACTIVE LOW
    tst w0, #(1<<23)     // Test bit 23
    b.eq trigger         // If the result is ZERO (Low), jump to 'trigger'
    
    // Check Sensor (24) - ACTIVE LOW
    tst w0, #(1<<24)     // Test bit 24
    b.eq trigger         // If Low, jump to 'trigger'
    
    b loop               // Else, jump back to start of loop
```
*   `tst`: Performs a bitwise AND.
*   `b.eq`: Branch if Equal (to Zero).
*   **Logic**: If the electric signal is 3.3V (1), `tst` result is non-zero. If signal is 0V (GND), `tst` result is zero. We trigger on Zero.

### Alarm & PWM Logic

```asm
trigger:
    mov x20, #5          // Set Loop Counter to 5 (5 Blinks)

alarm_cycle:
    // 1. Turn LED ON (Solid)
    mov w0, #(1<<17)
    str w0, [x19, #GPSET0] // GPSET0 sets the bit to 1 (High)
```

```asm
    // 2. Buzzer PWM Loop
    mov x21, #50           // Inner loop counter (50 small cycles)

pwm_loop:
    // Buzzer ON
    mov w0, #(1<<22)
    str w0, [x19, #GPSET0] // Turn Buzzer ON
    
    // Wait PWM ON (1ms)
    ldr x0, =ts_pwm_on     // Load 1ms time struct
    bl do_sleep            // Sleep

    // Buzzer OFF
    mov w0, #(1<<22)
    str w0, [x19, #GPCLR0] // Turn Buzzer OFF (GPCLR0 clears bit to 0)

    // Wait PWM OFF (9ms)
    ldr x0, =ts_pwm_off    // Load 9ms time struct
    bl do_sleep            // Sleep

    subs x21, x21, #1      // Decrement inner counter
    b.ne pwm_loop          // Repeat 50 times
```
*   **Result**: The buzzer turns on/off 50 times extremely fast. It spends 90% of the time OFF and 10% ON. The human ear hears this as a quieter, constant tone.

```asm
    // 3. Turn LED OFF
    mov w0, #(1<<17)
    str w0, [x19, #GPCLR0]

    // 4. Silence Delay (0.5s)
    ldr x0, =ts_500ms
    bl do_sleep

    subs x20, x20, #1      // Decrement main counter
    b.ne alarm_cycle       // Repeat 5 times
    b loop                 // Return to monitoring inputs
```

### Helper Function

```asm
do_sleep:
    str x30, [sp, #-16]!   // Save Link Register (Return Address) to Stack
    mov x1, #0             // Null pointer for remaining time
    mov x8, #101           // Syscall: nanosleep
    svc #0                 // Call Kernel
    ldr x30, [sp], #16     // Restore Link Register from Stack
    ret                    // Return to caller
```
