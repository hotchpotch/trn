# `trn` - Fast translation CLI using Apple's Translation framework

A small Swift command-line translator for macOS 26.4 Tahoe or later.

- 🍎 Uses the macOS built-in Translation framework, optimized for Apple Silicon.
- ⚡ Fast in everyday use because translation runs through Apple's on-device system translation service.
- 💸 Free to use: no paid translation API key or subscription is required.
- 🔒 Fully local: your source text does not need to be sent to a remote translation API.
- 🛠️ Secure and convenient for private notes, documents, shell pipelines, and developer workflows.
- 🎛️ Select high-quality Apple Intelligence translation or low-latency traditional translation with `--quality`.
- 📊 The [quality report](translation-quality-check.md) found `low` sufficient for the tested English/Japanese cases, while running about 10x faster than `high`.

## Quick Start

### Translate

Translations are fast enough for interactive shell use. For example, this run completed in about 0.08 seconds on a MacBook Pro with an M4 chip:

```sh
time trn --to ja 'Hello world!'
#=> こんにちは、世界！
#=> trn --to ja 'Hello world!'  0.02s user 0.02s system 46% cpu 0.083 total
```

Timing varies by Mac, language pair, and whether the translation model is already loaded.

Use it in a pipeline:

```sh
echo "Hello world!" | trn --to ja
#=> こんにちは、世界！
```

### Install

#### Homebrew (recommended)

Homebrew installs a prebuilt bottle, so no local Swift build is required:

```sh
brew tap hotchpotch/trn https://github.com/hotchpotch/trn
brew install hotchpotch/trn/trn
```

#### Installer

Alternatively, install the latest GitHub Release into `/usr/local/bin`:

```sh
curl -fsSL https://raw.githubusercontent.com/hotchpotch/trn/main/install.sh | sh
```

For a sudo-free installation into `~/.local/bin`:

```sh
curl -fsSL https://raw.githubusercontent.com/hotchpotch/trn/main/install.sh | sh -s -- --user
```

Pass a directory after `--user` to choose another user-writable location:

```sh
curl -fsSL https://raw.githubusercontent.com/hotchpotch/trn/main/install.sh | sh -s -- --user "$HOME/.bin"
```

The installer verifies the SHA-256 checksum, creates the destination directory, and prints a PATH instruction when needed.

## Manual Installation

Download the latest prebuilt archive from [GitHub Releases](https://github.com/hotchpotch/trn/releases):

- [Apple Silicon (`arm64`)](https://github.com/hotchpotch/trn/releases/latest/download/trn-arm64-apple-darwin.tar.gz)

Or download the correct archive from the command line and install it manually:

```sh
trn_arch=$(uname -m)
curl -fL "https://github.com/hotchpotch/trn/releases/latest/download/trn-${trn_arch}-apple-darwin.tar.gz" | tar -xz
sudo install -m 755 trn /usr/local/bin/trn
```

## Requirements

- macOS 26.4 Tahoe or later
- Installed Apple translation language packages for the language pairs you want to use

If a required language package is supported but not installed, `trn` reports that the package needs to be installed from System Settings.

## Usage

`trn` behaves like a Unix-style filter: it accepts text from standard input, buffers it into translation chunks, translates the chunks concurrently, and writes the translated text to standard output in the original order. You can also pass one positional text argument for quick one-off translations.

Quality-sensitive evaluation:

```sh
trn --from en --to ja --quality high "Hello world!"
trn --from en --to ja --quality low "Hello world!"
```

`low` is the default and is usually the practical choice for English/Japanese translation. Use `--quality high` when you want to compare against Apple's high-fidelity translation model or inspect whether a specific sentence benefits from it.

Basic translation:

```sh
trn --to ja "Hello world!"
#=> こんにちは、世界！
```

Use a language name instead of a language code:

```sh
trn --to japanese "Hello world!"
#=> こんにちは、世界！
```

Read source text from standard input:

```sh
echo "Hello world!" | trn --to ja
#=> こんにちは、世界！
```

Specify the source language explicitly:

```sh
trn --from en --to ja "Hello world!"
#=> こんにちは、世界！
```

Choose translation quality:

```sh
trn --to ja --quality high "Hello world!"
trn --to ja -q low "Hello world!"
```

`low` is the default and uses Apple's lower-latency traditional translation models. `high` uses Apple Intelligence high-fidelity translation when available.

If `--from` is omitted, `trn` auto-detects the source language from the input text before creating the translation request:

```sh
trn --to en "こんにちは、世界！"
#=> Hello, world!
```

## List Languages

List supported languages as JSON (no text input or language downloads required):

```sh
trn --list-languages | jq .
trn --list-languages --quality high | jq '.languages[] | {code, name}'
```

Add `--to` to check readiness for translation from each listed language to that target:

```sh
trn --list-languages --to en --quality low | jq .
trn --list-languages --to en --quality high \
  | jq '.languages[] | select(.status == "installed")'
```

The JSON object contains `quality` and `languages`; `target` is included only with `--to`.
Each language has `code` and an English `name`, sorted by code. With `--to`, each entry also has a `status`:

| Status | Meaning |
| --- | --- |
| `installed` | The source → target pair is ready with the requested quality strategy. |
| `supported` | The pair is supported, but required language assets are not installed. |
| `unsupported` | The framework does not support this pair, including unsupported script pairings. |
| `same_language` | Source and target have the same language and effective script; trn returns the original text without translation. |
| `unknown` | The framework returned an unrecognized status. |

Status describes a **language pair**, not whether a single language pack is downloaded.
`same_language` describes trn's passthrough behavior; it does not indicate that any
assets are installed or that the framework supports the pair.
The list contains the languages reported by the device for the selected strategy,
not every accepted input code or alias. For example, `ar` and `arabic` are accepted
although the list reports `ar-AE`.
Lists and readiness depend on the device and `--quality` (`low` by default).
`high` prefers Apple Intelligence models and can fall back to traditional models;
`installed` does not identify which model will be used.
Language codes preserve region and script distinctions, such as `en-GB` and `zh-TW`.
Accepted code syntax is `language[-Script][-REGION]`: a two- or three-letter language,
an optional four-letter script, and an optional two-letter or three-digit region.
Underscores and case differences are normalized. Malformed codes are errors; well-formed
codes for unsupported languages produce `unsupported` pair statuses.
The undetermined language code `und` (including region variants) is rejected.
Region variants with the same effective script (such as `en-GB` → `en` or `ar-AE` → `ar`)
are treated as `same_language` in both listing and translation. Different scripts
(such as `zh` → `zh-TW`) still go through the framework's availability check.
Use `trn --list-languages --help` to display help.
Listing ignores stdin and rejects translation-only options such as `--from` and `--stream`.

Compatibility note: translation now preserves non-default regions too. Previously,
`--to en-GB` was reduced to `en`; it now requests the British English variant and may
require different assets. Install the requested variant, or explicitly choose `--to en`
if the base language is acceptable. Default-region forms such as `en-US` and `ja-JP`
continue to normalize to `en` and `ja`.

## Buffered Translation

Buffered paragraph translation is the default. `trn` splits input on newlines and keeps each chunk at or below 512 characters when possible. The `-s` / `--stream` flag is still accepted for clarity and backward compatibility, but it is not required.

```sh
cat notes.txt | trn --to ja
```

The default maximum concurrency is `4`. You can change it with `-j` or `--concurrency`:

```sh
cat notes.txt | trn --to ja --concurrency 2
cat notes.txt | trn --to ja -j 2
```

Buffered chunks are translated concurrently, but output order is preserved.

When `--from` is omitted, `trn` detects the source language once from the full input and reuses that language for every chunk.

Change the translation buffer size with `-b` or `--buffer-size`. The value is a character count. Smaller buffers start work sooner and can reduce per-request size; larger buffers preserve more context per translation request.

```sh
cat notes.txt | trn --to ja --buffer-size 256
cat notes.txt | trn --to ja -b 1024
```

Example:

```sh
printf 'Hello world!\nGood morning.\n' | trn --to ja --concurrency 2
#=> こんにちは、世界！
#=>
#=> おはようございます。
```

## Local Build

Building from source requires Command Line Tools with the macOS 26.4 SDK or later.

Build the debug executable:

```sh
swift build
```

Run the executable from the build directory:

```sh
.build/debug/trn --to ja "Hello world!"
#=> こんにちは、世界！
```

Build a release executable:

```sh
swift build -c release
```

Copy the release binary into a directory on your `PATH`.

For a user-local bin directory:

```sh
mkdir -p ~/.bin
cp .build/release/trn ~/.bin/
```

For a system-wide install location:

```sh
sudo cp .build/release/trn /usr/local/bin/
```

After copying, confirm that the command is available:

```sh
trn --to ja "Hello world!"
#=> こんにちは、世界！
```

## Development

Running the test suite requires Xcode with the macOS 26.4 SDK or later.

Run the test suite:

```sh
swift test
```

The tests use Swift Testing, so run them with Xcode selected rather than Command Line Tools only.

Build the package:

```sh
swift build
```

The core behavior lives in `Sources/TranslateCore/` so it can be tested without launching a subprocess. The executable entry point is `Sources/trn/main.swift`.

## License

MIT License. See [LICENSE](LICENSE).

## Author

Yuichi Tateno ([@hotchpotch](https://github.com/hotchpotch))
