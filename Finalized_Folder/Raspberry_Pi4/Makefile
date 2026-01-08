# Assembler; Convert .S into .o object files
AS = aarch64-linux-gnu-as
# For debugging purpose
ASFLAGS = -g
# Linker; Convert .o files into an executable .elf binary
LD = aarch64-linux-gnu-ld
# Compiler (not used for pure asm but defined for compat)
CC = aarch64-linux-gnu-gcc

TARGET = main
EXEC=$(TARGET).elf
OBJS = main.o

# -- Build logic
main.o: main.S
	$(AS) $(ASFLAGS) -a=main.lst -o main.o main.S

$(EXEC): $(OBJS)
	$(LD) -o $(EXEC) $(OBJS)

all: $(EXEC)
.PHONY: clean
clean:
	rm -f *.o *.lst *.elf