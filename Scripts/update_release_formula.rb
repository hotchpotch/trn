#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

version, checksum, formula_argument = ARGV

unless version&.match?(/\A\d+\.\d+\.\d+\z/) && checksum&.match?(/\A[0-9a-f]{64}\z/)
  abort "usage: update_release_formula.rb VERSION SOURCE_SHA256 [FORMULA_PATH]"
end

formula_path = Pathname(formula_argument || "Formula/trn.rb")
contents = formula_path.read

# A bottle block belongs to the previous stable release. The release workflow
# generates a fresh block after building the new bottles.
contents.sub!(/\n  bottle do\n.*?^  end\n/m, "")

archive_url = "https://github.com/hotchpotch/trn/archive/refs/tags/v#{version}.tar.gz"
url_count = contents.scan(/^  url ".*"$/).count
checksum_count = contents.scan(/^  sha256 "[0-9a-f]+"$/).count

abort "expected exactly one stable URL in #{formula_path}" unless url_count == 1
abort "expected exactly one stable checksum in #{formula_path}" unless checksum_count == 1

contents.sub!(/^  url ".*"$/, %(  url "#{archive_url}"))
contents.sub!(/^  sha256 "[0-9a-f]+"$/, %(  sha256 "#{checksum}"))
formula_path.write(contents)
