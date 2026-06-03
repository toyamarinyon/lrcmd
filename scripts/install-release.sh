#!/bin/sh

set -eu

ENKA_VERSION=${ENKA_VERSION:-0.1.0}
ENKA_BASE_URL=${ENKA_BASE_URL:-https://github.com/ultrahope/enka/releases/download/v${ENKA_VERSION}}
ENKA_INSTALL_ROOT=${ENKA_INSTALL_ROOT:-"$HOME/Applications/enka"}

OS=$(uname -s)
if [ "$OS" != "Darwin" ]; then
  echo "error: hosted installer currently supports macOS only" >&2
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

ARCHIVE_NAME="enka-v${ENKA_VERSION}-${ENKA_PLATFORM}.tar.gz"
ARCHIVE_URL="$ENKA_BASE_URL/$ARCHIVE_NAME"
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

if [ ! -x "$EXTRACT_DIR/bin/enka" ]; then
  echo "error: extracted archive does not contain expected binary" >&2
  exit 1
fi
if [ ! -x "$EXTRACT_DIR/Enka.app/Contents/MacOS/Enka" ] || [ ! -f "$EXTRACT_DIR/Enka.app/Contents/Info.plist" ]; then
  echo "error: extracted archive does not contain expected app bundle" >&2
  exit 1
fi

mkdir -p "$ENKA_INSTALL_ROOT/bin"
cp "$EXTRACT_DIR/bin/enka" "$ENKA_INSTALL_ROOT/bin/enka"
mkdir -p "$ENKA_INSTALL_ROOT/Enka.app"
rm -rf "$ENKA_INSTALL_ROOT/Enka.app"
cp -R "$EXTRACT_DIR/Enka.app" "$ENKA_INSTALL_ROOT/"

echo "installed:"
echo "  $ENKA_INSTALL_ROOT/bin/enka"
echo "  $ENKA_INSTALL_ROOT/Enka.app"
echo "setup state:"
echo "  service/config files were not modified"
echo "  launchctl was not executed"
echo "next:"
echo "  $ENKA_INSTALL_ROOT/bin/enka setup"
echo "  setup handles app open / Accessibility / launchctl by default"
echo ""
echo "  If you need manual-only mode:"
echo "    open $ENKA_INSTALL_ROOT/Enka.app"
echo "  Then enable Enka.app in System Settings > Privacy & Security > Accessibility"
echo "  $ENKA_INSTALL_ROOT/bin/enka status"
