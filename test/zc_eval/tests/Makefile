CROSS ?= riscv64-linux-gnu-
AS    := $(CROSS)as
LD    := $(CROSS)ld
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
ARCH  := -march=rv32e_zicsr -mabi=ilp32e

.PHONY: smoke clean

smoke: smoke.bin

smoke.o: smoke.S
	$(AS) $(ARCH) -o $@ $<

smoke.elf: smoke.o link.ld
	$(LD) -m elf32lriscv -T link.ld -o $@ smoke.o
	$(OBJDUMP) -d $@ > smoke.txt

smoke.bin: smoke.elf
	$(OBJCOPY) -O binary $< $@

clean:
	-rm -f smoke.o smoke.elf smoke.bin smoke.txt
