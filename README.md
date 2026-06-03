# lrcmd

`lrcmd` maps left/right Command key single-taps to configured actions on macOS.

v0.0.1 also bundles `inctl`, a CLI for listing and selecting macOS input sources.

This repository is being prepared for installer-based distribution. v0.0.1 does not automatically register LaunchAgent services.

## Installer usage

Run from the repository root:

```bash
./install.sh
```

Optional install locations:

```bash
LRCMD_INSTALL_ROOT="$HOME/Applications/lrcmd" \
LRCMD_CONFIG_DIR="$HOME/.config/lrcmd" \
./install.sh
```

What `install.sh` does:

- runs `swift build -c release`
- copies `lrcmd` and `inctl` into `$LRCMD_INSTALL_ROOT/bin` (default: `~/Applications/lrcmd/bin`)
- creates `$LRCMD_CONFIG_DIR/config.json` if it does not already exist (default: `~/.config/lrcmd/config.json`)
- leaves an existing config untouched

The generated config points to the installed `inctl` binary and sets:

- left Command to `ABC`
- right Command to `Hiragana`

See [config.example.json](config.example.json) for the config shape.

v0.0.1 does not generate a LaunchAgent plist and does not run `launchctl`. Any background launch setup is still manual.

## CLI usage

Build with SwiftPM:

```bash
swift build
```

`lrcmd` usage:

```bash
.build/debug/lrcmd
.build/debug/lrcmd --config /path/to/config.json
```

- default config path: `~/.config/lrcmd/config.json`
- invalid usage exits with code `64`
- Accessibility permission is required before launch

Example config:

```json
{
  "leftCommand": {
    "command": "/absolute/path/to/.build/debug/inctl",
    "arguments": ["select", "com.apple.keylayout.ABC"]
  },
  "rightCommand": {
    "command": "/absolute/path/to/.build/debug/inctl",
    "arguments": ["select", "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"]
  }
}
```

Behavior:

- left Command single-tap runs `leftCommand`
- right Command single-tap runs `rightCommand`
- pressing another key while Command is held cancels the action
- pressing both Command keys together cancels both actions

`inctl` usage:

```bash
.build/debug/inctl list
.build/debug/inctl current
.build/debug/inctl select com.apple.keylayout.US
```

- `list`: print available input source IDs and localized names
- `current`: print the current input source ID and localized name
- `select <inputSourceID>`: switch to the specified input source
- invalid usage exits with code `64`
- unknown input source ID exits with code `1`
