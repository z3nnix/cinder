require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class BaremetalTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  MAIN = File.join(ROOT, "main.rb")
  KERNEL = File.join(ROOT, "examples", "kernel", "main.cnd")
  LINKER = File.join(ROOT, "examples", "kernel", "linker.ld")
  BOOT = File.join(ROOT, "examples", "kernel", "boot.s")

  TOOLS = %w[llc as ld objcopy cc qemu-system-x86_64].select { |t| system("command -v #{t} >/dev/null 2>&1") }
  FULL_TOOLCHAIN = (TOOLS & %w[llc as ld objcopy]).length == 4

  def setup
    @tmp = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def test_kernel_builds_multiboot_elf
    skip "kernel toolchain not available" unless FULL_TOOLCHAIN
    out = File.join(@tmp, "kernel.bin")
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, MAIN, "build", KERNEL,
      "--target=x86_64-freestanding", "--emit=kernel", "--linker-script=#{LINKER}",
      "--boot=#{BOOT}", "-o", out)
    assert_equal 0, status.exitstatus, "#{stdout}\n#{stderr}"
    assert File.exist?(out)
    type = Open3.capture3("file", out).first
    assert_match(/ELF 32-bit/, type, "expected ELF32 image for QEMU multiboot:\n#{type}")
    entry = Open3.capture3("readelf", "-h", out).first
    assert_match(/Entry point address:\s+0x101000/, entry)
    headers = Open3.capture3("readelf", "-S", out).first
    assert_match(/\.multiboot/, headers, "expected .multiboot section in kernel")
  end

  def test_kernel_prints_to_serial_in_qemu
    skip "qemu not available" unless FULL_TOOLCHAIN && TOOLS.include?("qemu-system-x86_64")
    out = File.join(@tmp, "kernel.bin")
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, MAIN, "build", KERNEL,
      "--target=x86_64-freestanding", "--emit=kernel", "--linker-script=#{LINKER}",
      "--boot=#{BOOT}", "-o", out)
    assert_equal 0, status.exitstatus, stderr
    serial, err, st = Open3.capture3(
      "timeout", "10", "qemu-system-x86_64", "-kernel", out,
      "-serial", "stdio", "-display", "none", "-no-reboot", "-m", "32M"
    )
    assert_includes serial, "Hello world!", "expected kernel output on COM1\nserial: #{serial.inspect}\nqemu stderr: #{err} st=#{st.exitstatus}"
  end
end
