module Cinder
  module Targets
    X86_64_DATALAYOUT = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"

    TARGETS = {
      "x86_64" => {
        triple: "x86_64-pc-linux-gnu",
        datalayout: X86_64_DATALAYOUT,
        ptr_bits: 64,
        usize: "i64",
        usize_rank: 5,
        ld_emulation: "elf_x86_64",
        freestanding: false,
      },
      "x86_64-freestanding" => {
        triple: "x86_64-unknown-none-elf",
        datalayout: X86_64_DATALAYOUT,
        ptr_bits: 64,
        usize: "i64",
        usize_rank: 5,
        ld_emulation: "elf_x86_64",
        freestanding: true,
      },
    }.freeze

    def self.[](name)
      TARGETS[name] || TARGETS["x86_64"].merge(name: name)
    end

    def self.known?(name)
      TARGETS.key?(name)
    end
  end
end
