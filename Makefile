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

TARGET_SIMP = alarm_simplified
EXEC_SIMP = $(TARGET_SIMP).elf
OBJS_SIMP = alarm_simplified.o

# -- Build logic

# Standard rule found in reference: main.o: main.S
alarm.o: alarm.S
	$(AS) $(ASFLAGS) -a=alarm.lst -o alarm.o alarm.S

$(EXEC): $(OBJS)
	$(LD) -o $(EXEC) $(OBJS)

alarm_simplified.o: alarm_simplified.S
	$(AS) $(ASFLAGS) -a=alarm_simplified.lst -o alarm_simplified.o alarm_simplified.S

alarm_inverted.o: alarm_inverted.S
	$(AS) $(ASFLAGS) -a=alarm_inverted.lst -o alarm_inverted.o alarm_inverted.S

$(EXEC_SIMP): $(OBJS_SIMP)
	$(LD) -o $(EXEC_SIMP) $(OBJS_SIMP)

target_inverted = alarm_inverted.elf
objs_inverted = alarm_inverted.o

$(target_inverted): $(objs_inverted)
	$(LD) -o $(target_inverted) $(objs_inverted)

all: $(EXEC) $(EXEC_SIMP) $(target_inverted)

.PHONY: clean
clean:
	rm -f *.o *.lst *.elf