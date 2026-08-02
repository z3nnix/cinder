ROOT      := ../..
CINDER    := ruby $(ROOT)/main.rb
TARGET    := x86_64-freestanding
EMIT      := kernel
LINKER    := linker.ld
BOOT      := boot.s
KERNEL    := kernel.bin

QEMU      := qemu-system-x86_64
QEMUFLAGS := -serial stdio -display none -no-reboot -m 32M

.PHONY: all run run-vga clean info

all: $(KERNEL)

$(KERNEL): main.cnd $(BOOT) $(LINKER)
	$(CINDER) build main.cnd \
		--target=$(TARGET) \
		--emit=$(EMIT) \
		--linker-script=$(LINKER) \
		--boot=$(BOOT) \
		-o $(KERNEL)

run: $(KERNEL)
	$(QEMU) -kernel $(KERNEL) $(QEMUFLAGS)

# Text-mode VGA: -nographic drops serial to stdio and prints the VGA text screen.
run-vga: $(KERNEL)
	$(QEMU) -kernel $(KERNEL) -nographic -no-reboot -m 32M

info: $(KERNEL)
	file $(KERNEL)
	readelf -h $(KERNEL) | grep -E 'Type|Entry'
	readelf -S $(KERNEL)

clean:
	rm -f $(KERNEL)
