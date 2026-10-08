# PS3 Quick Disc Decryptor - macOS

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)]()
[![Swift](https://img.shields.io/badge/swift-6.0-orange)]()
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

A native macOS app that decrypts Redump PS3 disc images so [RPCS3](https://rpcs3.net/)
can load them, in the spirit of
[PS3-Quick-Disc-Decryptor](https://github.com/ElektroStudios/PS3-Quick-Disc-Decryptor)
for Windows.

**License:** GPL-3.0. The decryption is implemented from scratch in Swift against
CommonCrypto, cross-checked against
[al3xtjames/ps3dec](https://github.com/al3xtjames/ps3dec) and the
[Redrrx/ps3dec](https://github.com/Redrrx/ps3dec) rewrite. All credit to those authors.

## Features

- **No dependencies at all.** CommonCrypto ships with macOS, so there is no `ps3dec`
  binary, no Rust, no CMake and no Homebrew to install. Build it with
  `./run.sh` and a `PS3QDD.app` appears.
- **About 1 GiB/s.** Sectors are independent, so each 64 MiB block is decrypted across
  all cores. A 9 GB disc takes roughly 8 seconds on an M-series Mac.
- **Accept either key format.** Point it at a folder of Redump `.dkey` files or at a
  single combined `Title<TAB>key` file. It works out which one you gave it.
- **Batch with live progress.** Pick a folder of ISOs and every file gets a row with a
  progress bar, percentage, throughput and ETA, plus its own Stop button.
- **It will not corrupt your files.** Every image's region map is validated before it is
  queued, so an already-decrypted ISO or a JB folder is reported as skipped instead of
  being silently mangled. Output goes to a `.part` file and is renamed only on success,
  free space is checked first, and the source is deleted only after a clean finish.
- **Keys never leave your Mac and are never bundled.** The app reads them from wherever
  you point it. Nothing is written into the repo or the app bundle.

## Requirements

macOS 14 or later, and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode
is **not** required.

## Build and run

```sh
./run.sh
```

That builds a release binary, assembles `PS3QDD.app`, ad-hoc signs it and opens it. On
Apple Silicon a bundle whose signature does not match its contents is killed at launch,
which is why the signing step is in the script.

Then:

1. Choose the folder holding your encrypted `.iso` files.
2. Choose your keys (see below).
3. Choose an output folder, or leave it to write next to the sources.
4. Press **Start Decryption**.

## Keys

The app understands two layouts:

- **A folder of `.dkey` files**, one per title, as distributed by Redump.
- **A single combined file** of `Title<TAB>32-character-key` lines. Lines starting with
  `#` are ignored, and the key may also be separated by a space as long as it is last.

The app looks for `~/Library/Application Support/PS3QDD/keys.txt` at launch, and
`scripts/prepare-keys.sh` builds that file from a Redump `.dkey` archive:

```sh
sh scripts/prepare-keys.sh [archive.7z] [destination]
```

`bsdtar` ships with macOS and reads 7z natively, so no extra tools are needed. Titles are
matched against the ISO filename, then its stem, then a punctuation-insensitive form that
**keeps** region and version tags. That last part matters: ignoring tags would hand the USA
release the Europe key, which fails by producing a corrupt image rather than an error.

## Headless use

The same binary decrypts from the command line, which is also how the end-to-end check
below runs:

```sh
./run.sh --decrypt <input.iso> <keys-file-or-dkey-folder> <output-dir>
```

## How it works

A PS3 disc image is 2048-byte sectors. Sector 0 holds a region map, and the regions
alternate plain, encrypted, plain, encrypted, starting with plain. Each sector in an
encrypted region is independently AES-128-CBC decrypted with no padding, using the disc
key and an IV of twelve zero bytes followed by the big-endian sector index. Because the IV
depends only on the absolute sector index, no sector depends on any other, so the work
parallelizes across cores with no chaining.

`Sources/PS3QDDCore` holds that logic with no UI, so the tests run without a window server.
`Sources/PS3QDD` is the SwiftUI app.

## Verification

```sh
swift test
```

31 tests covering the NIST SP 800-38A CBC vector, region-map arithmetic against the real
disc layout and malformed maps, `.dkey` CRLF trimming, key lookup, and a synthesized
round-trip that encrypts an image and decrypts it back byte for byte.

Verified end to end against
`LittleBigPlanet (USA) (En,Ja,Fr,De,Es,It,Nl,Pt,Sv,No,Da,Fi,Zh,Ko) (v02.00).iso`:

| Check | Result |
|---|---|
| Output size | 9,011,200,000 bytes, matching the input exactly |
| Plain regions | byte-identical to the input, so they were left alone |
| `EBOOT.BIN` at sector 95,030 | starts `SCE\0`, inside the encrypted region |
| `PARAM.SFO` | names the title |
| Other containers | `FSB4`, `BIKi` and `PNG` all intact |
| Mounts as ISO9660 | 235 files, `PS3_GAME/USRDIR/EBOOT.BIN` present |
| Output MD5 | `e00a1158c138f6e2be2a4a5ee73580a1`, identical to an independent prototype |
| Throughput | ~8.0 s for 9 GB, about 1081 MiB/s |

`EBOOT.BIN` is the decisive one. It lives inside the encrypted region, so its `SCE\0`
header only appears if the key and the IV scheme are both right.

## Notes and limits

- **Decrypt only.** The Windows tool can re-encrypt; this does not.
- **One image at a time.** Jobs run sequentially, because a single disc already saturates
  the disk.
- **No resume.** An interrupted run starts that file over rather than resuming from a
  partial output.
- **Not signed for distribution.** A locally built bundle is not quarantined and runs
  fine, but shipping one would need a Developer ID.
- **No key material is included.** Bring your own.

## Toolchain note

Under Command Line Tools alone, `Testing.framework` ships without the driver being told to
load its macro plugin, so `swift test` fails with "plugin for module 'TestingMacros' not
found". `Package.swift` points the driver at the plugin when it finds it at the Command
Line Tools path, and stays out of the way under a full Xcode install. Separately, SwiftUI's
`@State` and `#Preview` macros are **not** available at all without full Xcode, which is
why the app keeps its mutable state in an `ObservableObject` view model reached through
`@StateObject` and `@ObservedObject`.
