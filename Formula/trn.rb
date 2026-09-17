class Trn < Formula
  desc "Swift command-line translator for macOS using Apple's Translation framework"
  homepage "https://github.com/hotchpotch/trn"
  url "https://github.com/hotchpotch/trn/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "4b18b86a76a067e1fbb227d38a51d440c52a35315a3e1a79bb5ff58e4cbf0ac1"
  license "MIT"

  bottle do
    root_url "https://github.com/hotchpotch/trn/releases/download/v0.2.1"
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "30335b4e3f434bb7a87f3b0f7e1dbf70bbc1c76cc67a6e04c9e7d044c93c9ece"
    sha256 cellar: :any_skip_relocation, tahoe:       "b9d36a7a6c5764f9b44f3d0be5b45bff8083298c0d5afb456e3a2df7803009fc"
  end

  depends_on macos: :tahoe

  def install
    if OS.mac?
      macos_version = Version.new(Utils.safe_popen_read("/usr/bin/sw_vers", "-productVersion").strip)
      odie "trn requires macOS 26.4 or later." if macos_version < Version.new("26.4")
    end

    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/trn"
  end

  test do
    assert_equal "hello", shell_output("#{bin}/trn --from en --to en hello").strip
  end
end
