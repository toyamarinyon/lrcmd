# lrcmd v0.0.1 Checkpoints

## Goal

Build the first distributable shape of `lrcmd` in this repository.

`lrcmd` is a small macOS utility that maps left/right Command single-taps to configured commands. It bundles `inctl`, a small CLI for listing and selecting macOS input sources. v0.0.1 prepares the code and installer layout, but does not register or modify the user's existing LaunchAgent because `cmd-launcher` is already in use.

## Checkpoints

- [x] 1. Repository baseline
  - Create a clean SwiftPM package in `~/Documents/lrcmd`.
  - Add `.gitignore`, README skeleton, and this checkpoint plan.
  - Commit as a baseline.

- [x] 2. Rename and port CLIs
  - Port the current `cmd-launcher` behavior as executable `lrcmd`.
  - Port the current `input-source` behavior as executable `inctl`.
  - Update default config path to `~/.config/lrcmd/config.json`.
  - Keep LaunchAgent registration out of runtime behavior.
  - Verify `swift build`.

- [ ] 3. Add setup-oriented installer assets
  - Add `install.sh` that behaves like `lrcmd setup`: build/copy release binaries into a local install root and create config if missing.
  - Do not call `launchctl bootstrap`, `kickstart`, `enable`, or `bootout` in v0.0.1.
  - Add `config.example.json` using bundled `inctl`.
  - Add clear next-step output for Accessibility permission and manual LaunchAgent migration.

- [ ] 4. Documentation and verification
  - Document install script usage, manual verification, uninstall notes, and the current no-LaunchAgent-registration boundary.
  - Verify `swift build -c release`.
  - Verify `inctl list`, `inctl current`, and basic `lrcmd` error behavior.
  - Commit v0.0.1-ready state.

## Non-goals for v0.0.1

- No automatic LaunchAgent registration.
- No `.app`, `.pkg`, code signing, or notarization.
- No domain-hosted installer script yet.
- No Homebrew or npm distribution.
