# enka

`enka` maps left/right Command key single-taps to macOS input-source toggle keys.

It is intentionally focused on input source switching: the daemon watches Command releases and posts the JIS 英数 / かな key events directly with `CGEvent.post`.

## Install

Hosted installer (recommended):

```bash
curl -fsSL https://enka.ultrahope.dev/install | sh
```

This downloads the release archive and configures Enka automatically:
- downloads the hosted release and checksum
- installs to `~/Applications/enka` by default
- installs `bin/enka` and `Enka.app`
- opens `Enka.app` and waits for Accessibility permission
- writes the LaunchAgent plist
- starts/restarts the LaunchAgent after permission is granted
- if permission is not granted before timeout, the installer exits with retry guidance

If installation fails while waiting for Accessibility permission, rerun the installer:

```bash
curl -fsSL https://enka.ultrahope.dev/install | sh
```

If the files are already installed, you can rerun macOS registration directly:

```bash
~/Applications/enka/bin/enka install
```

Accessibility permission cannot be granted automatically by the installer.
The installer opens `Enka.app` and waits for you to enable it in System Settings; if permission is not granted before timeout, it exits with retry guidance.

Environment overrides:

```bash
ENKA_VERSION=0.1.2 \
ENKA_INSTALL_ROOT="$HOME/Applications/enka" \
ENKA_INSTALL_ORIGIN="https://enka.ultrahope.dev" \
ENKA_RELEASE_BASE_URL="https://github.com/toyamarinyon/enka/releases/download" \
ENKA_BASE_URL="https://example.com/custom/path" \
ENKA_SKIP_SETUP=1 \
ENKA_SETUP_WAIT_ACCESSIBILITY_SECONDS=30 \
sh -c "$(curl -fsSL https://enka.ultrahope.dev/install)"
```

Notes:

- `ENKA_SKIP_SETUP=1` skips automatic configuration after copying files.
- `ENKA_SETUP_WAIT_ACCESSIBILITY_SECONDS` enables a custom timeout for the permission wait.
- `ENKA_INSTALL_ORIGIN` sets the product install site used to resolve `latest.json`.
- `ENKA_RELEASE_BASE_URL` sets the release download base; by default, artifacts are downloaded from GitHub Releases.
- `ENKA_BASE_URL` sets a fully-resolved base path and bypasses the default release download convention.

Development path overrides:

- `ENKA_INSTALL_ROOT`: install root used by installation, status, and plist generation
- `ENKA_LAUNCH_AGENT_DIR`: LaunchAgent directory (default: `~/Library/LaunchAgents`)
- `ENKA_STATE_DIR`: state/log directory (default: `~/.local/state/enka`)

## CLI

Build with SwiftPM:

```bash
swift build
swift build -c release
```

Daemon and lifecycle commands:

```bash
.build/debug/enka
.build/debug/enka run
.build/debug/enka install
.build/debug/enka status
.build/debug/enka restart
.build/debug/enka stop
.build/debug/enka uninstall
```

Default paths:

- LaunchAgent: `~/Library/LaunchAgents/dev.ultrahope.enka.plist`
- install root: `~/Applications/enka`
- state/logs: `~/.local/state/enka`

Behavior:

- left Command single-tap posts the JIS 英数 key event
- right Command single-tap posts the JIS かな key event
- pressing another key while Command is held cancels the action
- pressing both Command keys together cancels both actions

Accessibility permission is required before the daemon can observe Command key events. If `enka install` does not show the app in System Settings, open it manually:

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

`enka uninstall` asks before stopping the LaunchAgent and removing the LaunchAgent plist and installed files.

macOS manages Accessibility permission separately. After uninstalling, open Accessibility settings, select `Enka`, then click the minus button below the app list:

```text
System Settings > Privacy & Security > Accessibility
```

Manual cleanup:

```bash
rm -rf "$HOME/Applications/enka"
rm -rf "$HOME/.local/state/enka"
```

## Release Packaging

Build a release archive locally:

```bash
sh scripts/package-release.sh
```

Distribution shape:

```text
enka-v0.1.2-macos-arm64.tar.gz
  Enka.app/
  bin/enka
  README.md
  LICENSE (if present)
```

`Enka.app` metadata is copied from `resources/Enka.app`.

Customize version/output:

```bash
ENKA_VERSION=0.1.2 \
ENKA_DIST_DIR=/tmp/enka-dist \
sh scripts/package-release.sh
```

Verify local release artifacts:

```bash
sh scripts/package-release.sh
sh scripts/verify-release.sh
```

Publish a GitHub Release:

1. Open the `Release` workflow in GitHub Actions.
2. Run it manually with a version such as `0.1.2` (without the leading `v`).
3. The workflow builds and verifies the archive on macOS, then publishes
   `v0.1.2` with the `.tar.gz` archive and matching `.sha256` file.

GitHub Pages installer site:

```text
docs/
  CNAME
  install
  latest.json
```

Configure GitHub Pages to publish from `main` / `docs`, then assign the custom
domain `enka.ultrahope.dev`.
