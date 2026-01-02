.section .rodata
msg:
	.ascii "Hello, ARM64 World. Miin Ning!\n"
len = . - msg

.section .text
	.global _start
#	.global	main // entry point of the program
_start:
#main:
	mov x0, #1 // Fit the stdout instruction at file descriptor 1 to register x0
	ldr x1, =msg // message address
	ldr x2, =len // message length
	mov x8, #64 // syscall: write
	svc #0 // Ask kernel to do "exit"
	mov x8, #93 // syscall: exit to terminate
	mov x0, #0 // the program
	svc #0
	.end
