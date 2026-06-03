#!/bin/sh

set -eu

LRCMD_VERSION=${LRCMD_VERSION:-0.1.0}
LRCMD_DIST_DIR=${LRCMD_DIST_DIR:-dist}
LRCMD_VERIFY_INSTALL_ROOT=${LRCMD_VERIFY_INSTALL_ROOT:-/private/tmp/lrcmd-verify-install}

OS=$(uname -s)
if [ "$OS" != "Darwin" ]; then
  echo "error: release verification is supported on macOS only" >&2
  exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
  arm64)
    LRCMD_PLATFORM="macos-arm64"
    ;;
  x86_64)
    LRCMD_PLATFORM="macos-x86_64"
    ;;
  *)
    echo "error: unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

if [ ! -d "$LRCMD_DIST_DIR" ]; then
  echo "error: missing dist directory: $LRCMD_DIST_DIR" >&2
  exit 1
fi

ABS_DIST_DIR=$(cd "$LRCMD_DIST_DIR" && pwd)

ARCHIVE_PATH="$ABS_DIST_DIR/lrcmd-v${LRCMD_VERSION}-${LRCMD_PLATFORM}.tar.gz"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

if [ ! -f "$ARCHIVE_PATH" ] || [ ! -f "$CHECKSUM_PATH" ]; then
  echo "error: required release artifacts not found. Run scripts/package-release.sh first." >&2
  exit 1
fi

echo "verify: checksum"
(cd "$ABS_DIST_DIR" && shasum -a 256 -c "$(basename "$CHECKSUM_PATH")")

echo "verify: archive members"
VERIFY_TMP_DIR=$(mktemp -d)
trap 'rm -rf "$VERIFY_TMP_DIR"' EXIT
ARCHIVE_APP_EXEC="Lrcmd.app/Contents/MacOS/Lrcmd"
if tar -tzf "$ARCHIVE_PATH" | awk '$1=="Lrcmd.app/Contents/MacOS/Lrcmd" || $1=="./Lrcmd.app/Contents/MacOS/Lrcmd" { found=1; exit } END { exit !found }'; then
  ARCHIVE_APP_EXEC="$(tar -tzf "$ARCHIVE_PATH" | awk '$1=="Lrcmd.app/Contents/MacOS/Lrcmd" || $1=="./Lrcmd.app/Contents/MacOS/Lrcmd" { print $1; exit }')"
fi

if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?bin/lrcmd$'; then
  echo "error: archive missing expected binary: bin/lrcmd" >&2
  exit 1
fi
if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?bin/inctl$'; then
  echo "error: archive missing expected binary: bin/inctl" >&2
  exit 1
fi
if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?Lrcmd\.app/$'; then
  echo "error: archive missing expected app bundle: Lrcmd.app/" >&2
  exit 1
fi
if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?Lrcmd\.app/Contents/Info\.plist$'; then
  echo "error: archive missing expected file: Lrcmd.app/Contents/Info.plist" >&2
  exit 1
fi
if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?Lrcmd\.app/Contents/MacOS/Lrcmd$'; then
  echo "error: archive missing expected file: Lrcmd.app/Contents/MacOS/Lrcmd" >&2
  exit 1
fi
if [ -z "${ARCHIVE_APP_EXEC:-}" ]; then
  echo "error: could not locate app executable in archive: Lrcmd.app/Contents/MacOS/Lrcmd" >&2
  exit 1
fi
ARCHIVE_TMP_EXEC="$VERIFY_TMP_DIR/$(printf '%s' "$ARCHIVE_APP_EXEC" | tr '/' '_')"
if ! tar -xOf "$ARCHIVE_PATH" "$ARCHIVE_APP_EXEC" > "$ARCHIVE_TMP_EXEC"; then
  echo "error: failed to extract app executable from archive: $ARCHIVE_APP_EXEC" >&2
  exit 1
fi
if LC_ALL=C head -c 2 "$ARCHIVE_TMP_EXEC" | grep -q "^#!"; then
  echo "error: archive app executable appears to be a shell script, expected binary executable" >&2
  exit 1
else
  echo "verify: archive app executable is binary-style (no #! script header)"
fi
if ! tar -tvf "$ARCHIVE_PATH" | awk '
{
  mode = $1
  file = $NF
  sub(/^\.\/?/, "", file)
  if (file == "Lrcmd.app/Contents/MacOS/Lrcmd" && mode ~ /^-..x/ ) {
    found_executable = 1
  }
}
END {
  exit (!found_executable)
}' >/dev/null; then
  echo "error: archived app executable is not marked executable: Lrcmd.app/Contents/MacOS/Lrcmd" >&2
  exit 1
fi
if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?README.md$'; then
  echo "error: archive missing expected file: README.md" >&2
  exit 1
fi

if [ -z "$LRCMD_VERIFY_INSTALL_ROOT" ] || [ "$LRCMD_VERIFY_INSTALL_ROOT" = "/" ] || [ "$LRCMD_VERIFY_INSTALL_ROOT" = "/private" ] || [ "$LRCMD_VERIFY_INSTALL_ROOT" = "/private/tmp" ] || [ "$LRCMD_VERIFY_INSTALL_ROOT" = "$HOME" ]; then
  echo "error: refusing to remove unsafe install root: ${LRCMD_VERIFY_INSTALL_ROOT:-<empty>}" >&2
  exit 1
fi

echo "verify: preparing install root"
rm -rf "$LRCMD_VERIFY_INSTALL_ROOT"

echo "verify: running hosted installer"
(
  LRCMD_BASE_URL="file://$ABS_DIST_DIR"
  LRCMD_INSTALL_ROOT="$LRCMD_VERIFY_INSTALL_ROOT"
  export LRCMD_BASE_URL LRCMD_INSTALL_ROOT
  sh scripts/install-release.sh
)

if [ ! -x "$LRCMD_VERIFY_INSTALL_ROOT/bin/lrcmd" ]; then
  echo "error: installed lrcmd is missing or not executable" >&2
  exit 1
fi
if [ ! -x "$LRCMD_VERIFY_INSTALL_ROOT/bin/inctl" ]; then
  echo "error: installed inctl is missing or not executable" >&2
  exit 1
fi
if [ ! -x "$LRCMD_VERIFY_INSTALL_ROOT/Lrcmd.app/Contents/MacOS/Lrcmd" ]; then
  echo "error: installed app executable is missing or not executable" >&2
  exit 1
fi
if head -c 2 "$LRCMD_VERIFY_INSTALL_ROOT/Lrcmd.app/Contents/MacOS/Lrcmd" | LC_ALL=C grep -q "^#!"; then
  echo "error: installed app executable appears to be a shell script, expected binary executable" >&2
  exit 1
fi
if [ ! -f "$LRCMD_VERIFY_INSTALL_ROOT/Lrcmd.app/Contents/Info.plist" ]; then
  echo "error: installed app Info.plist is missing" >&2
  exit 1
fi

echo "verify: dry-run execution"
VERIFY_SETUP_DRY_RUN_LOG="$VERIFY_TMP_DIR/verify-setup-dry-run.log"
if ! (
  LRCMD_INSTALL_ROOT="$LRCMD_VERIFY_INSTALL_ROOT" \
  LRCMD_CONFIG_DIR="$LRCMD_VERIFY_INSTALL_ROOT/.verify-config" \
  LRCMD_LAUNCH_AGENT_DIR="$LRCMD_VERIFY_INSTALL_ROOT/.verify-agents" \
  "$LRCMD_VERIFY_INSTALL_ROOT/bin/lrcmd" setup --dry-run --yes --wait-accessibility 0
) >"$VERIFY_SETUP_DRY_RUN_LOG" 2>&1; then
  cat "$VERIFY_SETUP_DRY_RUN_LOG"
  echo "error: setup dry-run command failed" >&2
  exit 1
fi

if [ -e "$LRCMD_VERIFY_INSTALL_ROOT/.verify-config/config.json" ] || [ -e "$LRCMD_VERIFY_INSTALL_ROOT/.verify-agents/dev.ultrahope.lrcmd.plist" ]; then
  cat "$VERIFY_SETUP_DRY_RUN_LOG"
  echo "error: setup dry-run modified files unexpectedly" >&2
  exit 1
fi
if [ -d "$LRCMD_VERIFY_INSTALL_ROOT/.verify-config" ] || [ -d "$LRCMD_VERIFY_INSTALL_ROOT/.verify-agents" ]; then
  cat "$VERIFY_SETUP_DRY_RUN_LOG"
  echo "error: setup dry-run created config or launch agent directories unexpectedly" >&2
  exit 1
fi
if ! grep -Fq "No files will be written, no apps opened, no launchctl commands run." "$VERIFY_SETUP_DRY_RUN_LOG"; then
  cat "$VERIFY_SETUP_DRY_RUN_LOG"
  echo "error: setup dry-run did not report safe no-op behavior" >&2
  exit 1
fi
rm -f "$VERIFY_SETUP_DRY_RUN_LOG"

LRCMD_INSTALL_ROOT="$LRCMD_VERIFY_INSTALL_ROOT" "$LRCMD_VERIFY_INSTALL_ROOT/bin/lrcmd" status --dry-run >/dev/null

cat <<EOF
verification passed:
- release artifacts: checksum + archive members
- hosted installer path: scripts/install-release.sh
- installed binaries: $LRCMD_VERIFY_INSTALL_ROOT/bin/lrcmd, $LRCMD_VERIFY_INSTALL_ROOT/bin/inctl
- installed app: $LRCMD_VERIFY_INSTALL_ROOT/Lrcmd.app
- CLI status check: lrcmd status --dry-run
EOF
