# Assembler; Convert .S into .o object files
AS = aarch64-linux-gnu-as
# For debugging purpose
ASFLAGS = -g
# Linker; Convert .o files into an executable .elf binary
LD = aarch64-linux-gnu-ld # use $(LD) - pure Assembly
# Compiler
CC = aarch64-linux-gnu-gcc # use $(CC) - mixed Assembly and C
# Enable warnings at link/compile time
LDFLAGS = -Wall

TARGET = $(notdir $(shell pwd))
EXEC=$(TARGET).elf

# -- Build logic (Build .S into .o object files)
main.o: main.S
	$(AS) $(ASFLAGS) -a=main.lst -o main.o main.S

$(EXEC): main.o
# pure assembly code
	$(LD) -o $(EXEC) main.o
# mix of assembly and C++ code
#	$(CC) $(LDFLAGS) -o $(EXEC) main.o

all: $(EXEC)
.PHONY: clean
clean:
	rm -f *.o *.lst *.elf