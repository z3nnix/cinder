CINDER    := cinder
TARGET    := x86_64-freestanding
EMIT      := kernel
LINKER    := linker.ld
BOOT      := boot.s
KERNEL    := kernel.bin

QEMU      := qemu-system-x86_64
QEMUFLAGS := -serial stdio -no-reboot -no-reboot -m 32M

.PHONY: all run run-vga clean info

all: $(KERNEL)

$(KERNEL): src/main.cnd $(BOOT) $(LINKER)
	$(CINDER) build src/main.cnd \
		--target=$(TARGET) \
		--emit=$(EMIT) \
		--linker-script=$(LINKER) \
		--boot=$(BOOT) \
		-o $(KERNEL)

run: $(KERNEL)
	$(QEMU) -kernel $(KERNEL) $(QEMUFLAGS)

clean:
	rm -f $(KERNEL)