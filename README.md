# lrcmd

`lrcmd` maps left/right Command key single-taps to configured actions on macOS.

v0.0.1 also bundles `inctl`, a CLI for listing and selecting macOS input sources.

`v0.0.1` behavior has changed so that the installer only places binaries; `lrcmd setup` is now responsible for generating both config and LaunchAgent plist files.

## Installer usage

Run from the repository root:

```bash
./install.sh
```

Optional install locations:

```bash
LRCMD_INSTALL_ROOT="$HOME/Applications/lrcmd" \
./install.sh
```

For development/testing, you can also override environment paths:

```bash
LRCMD_INSTALL_ROOT="$HOME/Applications/lrcmd" \
LRCMD_CONFIG_DIR="$HOME/.config/lrcmd" \
LRCMD_LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents" \
./install.sh
```

What `install.sh` does:

- runs `swift build -c release`
- copies `Lrcmd.app`, `lrcmd`, and `inctl` into `$LRCMD_INSTALL_ROOT` and `$LRCMD_INSTALL_ROOT/bin` (default: `~/Applications/lrcmd`)
- does **not** create/update any config file
- does **not** create/update any LaunchAgent plist
- does **not** execute `launchctl`

See [config.example.json](config.example.json) for the config shape.

To complete setup after install:

```bash
~/Applications/lrcmd/bin/lrcmd setup
```

## Verification

After installation, check the bundled input-source helper:

```bash
$HOME/Applications/lrcmd/bin/inctl list
$HOME/Applications/lrcmd/bin/inctl current
```

To run `lrcmd` manually with your config:

```bash
~/Applications/lrcmd/bin/lrcmd --config "$HOME/.config/lrcmd/config.json"
```

`lrcmd setup` requests the `Accessibility` flow via the app by default.
If you need to run it manually, open the app first and then enable the toggle in System Settings:

```bash
open ~/Applications/lrcmd/Lrcmd.app
```

```text
System Settings > Privacy & Security > Accessibility
```

If you are currently using an existing `cmd-launcher` LaunchAgent, leave it in place until you intentionally migrate it.

## Setup

Run setup to generate runtime files from installed binaries:

```bash
~/Applications/lrcmd/bin/lrcmd setup
```

`lrcmd setup` now completes onboarding by default:

- shows input source candidates and lets you choose left/right source IDs
- writes/updates config and LaunchAgent plist
- opens `Lrcmd.app` (unless `--no-open`)
- waits for Accessibility permission (default 120 seconds), checking the app bundle permission state (`Lrcmd.app`)
- starts/restarts the service

`lrcmd setup` behavior flags:

- `--yes`: use recommended defaults without prompts
- `--replace`: replace existing config file
- `--dry-run`: show planned config/plist paths, open command, permission wait, and launchctl restart without writing files, opening apps, or running launchctl
- `--no-open`: skip running `open`, print manual open command instead
- `--no-start`: skip `launchctl` calls, print `lrcmd restart` guidance
- `--wait-accessibility <seconds>`: customize permission wait timeout (non-negative integer, default `120`)

You can inspect setup diagnostics at `~/.local/state/lrcmd/setup.log` (or the same path shown by `Setup log: ...` in the setup output).

`lrcmd setup` also respects:

- `LRCMD_LAUNCH_AGENT_DIR`: directory for generated LaunchAgent plist (default `~/Library/LaunchAgents`, mainly for development/testing)

Examples:

```bash
~/Applications/lrcmd/bin/lrcmd setup --dry-run --yes
~/Applications/lrcmd/bin/lrcmd setup --no-open --no-start
~/Applications/lrcmd/bin/lrcmd setup --wait-accessibility 45
```

Fallback (if automatic appearance does not happen): open Settings and add it manually with `+` by navigating to `~/Applications/lrcmd` and selecting `Lrcmd.app`.

## Uninstall

Current state:

- `lrcmd restart` and `lrcmd stop` now perform service operations directly via `launchctl`:
  - normal mode: execute service commands (`bootout`, `bootstrap`, `kickstart` as applicable)
  - dry-run mode: only print planned `launchctl` commands and do not execute them
- `lrcmd uninstall` now also runs `launchctl bootout` first in normal mode before file cleanup, and behaves as dry-run when `--dry-run` is passed.
- `lrcmd uninstall --yes` keeps config and installed binaries; it automatically removes the generated LaunchAgent plist if it exists, and continues cleanup with a warning even if `launchctl bootout` fails.

Recommended uninstall entrypoint is `lrcmd uninstall`:

```bash
lrcmd uninstall
```

This checks each generated artifact (LaunchAgent plist, config file, and install root) and asks before removing each one.
With `--dry-run`, it reports what would be removed and what would be cleaned up without deleting files or running `launchctl`.

If you pass `--yes`, `lrcmd uninstall` keeps these defaults:

- generated LaunchAgent plist: removed automatically
- generated config file: kept
- installed binaries root: kept

For manual cleanup:

```bash
rm -rf "$HOME/Applications/lrcmd"
rm -rf "$HOME/.config/lrcmd"  # only if you ran setup and want to remove generated config
```

If you created a manual LaunchAgent via setup output, stop/remove it manually.
`lrcmd uninstall` now runs `launchctl bootout` automatically in normal mode.
For dry-run usage, use `--dry-run` to confirm the commands before applying changes.

## Distribution / Release packaging

The release artifact is built as `lrcmd-v<version>-<platform>.tar.gz`, where `<platform>` is `macos-arm64` or `macos-x86_64`.

Distribution shape:

```text
lrcmd-v0.1.0-macos-arm64.tar.gz
  Lrcmd.app/
  bin/lrcmd
  bin/inctl
  README.md
  LICENSE (if present)
```

The package script creates a checksum file next to the archive:

```text
lrcmd-v0.1.0-macos-arm64.tar.gz.sha256
```

Build a release archive locally (default version `0.1.0`, output dir `dist/`):

```bash
sh scripts/package-release.sh
```

Customize version/output:

```bash
LRCMD_VERSION=0.1.0 \
LRCMD_DIST_DIR=/tmp/lrcmd-dist \
sh scripts/package-release.sh
```

The script copies the built binaries and documentation into a staging directory under
`$LRCMD_DIST_DIR/.staging/...`, creates the tarball in `$LRCMD_DIST_DIR`, and prints both paths when done.

### Hosted installer script

`scripts/install-release.sh` is a thin, inspectable installer for curl-based install.

> The hosted endpoint is not deployed yet. Upload `scripts/install-release.sh` to your intended host (for example `https://install.ultrahope.dev/lrcmd`) when ready.

Inspect before running:

```bash
curl -fsSL https://install.ultrahope.dev/lrcmd -o install-lrcmd.sh
less install-lrcmd.sh
sh install-lrcmd.sh
```

The script:

- detects macOS + architecture
- downloads `lrcmd-v${LRCMD_VERSION}-${platform}.tar.gz`
- verifies checksum when `.sha256` metadata is available
- installs `Lrcmd.app` and `bin/lrcmd`, `bin/inctl` to `~/Applications/lrcmd` by default
- prints `lrcmd setup` / `lrcmd status` guidance
- does not modify service/config files or run `launchctl`

To validate locally before deployment:

```bash
sh scripts/package-release.sh
sh scripts/verify-release.sh
```

If you want to verify a different local dist path:

```bash
LRCMD_VERSION=0.1.0 \
LRCMD_DIST_DIR=/private/tmp/lrcmd-dist \
LRCMD_VERIFY_INSTALL_ROOT=/private/tmp/lrcmd-verify-install \
sh scripts/verify-release.sh
```

`scripts/verify-release.sh` checks archive/checksum integrity and the hosted installer flow with `LRCMD_BASE_URL=file:///...` locally. It does not access the network and `status --dry-run` is used for CLI validation, so `launchctl` is not executed during verification.

Recommended distribution flow:

1. `sh scripts/package-release.sh`
2. `sh scripts/verify-release.sh`
3. upload `scripts/install-release.sh` and archive/checksum to your host

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

- `lrcmd run` (default command): start command-key mapping with config
- `lrcmd status [--dry-run]`: print service status/check summary; checks service state via `launchctl print gui/<uid>/dev.ultrahope.lrcmd` (dry-run prints commands only)
- `lrcmd doctor`: validate prerequisites without running launchctl (config/plist/json decode + binary/inctl/state/log path checks + Accessibility checks)

`lrcmd doctor` also prints the resolved paths used by the tool chain:
- config file path (`~/.config/lrcmd/config.json`)
- launch agent plist path
- inctl path
- state/log paths: `~/.local/state/lrcmd`, `~/.local/state/lrcmd/lrcmd.log`, `~/.local/state/lrcmd/lrcmd.err.log`
- `lrcmd setup [--yes] [--replace] [--dry-run] [--no-open] [--no-start] [--wait-accessibility <seconds>]`: generate config/plist and complete onboarding by default (open + Accessibility wait + launchctl restart); use `--dry-run` or `--no-start` to suppress actions
- `lrcmd restart [--dry-run]`: perform service reload (default: execute `launchctl`; `--dry-run` prints planned commands only)
- `lrcmd stop [--dry-run]`: perform service stop (default: execute `launchctl`; `--dry-run` prints planned commands only)
- `lrcmd uninstall [--yes] [--dry-run]`: perform unload + cleanup (default: execute `launchctl` and remove files as selected; `--dry-run` prints planned commands and reports `Would remove`)

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
