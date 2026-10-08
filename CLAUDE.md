# ps3-qdd-mac

Native macOS decryptor for Redump PS3 disc images. See `README.md` for what it does.

## Layout

- `Sources/PS3QDDCore` - the decryption logic, no UI. Kept separate so `swift test` runs
  without a window server.
- `Sources/PS3QDD` - the SwiftUI app and the `--decrypt` headless entry point.
- `Tests/PS3QDDCoreTests` - Swift Testing suites.
- `scripts/prepare-keys.sh` - builds `keys.txt` from a Redump `.dkey` archive.
- `run.sh` - builds `PS3QDD.app`, signs it and opens it.

## Toolchain constraints, both load-bearing

1. **No `@State`, no `#Preview`.** Their macro plugin (`SwiftUIMacros`) ships only with
   full Xcode, not Command Line Tools. Keep mutable state in an `ObservableObject` and
   reach it with `@StateObject` / `@ObservedObject` / `@Binding`.
2. **`swift test` needs a nudge.** Command Line Tools ship `Testing.framework` without
   wiring its macro plugin into the driver. `Package.swift` passes
   `-load-plugin-library` for it when the plugin exists at the Command Line Tools path.
   Do not "simplify" that away.

## Invariants worth not breaking

- **Never use `CCCrypt`.** It silently applies PKCS#7 padding and would corrupt every
  sector. Use `CCCryptorCreate` / `CCCryptorUpdate` / `CCCryptorRelease`, as `AES.swift`
  does.
- **Never decrypt in place.** CommonCrypto does not document it. Each sector writes to its
  own scratch slot and is copied back, which is also what makes the parallel version
  race-free.
- **Never match keys on region-stripped titles.** Region and version tags distinguish
  discs. A wrong key produces a corrupt image rather than an error, so the lookup in
  `KeyStore.aliases` deliberately keeps them.
- **Validate before queueing.** A file without a valid region map must be skipped, never
  handed to the engine, or an already-decrypted image gets mangled in place.

## Conventions

- No em dashes or en dashes in anything user-facing, in the UI or in `README.md`.
- Plain `sh` scripts with `set -u` and a `die()` helper. No Makefile.
- Commits end with `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
