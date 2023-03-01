require "language/node"

class DashlaneCli < Formula
  desc "Command-line interface for Dashlane"
  homepage "https://dashlane.com"
  url "https://github.com/Dashlane/dashlane-cli/archive/refs/tags/v1.5.0.tar.gz"
  sha256 "d6af9b02ed60f16954b277fccb54a189ea73c048c2ea7429fc519e24f82bb203"
  license "Apache-2.0"

  livecheck do
    url :stable
    strategy :github_latest
  end

  depends_on "node@16" => :build
  depends_on "yarn" => :build

  on_macos do
    # macos requires binaries to do codesign
    depends_on xcode: :build
    # macos 12+ only
    depends_on macos: :monterey
  end

  def install
    Language::Node.setup_npm_environment
    platform = OS.linux? ? "linux" : "macos"
    system "yarn", "set", "version", "berry"
    system "yarn"
    system "yarn", "run", "build"
    system "yarn", "workspaces", "focus", "--production"
    system "yarn", "dlx", "pkg", ".",
      "-t", "node16-#{platform}-#{Hardware::CPU.arch}", "-o", "bin/dcli",
      "--no-bytecode", "--public", "--public-packages", "tslib,thirty-two"
    bin.install "bin/dcli"
  end

  def post_install
    return unless OS.linux?

    # Linuxbrew patches the ELF header when a binary is installed from bottle.
    # Patching would change the position of JavaScript code embedded in the binary.
    # Changing position results in the binary not being executable.
    # Recalculating the offset will resolve this issue.
    #
    # See github.com/vercel/pkg/issues/321
    # and github.com/NixOS/nixpkgs/pull/48193/files
    executable = bin/"dcli"
    unless (system_command executable).success?
      default_interpreter_size = 27 # /lib64/ld-linux-x86-64.so.2
      return if executable.interpreter.size <= default_interpreter_size

      offset = PatchELF::Helper::PAGE_SIZE
      binary = File.binread executable
      binary.sub!(/(?<=PAYLOAD_POSITION = ')((\d+) *)(?=')/) do
        (Regexp.last_match(2).to_i + offset).to_s.ljust(Regexp.last_match(1).size)
      end
      binary.sub!(/(?<=PRELUDE_POSITION = ')((\d+) *)(?=')/) do
        (Regexp.last_match(2).to_i + offset).to_s.ljust(Regexp.last_match(1).size)
      end
      executable.atomic_write binary
    end
  end

  test do
    # Test cli version
    assert_equal version.to_s, shell_output("#{bin}/dcli --version").chomp

    # Test cli reset storage
    expected_stdout = "? Do you really want to delete all local data from this app? (Use arrow keys)\n" \
                      "❯ Yes \n  No \e[5D\e[5C\e[2K\e[1A\e[2K\e[1A\e[2K\e[G? " \
                      "Do you really want to delete all local data from this " \
                      "app? Yes\e[64D\e[64C\nThe local Dashlane local storage has been reset"
    assert_equal expected_stdout, pipe_output("#{bin}/dcli reset", "\n", 0).chomp
  end
end
