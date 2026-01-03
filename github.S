/*
 * alarm_inverted.S - Alarm System (Active Low Inputs) with PWM Volume Control
 *
 * GPIO 17 (LED), 22 (Buzzer) -> Output
 * GPIO 23 (Button), 24 (Sensor) -> Input
 *
 * Volume Control: The buzzer is modulated (PWM) to lower the volume.
 */

.section .data
    filename: .asciz "/dev/gpiomem"

    // Delays
    // 0.5s (Main Delay)
    ts_500ms: .quad 0, 500000000

    // PWM High Time (1ms) - Reduces "ON" time for lower volume
    ts_pwm_on: .quad 0, 1000000

    // PWM Low Time (9ms) - Increases "OFF" time
    ts_pwm_off: .quad 0, 9000000

.section .text
    .global _start

	// .equ means "to replace the following name(GPIO_BASE) with the value (0xFE200000)"
	// Raspberry Pi SoC divides physical memory(RAM) INTO REGIONS:
	// Region RAM: address range from 0x00000000
	// Region Peripherals: address range from 0xFE000000
	// Region GPIO block: address range from 0xFE200000, where the GPIO hardware lives in physical memory
    .equ GPIO_BASE, 0xFE200000

    // These values come from Linux header files(Linux mmap() API), not hardware
    .equ PROT_RDWR, 3
    .equ MAP_SHARED, 1

	// GPIO registers laid out like this by the offset of 4
	// GPFSEL1 register controls pins from 0 to 9; GPFSEL2 register controls pins from 10-19.
	// The control is 3 bits per pin, where 000 is the input and 001 is the output
    .equ GPFSEL1, 0x04
    .equ GPFSEL2, 0x08

    // “To reach GPLEV0, add 0x34 bytes to GPIO_BASE.”
    .equ GPSET0,  0x1C
    .equ GPCLR0,  0x28
    .equ GPLEV0,  0x34

	// These values come from the Linux syscall table(ARM64)
    .equ SYS_OPENAT, 56
    .equ SYS_MMAP, 222
    .equ SYS_EXIT, 93
    .equ SYS_NANOSLEEP, 101

    // bit_start = (17 % 10) * 3
          = 7 * 3
          = 21
    // So bits 21, 22, 23 control GPIO17.

    // When doing
    // mov x8, #56
    // svc #0
    // it means Kernel, please run syscall #56(openat).
    // x0 to x5 are the parameters to the syscall, x8 is the syscall number which allows you to call the service you want
	// svc #0 calls the specified syscall service.
	// When the syscall returns, the result is in x0. which will be loaded into the x4, or x8 using the mov instruction

_start:
    // Open /dev/gpiomem
    mov x0, #-100  // Use current working directory with the value of -100
    ldr x1, =filename
    mov x2, #2
    mov x8, #SYS_OPENAT
    svc #0
    mov x4, x0

    // Mmap
    // mmap maps a file or device into memory, so your program can read/write it as if it were RAM.
    mov x0, #0	//start address is 0, which means let OS pick
    mov x1, #4096  // length will be 4096 bytes (storage size allocation)
    mov x2, #PROT_RDWR   // Protection(read/write)
    mov x3, #MAP_SHARED  // Changes affect device
    mov x5, #0		// 0 (start of file/device)
    mov x8, #SYS_MMAP
    svc #0
    mov x19, x0		// result of svc #0 stored in x0 temporarily

    // Configure GPIO 17 (LED) -> Output

    // x19 = base address of GPIO block (from mmap)
	#GPFSEL1 = 0x04 → offset for pins 10–19
	//ldr w0, [...] → load 32-bit GPFSEL1 register value into w0
	ldr w0, [x19, #GPFSEL1]
	# x19 is the starting address of the GPIO block and #GPFSEL1 register value points toward the pins 10-19
	# w0 points towards the current configuration of GPIO10-19.

	// Configuration for GPIO 17(LED)
	// GPIO 17 located at 17//10 = 1 or GPFSEL1 register; and at the bit of 17%10=7 * 3bits = 21th bit position.
	// feel like using 7 or 0111 to create a mask to select the register 21st to 23rd for the GPIO17.
    mov w1, #(7 << 21)
	// invert the 111 to 000 for those specific 3 bits from 21 to 23
    mvn w1, w1
    // use the 000 to erase the specific 21 to 23 bit, and the rest are remained intact due to the effect of 1, which 1 & 0 = 0 or 1 & 1 = 1
    and w0, w0, w1
    // w0 holds the state of the register GPFSEL1 which holds the state for the pin from 10 to 19.
    // then we push the 001 to the 21 bit position, which carries the configuration meaning of making this pin as the output.
    orr w0, w0, #(1<<21)
    // store the w0 or the LED configuration state to the virtual address space.
    str w0, [x19, #GPFSEL1]

    // Configure GPIO 22(Out), 23(In), 24(In)
    ldr w0, [x19, #GPFSEL2]
    mov w1, #(0x1FF << 6)
    mvn w1, w1
    and w0, w0, w1
    orr w0, w0, #(1<<6)
    str w0, [x19, #GPFSEL2]

loop:
    ldr w0, [x19, #GPLEV0]

    // Active LOW Checks
    tst w0, #(1<<23)
    b.eq trigger

    tst w0, #(1<<24)
    b.eq trigger

    b loop

trigger:
    mov x20, #5          // Alarm Cycles

alarm_cycle:
    // 1. Turn LED ON (Solid)
    mov w0, #(1<<17)
    str w0, [x19, #GPSET0]

    // 2. Buzzer PWM Loop (Duration approx 0.5s)
    // 10ms period * 50 iterations = 500ms
    mov x21, #50

pwm_loop:
    // Buzzer ON
    mov w0, #(1<<22)
    str w0, [x19, #GPSET0]

    // Wait PWM ON (1ms)
    ldr x0, =ts_pwm_on
    bl do_sleep

    // Buzzer OFF
    mov w0, #(1<<22)
    str w0, [x19, #GPCLR0]

    // Wait PWM OFF (9ms)
    ldr x0, =ts_pwm_off
    bl do_sleep

    subs x21, x21, #1
    b.ne pwm_loop

    // 3. Turn LED OFF
    mov w0, #(1<<17)
    str w0, [x19, #GPCLR0]

    // 4. Silence Delay (0.5s)
    ldr x0, =ts_500ms
    bl do_sleep

    subs x20, x20, #1
    b.ne alarm_cycle
    b loop

// Subroutine: do_sleep
// Input: x0 = address of timespec
do_sleep:
    // Create stack frame to save LR (x30)
    str x30, [sp, #-16]!

    mov x1, #0
    mov x8, #SYS_NANOSLEEP
    svc #0

    ldr x30, [sp], #16
    ret
