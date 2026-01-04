/*
 * Alarm System (Active Low Inputs) with PWM Volume Control
 *
 * Input: GPIO 23 (Button), 24 (Sensor) 
 * Output: GPIO 17 (LED), 22 (Buzzer)
 *
 * Volume Control: The buzzer is modulated (PWM) to lower the volume.
 */

.section .data
    // Specify the device file name for GPIO memory access
    filename: .asciz "/dev/gpiomem"

    // Delays
    // 0.5s (Main Delay)
    ts_500ms: .quad 0, 500000000

    // PWM High Time (1ms) - This is to reduce "ON" time for lower volume
    ts_pwm_on: .quad 0, 1000000

    // PWM Low Time (9ms) - This is to increases "OFF" time
    ts_pwm_off: .quad 0, 9000000

.section .text
    .global _start

	// .equ means "to replace the following name(GPIO_BASE) with the value (0xFE200000)"
	// Raspberry Pi SoC divides physical memory(RAM) INTO REGIONS:
	// Region RAM: address range from 0x00000000
	// Region Peripherals: address range from 0xFE000000
	// Region GPIO block: address range from 0xFE200000, where the GPIO hardware lives in physical memory
    .equ GPIO_BASE, 0xFE200000

    // These values come from Linux header files(Linux mmap() API)
    .equ PROT_RDWR, 3
    .equ MAP_SHARED, 1

	// GPIO registers laid out like this by the offset of 4
	// GPFSEL1 register controls pins from 0 to 9; GPFSEL2 register controls pins from 10-19.
	// The control is 3 bits per pin, where 000 is the input and 001 is the output
    .equ GPFSEL1, 0x04
    .equ GPFSEL2, 0x08

    // “To reach GPLEV0, add 0x34 bytes to GPIO_BASE.”
    .equ GPSET0,  0x1C  // To set GPIO on
    .equ GPCLR0,  0x28  // To set GPIO off
    .equ GPLEV0,  0x34  // To read the GPIO level

	// These values come from the Linux syscall table(ARM64)
    .equ SYS_OPENAT, 56
    .equ SYS_MMAP, 222
    .equ SYS_EXIT, 93
    .equ SYS_NANOSLEEP, 101

    // bit_start = (17 % 10) * 3
    //      = 7 * 3
    //      = 21
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
    mov x0, #-100  // Directory File Descriptor: Use current working directory with the value of -100
    ldr x1, =filename   // File Pathname: Use the address of the filename string
    mov x2, #2      // Flags: Put the file-open flags into x2.
    mov x8, #SYS_OPENAT  // Syscall number for openat
    svc #0      // Make the syscall
    mov x4, x0    // Store the returned file descriptor in x4 for later use in mmap

    // Mmap
    // mmap: Kernel, map/put this file/device into my program’s memory so I can access it like RAM.
    mov x0, #0	//start address is 0, which means let OS pick a safe virtual address, specify where in our virtual memory space we want to map the device
    mov x1, #4096  // length will be 4096 bytes (storage size allocation) // GPIO registers fit inside one page
    mov x2, #PROT_RDWR   // Protection(read/write) // Allow read and write access to the mapped memory
    mov x3, #MAP_SHARED  // Changes affect device // Changes made to the mapped memory will be reflected in the underlying device
    // x4 is the file descriptor from openat syscall
    mov x5, #0		// Offset: 0 (start of file/device). This one specifies where in or which part of the file/device we want to start mapping from.
    mov x8, #SYS_MMAP
    svc #0
    mov x19, x0		// result of svc #0 stored in x0 temporarily

    // Configure GPIO 17 (LED) -> Output

    // x19 = base virtual memory address where the /dev/gpiomem is mapped into the program (from mmap)
	// #GPFSEL1 = 0x04 → offset for pins 10–19 used to locate the register for pins 10-19
	// Each GPFSEL reigster is 32 bits wide, controlling 10 GPIO pins (3 bits per pin).
    // ldr w0, [...] → load 32-bit GPFSEL1 register value into w0
    // GPFSEL XX is used to set input/output mode for GPIO pins; GPSET XX is used to set pins high or low; GPLEV 0/1 is used to read HIGH or LOW state of pins.
	ldr w0, [x19, #GPFSEL1]
	// Now that, the w0 points towards the current configuration settings of GPIO10-19.

	// Configuration for GPIO 17(LED)
	// GPIO 17 located at 17//10 = 1 or GPFSEL 1 register; and at the bit of 17%10=7 * 3bits = 21th bit position.
	// 7 or 0111 is used to create a mask to select the register 21st to 23rd for the GPIO17.
    mov w1, #(7 << 21)
	// invert the 111 to 000 for those specific 3 bits from 21 to 23
    // use the 000 to erase the specific 21 to 23 bit, and the rest are remained intact due to the effect of 1, which keeps the original value: 1 & 0 = 0 or 1 & 1 = 1
    mvn w1, w1              // Invert to 000 at pos 21-23, 1s elsewhere

    and w0, w0, w1
    // w0 holds the state of the register GPFSEL1 which holds the state for the pin from 10 to 19.
    // then we push the 001 to the 21 bit position, which carries the configuration meaning of making this pin as the output.
    // 001 means output, which we set the GPIO17 as output pin, orr is used as write the #(1<<21) value to the w0 register.
    orr w0, w0, #(1<<21)
    // store the latest w0 or the LED configuration state of GPFSEL1 to the virtual address space.
    str w0, [x19, #GPFSEL1]
    // So, basically just read the GPFSEL1 register data into w0 register, clean and set the specific bits for GPIO17 to make it output, using w1 operations that acts upon onto the w0 and update the GPFSEL1 back with the latest w0 register data it back.

    // Configure GPIO 22(Out), 23(In), 24(In)
    ldr w0, [x19, #GPFSEL2]     // w0 is the current GPFSEL2 value
    // 0x1FF = 0000 0001 1111 1111, which means clear 9 bits from bit 6 to bit 14
    // #(X << Y): X locates how many bits, Y starts from which bit position
    mov w1, #(0x1FF << 6)       // w1 is the editor: mask to clear bits 6-14
    mvn w1, w1              // invert w1 to make 1s to 0s to clear desired bits
    and w0, w0, w1      // clear bits 6-14 in w0
    orr w0, w0, #(1<<6)     // Set GPIO22 (bit 6-8) to 001 (output)
    str w0, [x19, #GPFSEL2]
    // Dont need to set GPIO23,24 as they are inputs by default (000)

loop:
    // Read GPIO Levels from the /dev/gpiomem mapped memory data into w0
    ldr w0, [x19, #GPLEV0]

    // Active LOW Checks
    // If the bit is 1(HIGH) on 23 bit position, it means the button is NOT pressed
    // #(1<<23) is the tester, w0 is the tested subject. If tested subject ANDed with the tester and result in high, GPIO level is high and result is not zero. And the zero flag is zero.
    // If the result is zero, it means the w0 and 1<<23 are not the same, which means GPIO is low or 0, and the result is zero, but the Zero flag is set to 1.
    tst w0, #(1<<23)
    // If zero flag is set, it means button is pressed (active low)
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
