#!/bin/sh

set -eu

LRCMD_VERSION=${LRCMD_VERSION:-0.1.0}
LRCMD_BASE_URL=${LRCMD_BASE_URL:-https://github.com/ultrahope/lrcmd/releases/download/v${LRCMD_VERSION}}
LRCMD_INSTALL_ROOT=${LRCMD_INSTALL_ROOT:-"$HOME/Applications/lrcmd"}

OS=$(uname -s)
if [ "$OS" != "Darwin" ]; then
  echo "error: hosted installer currently supports macOS only" >&2
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

ARCHIVE_NAME="lrcmd-v${LRCMD_VERSION}-${LRCMD_PLATFORM}.tar.gz"
ARCHIVE_URL="$LRCMD_BASE_URL/$ARCHIVE_NAME"
CHECKSUM_URL="${ARCHIVE_URL}.sha256"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE_PATH="$TMP_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$TMP_DIR/$ARCHIVE_NAME.sha256"

echo "downloading $ARCHIVE_URL"
curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"

if curl -fsSL "$CHECKSUM_URL" -o "$CHECKSUM_PATH"; then
  echo "verifying checksum"
  (cd "$TMP_DIR" && shasum -a 256 -c "$ARCHIVE_NAME.sha256")
else
  echo "warning: checksum file not available, skipping verification" >&2
fi

EXTRACT_DIR="$TMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"

if [ ! -x "$EXTRACT_DIR/bin/lrcmd" ] || [ ! -x "$EXTRACT_DIR/bin/inctl" ]; then
  echo "error: extracted archive does not contain expected binaries" >&2
  exit 1
fi
if [ ! -x "$EXTRACT_DIR/Lrcmd.app/Contents/MacOS/Lrcmd" ] || [ ! -f "$EXTRACT_DIR/Lrcmd.app/Contents/Info.plist" ]; then
  echo "error: extracted archive does not contain expected app bundle" >&2
  exit 1
fi

mkdir -p "$LRCMD_INSTALL_ROOT/bin"
cp "$EXTRACT_DIR/bin/lrcmd" "$LRCMD_INSTALL_ROOT/bin/lrcmd"
cp "$EXTRACT_DIR/bin/inctl" "$LRCMD_INSTALL_ROOT/bin/inctl"
mkdir -p "$LRCMD_INSTALL_ROOT/Lrcmd.app"
rm -rf "$LRCMD_INSTALL_ROOT/Lrcmd.app"
cp -R "$EXTRACT_DIR/Lrcmd.app" "$LRCMD_INSTALL_ROOT/"

echo "installed:"
echo "  $LRCMD_INSTALL_ROOT/bin/lrcmd"
echo "  $LRCMD_INSTALL_ROOT/bin/inctl"
echo "  $LRCMD_INSTALL_ROOT/Lrcmd.app"
echo "setup state:"
echo "  service/config files were not modified"
echo "  launchctl was not executed"
echo "next:"
echo "  $LRCMD_INSTALL_ROOT/bin/lrcmd setup"
echo "  setup handles app open / Accessibility / launchctl by default"
echo ""
echo "  If you need manual-only mode:"
echo "    open $LRCMD_INSTALL_ROOT/Lrcmd.app"
echo "  Then enable Lrcmd.app in System Settings > Privacy & Security > Accessibility"
echo "  $LRCMD_INSTALL_ROOT/bin/lrcmd status"
