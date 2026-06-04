# enka

`enka` maps left/right Command key single-taps to macOS input-source toggle keys.

It is intentionally focused on input source switching: the daemon watches Command releases and posts the JIS 英数 / かな key events directly with `CGEvent.post`.

## Install

Run from the repository root:

```bash
./install.sh
```

Optional install location:

```bash
ENKA_INSTALL_ROOT="$HOME/Applications/enka" \
./install.sh
```

What `install.sh` does:

- runs `swift build -c release`
- installs `bin/enka` and `Enka.app` under `$ENKA_INSTALL_ROOT` (default: `~/Applications/enka`)
- does not create/update config
- does not create/update a LaunchAgent plist
- does not execute `launchctl`

Complete onboarding after install:

```bash
~/Applications/enka/bin/enka setup
```

## Setup

`enka setup` installs or refreshes the LaunchAgent and supporting files for the app bundle:

- writes/updates the LaunchAgent plist
- opens `Enka.app` unless `--no-open` is passed
- waits for Accessibility permission (default 120 seconds)
- starts/restarts the LaunchAgent unless `--no-start` is passed

Flags:

- `--yes`: use recommended defaults without prompts
- `--dry-run`: show planned plist paths, app open, permission wait, and restart without writing files, opening apps, or running `launchctl`
- `--no-open`: skip opening `Enka.app`
- `--no-start`: skip `launchctl` calls
- `--wait-accessibility <seconds>`: customize permission wait timeout

Development path overrides:

- `ENKA_INSTALL_ROOT`: install root used by status/setup/plist generation
- `ENKA_CONFIG_DIR`: config directory (default: `~/.config/enka`)
- `ENKA_LAUNCH_AGENT_DIR`: LaunchAgent directory (default: `~/Library/LaunchAgents`)

## CLI

Build with SwiftPM:

```bash
swift build
```

Input source commands:

```bash
.build/debug/enka sources
.build/debug/enka current
.build/debug/enka select com.apple.keylayout.ABC
```

Daemon and lifecycle commands:

```bash
.build/debug/enka
.build/debug/enka run
.build/debug/enka run --config /path/to/config.json
.build/debug/enka setup --dry-run --yes
.build/debug/enka status --dry-run
.build/debug/enka doctor
.build/debug/enka restart --dry-run
.build/debug/enka stop --dry-run
.build/debug/enka uninstall --dry-run
```

Default paths:

- config: `~/.config/enka/config.json`
- LaunchAgent: `~/Library/LaunchAgents/dev.ultrahope.enka.plist`
- install root: `~/Applications/enka`
- state/logs: `~/.local/state/enka`

Example config:

```json
{
  "leftTap": {
    "source": "com.apple.keylayout.ABC"
  },
  "rightTap": {
    "source": "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
  }
}
```

This config is kept for CLI reference and legacy compatibility. The daemon no longer needs it for tap switching.

Behavior:

- left Command single-tap posts the JIS 英数 key event
- right Command single-tap posts the JIS かな key event
- pressing another key while Command is held cancels the action
- pressing both Command keys together cancels both actions

Accessibility permission is required before the daemon can observe Command key events. If automatic setup does not show the app in System Settings, open it manually:

```bash
open ~/Applications/enka/Enka.app
```

Then enable it in:

```text
System Settings > Privacy & Security > Accessibility
```

## Uninstall

Recommended:

```bash
enka uninstall
```

With `--dry-run`, `enka` reports what would be removed without deleting files or running `launchctl`.

Manual cleanup:

```bash
rm -rf "$HOME/Applications/enka"
rm -rf "$HOME/.config/enka"
rm -rf "$HOME/.local/state/enka"
```

## Release Packaging

Build a release archive locally:

```bash
sh scripts/package-release.sh
```

Distribution shape:

```text
enka-v0.1.0-macos-arm64.tar.gz
  Enka.app/
  bin/enka
  README.md
  LICENSE (if present)
```

Customize version/output:

```bash
ENKA_VERSION=0.1.0 \
ENKA_DIST_DIR=/tmp/enka-dist \
sh scripts/package-release.sh
```

Verify local release artifacts:

```bash
sh scripts/package-release.sh
sh scripts/verify-release.sh
```

Hosted installer defaults to `~/Applications/enka` and installs only `bin/enka` plus `Enka.app`.
