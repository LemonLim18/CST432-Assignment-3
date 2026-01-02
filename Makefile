# Assembler; Convert .S into .o object files
AS = aarch64-linux-gnu-as
# For debugging purpose
ASFLAGS = -g
# Linker; Convert .o files into an executable .elf binary
LD = aarch64-linux-gnu-ld
# Compiler (not used for pure asm but defined for compat)
CC = aarch64-linux-gnu-gcc

TARGET = alarm
EXEC=$(TARGET).elf
OBJS = alarm.o

# -- Build logic

# Standard rule found in reference: main.o: main.S
alarm.o: alarm.S
	$(AS) $(ASFLAGS) -a=alarm.lst -o alarm.o alarm.S

$(EXEC): $(OBJS)
	$(LD) -o $(EXEC) $(OBJS)

all: $(EXEC)

.PHONY: clean
clean:
	rm -f *.o *.lst *.elf