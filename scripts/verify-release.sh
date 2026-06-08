#!/bin/sh

set -eu

ENKA_VERSION=${ENKA_VERSION:-0.1.2}
ENKA_DIST_DIR=${ENKA_DIST_DIR:-dist}
ENKA_VERIFY_INSTALL_ROOT=${ENKA_VERIFY_INSTALL_ROOT:-/private/tmp/enka-verify-install}

OS=$(uname -s)
if [ "$OS" != "Darwin" ]; then
  echo "error: release verification is supported on macOS only" >&2
  exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
  arm64)
    ENKA_PLATFORM="macos-arm64"
    ;;
  x86_64)
    ENKA_PLATFORM="macos-x86_64"
    ;;
  *)
    echo "error: unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

if [ ! -d "$ENKA_DIST_DIR" ]; then
  echo "error: missing dist directory: $ENKA_DIST_DIR" >&2
  exit 1
fi

ABS_DIST_DIR=$(cd "$ENKA_DIST_DIR" && pwd)

ARCHIVE_PATH="$ABS_DIST_DIR/enka-v${ENKA_VERSION}-${ENKA_PLATFORM}.tar.gz"
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
ARCHIVE_APP_EXEC="Enka.app/Contents/MacOS/Enka"
if tar -tzf "$ARCHIVE_PATH" | awk '$1=="Enka.app/Contents/MacOS/Enka" || $1=="./Enka.app/Contents/MacOS/Enka" { found=1; exit } END { exit !found }'; then
  ARCHIVE_APP_EXEC="$(tar -tzf "$ARCHIVE_PATH" | awk '$1=="Enka.app/Contents/MacOS/Enka" || $1=="./Enka.app/Contents/MacOS/Enka" { print $1; exit }')"
fi

if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?bin/enka$'; then
  echo "error: archive missing expected binary: bin/enka" >&2
  exit 1
fi
if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?Enka\.app/$'; then
  echo "error: archive missing expected app bundle: Enka.app/" >&2
  exit 1
fi
if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?Enka\.app/Contents/Info\.plist$'; then
  echo "error: archive missing expected file: Enka.app/Contents/Info.plist" >&2
  exit 1
fi
if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?Enka\.app/Contents/MacOS/Enka$'; then
  echo "error: archive missing expected file: Enka.app/Contents/MacOS/Enka" >&2
  exit 1
fi
if [ -z "${ARCHIVE_APP_EXEC:-}" ]; then
  echo "error: could not locate app executable in archive: Enka.app/Contents/MacOS/Enka" >&2
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
  if (file == "Enka.app/Contents/MacOS/Enka" && mode ~ /^-..x/ ) {
    found_executable = 1
  }
}
END {
  exit (!found_executable)
}' >/dev/null; then
  echo "error: archived app executable is not marked executable: Enka.app/Contents/MacOS/Enka" >&2
  exit 1
fi
if ! tar -tzf "$ARCHIVE_PATH" | grep -Eq '^(\./)?README.md$'; then
  echo "error: archive missing expected file: README.md" >&2
  exit 1
fi

if [ -z "$ENKA_VERIFY_INSTALL_ROOT" ] || [ "$ENKA_VERIFY_INSTALL_ROOT" = "/" ] || [ "$ENKA_VERIFY_INSTALL_ROOT" = "/private" ] || [ "$ENKA_VERIFY_INSTALL_ROOT" = "/private/tmp" ] || [ "$ENKA_VERIFY_INSTALL_ROOT" = "$HOME" ]; then
  echo "error: refusing to remove unsafe install root: ${ENKA_VERIFY_INSTALL_ROOT:-<empty>}" >&2
  exit 1
fi

echo "verify: preparing install root"
rm -rf "$ENKA_VERIFY_INSTALL_ROOT"

echo "verify: running hosted installer"
(
  ENKA_BASE_URL="file://$ABS_DIST_DIR"
  ENKA_VERSION="$ENKA_VERSION"
  ENKA_INSTALL_ROOT="$ENKA_VERIFY_INSTALL_ROOT"
  ENKA_SKIP_SETUP=1
  export ENKA_BASE_URL ENKA_VERSION ENKA_INSTALL_ROOT ENKA_SKIP_SETUP
  sh docs/install
)

if [ ! -x "$ENKA_VERIFY_INSTALL_ROOT/bin/enka" ]; then
  echo "error: installed enka is missing or not executable" >&2
  exit 1
fi
if [ ! -x "$ENKA_VERIFY_INSTALL_ROOT/Enka.app/Contents/MacOS/Enka" ]; then
  echo "error: installed app executable is missing or not executable" >&2
  exit 1
fi
if head -c 2 "$ENKA_VERIFY_INSTALL_ROOT/Enka.app/Contents/MacOS/Enka" | LC_ALL=C grep -q "^#!"; then
  echo "error: installed app executable appears to be a shell script, expected binary executable" >&2
  exit 1
fi
if [ ! -f "$ENKA_VERIFY_INSTALL_ROOT/Enka.app/Contents/Info.plist" ]; then
  echo "error: installed app Info.plist is missing" >&2
  exit 1
fi

echo "verify: isolated setup"
VERIFY_SETUP_LOG="$VERIFY_TMP_DIR/verify-setup.log"
if ! (
  ENKA_INSTALL_ROOT="$ENKA_VERIFY_INSTALL_ROOT" \
  ENKA_LAUNCH_AGENT_DIR="$ENKA_VERIFY_INSTALL_ROOT/.verify-agents" \
  ENKA_STATE_DIR="$ENKA_VERIFY_INSTALL_ROOT/.verify-state" \
  "$ENKA_VERIFY_INSTALL_ROOT/bin/enka" install --no-open --no-start --wait-accessibility 0
) >"$VERIFY_SETUP_LOG" 2>&1; then
  cat "$VERIFY_SETUP_LOG"
  echo "error: isolated setup command failed" >&2
  exit 1
fi

if [ ! -f "$ENKA_VERIFY_INSTALL_ROOT/.verify-agents/dev.ultrahope.enka.plist" ]; then
  cat "$VERIFY_SETUP_LOG"
  echo "error: isolated setup did not write LaunchAgent plist" >&2
  exit 1
fi
if [ ! -f "$ENKA_VERIFY_INSTALL_ROOT/.verify-state/setup.log" ]; then
  cat "$VERIFY_SETUP_LOG"
  echo "error: isolated setup did not write setup log" >&2
  exit 1
fi
if grep -Fq "Registering LaunchAgent" "$VERIFY_SETUP_LOG"; then
  cat "$VERIFY_SETUP_LOG"
  echo "error: isolated setup attempted to register LaunchAgent" >&2
  exit 1
fi
rm -f "$VERIFY_SETUP_LOG"

ENKA_INSTALL_ROOT="$ENKA_VERIFY_INSTALL_ROOT" \
ENKA_LAUNCH_AGENT_DIR="$ENKA_VERIFY_INSTALL_ROOT/.verify-agents" \
ENKA_STATE_DIR="$ENKA_VERIFY_INSTALL_ROOT/.verify-state" \
"$ENKA_VERIFY_INSTALL_ROOT/bin/enka" status >/dev/null

cat <<EOF
verification passed:
- release artifacts: checksum + archive members
- hosted installer path: docs/install
- installed binary: $ENKA_VERIFY_INSTALL_ROOT/bin/enka
- installed app: $ENKA_VERIFY_INSTALL_ROOT/Enka.app
- isolated setup: install --no-open --no-start --wait-accessibility 0
- CLI status check: enka status
EOF
