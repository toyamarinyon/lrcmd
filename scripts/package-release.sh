#!/bin/sh

set -eu

LRCMD_VERSION=${LRCMD_VERSION:-0.1.0}
LRCMD_DIST_DIR=${LRCMD_DIST_DIR:-dist}

OS=$(uname -s)
if [ "$OS" != "Darwin" ]; then
  echo "error: release packaging is supported on macOS only" >&2
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

STAGING_DIR="$LRCMD_DIST_DIR/.staging/lrcmd-v${LRCMD_VERSION}-${LRCMD_PLATFORM}"
STAGING_APP_DIR="$STAGING_DIR/Lrcmd.app"
ARCHIVE_NAME="lrcmd-v${LRCMD_VERSION}-${LRCMD_PLATFORM}.tar.gz"
ARCHIVE_PATH="$LRCMD_DIST_DIR/$ARCHIVE_NAME"

mkdir -p "$LRCMD_DIST_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/bin"
mkdir -p "$STAGING_APP_DIR/Contents/MacOS"

swift build -c release

cp .build/release/lrcmd "$STAGING_DIR/bin/lrcmd"
cp .build/release/inctl "$STAGING_DIR/bin/inctl"
chmod +x "$STAGING_DIR/bin/lrcmd"
cp README.md "$STAGING_DIR/README.md"

if [ -f LICENSE ]; then
  cp LICENSE "$STAGING_DIR/LICENSE"
else
  echo "warning: LICENSE file not found, skipping archive inclusion" >&2
fi
cp .build/release/lrcmd "$STAGING_APP_DIR/Contents/MacOS/Lrcmd"
chmod +x "$STAGING_APP_DIR/Contents/MacOS/Lrcmd"

cat <<EOF > "$STAGING_APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Lrcmd</string>
  <key>CFBundleExecutable</key>
  <string>Lrcmd</string>
  <key>CFBundleIdentifier</key>
  <string>dev.ultrahope.lrcmd</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
EOF

tar -czf "$ARCHIVE_PATH" -C "$STAGING_DIR" .
(cd "$LRCMD_DIST_DIR" && shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256")

echo "created: $ARCHIVE_PATH"
echo "checksum: ${ARCHIVE_PATH}.sha256"
