#!/bin/sh

set -eu

install_root=${ENKA_INSTALL_ROOT:-"$HOME/Applications/enka"}
bin_dir="$install_root/bin"
app_dir="$install_root/Enka.app"
app_contents_dir="$app_dir/Contents"
app_macos_dir="$app_contents_dir/MacOS"
app_executable="$app_macos_dir/Enka"

echo "==> Building release binary"
swift build -c release

echo "==> Installing binary into $bin_dir (installed/updated)"
mkdir -p "$bin_dir"
cp ".build/release/enka" "$bin_dir/enka"
chmod +x "$bin_dir/enka"

echo "==> Installing Enka.app binary executable into $app_dir"
mkdir -p "$app_macos_dir"
cp ".build/release/enka" "$app_executable"
chmod +x "$app_executable"

cat <<EOF > "$app_contents_dir/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Enka</string>
  <key>CFBundleExecutable</key>
  <string>Enka</string>
  <key>CFBundleIdentifier</key>
  <string>dev.ultrahope.enka</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

cat <<EOF

Install complete (installed/updated).

Install root: $install_root
Installed:
- $bin_dir/enka
- $app_dir
- $app_executable

service/config: not changed by installer
  - No config file was generated.
  - No LaunchAgent plist was generated.

Next steps:
- Run onboarding setup:
  - $bin_dir/enka setup
- setup handles app open, Accessibility, and launchctl by default.
- Check status output with:
  - $bin_dir/enka status
EOF
