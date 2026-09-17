#!/bin/sh

set -eu

repository_directory=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
formula_path=$(mktemp "${TMPDIR:-/tmp}/trn-formula-test.XXXXXX")

cleanup() {
  rm -f -- "$formula_path"
}
trap cleanup EXIT HUP INT TERM

cp "${repository_directory}/Formula/trn.rb" "$formula_path"

checksum=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
ruby "${repository_directory}/Scripts/update_release_formula.rb" 9.9.9 "$checksum" "$formula_path"

grep -Fq 'url "https://github.com/hotchpotch/trn/archive/refs/tags/v9.9.9.tar.gz"' "$formula_path"
grep -Fq "sha256 \"${checksum}\"" "$formula_path"

if grep -Fq "bottle do" "$formula_path"; then
  echo "Previous bottle block was not removed" >&2
  exit 1
fi

grep -Fq "depends_on macos: :tahoe" "$formula_path"

ruby -e 'abort "Consecutive blank lines after bottle removal" if File.read(ARGV.fetch(0)).include?("\n\n\n")' "$formula_path"

echo "Release formula update tests passed."
