#!/bin/sh

set -eu

install_root=${LRCMD_INSTALL_ROOT:-"$HOME/Applications/lrcmd"}
bin_dir="$install_root/bin"
app_dir="$install_root/Lrcmd.app"
app_contents_dir="$app_dir/Contents"
app_macos_dir="$app_contents_dir/MacOS"
app_executable="$app_macos_dir/Lrcmd"

echo "==> Building release binaries"
swift build -c release

echo "==> Installing binaries into $bin_dir (installed/updated)"
mkdir -p "$bin_dir"
cp ".build/release/lrcmd" "$bin_dir/lrcmd"
cp ".build/release/inctl" "$bin_dir/inctl"
chmod +x "$bin_dir/lrcmd"

echo "==> Installing Lrcmd.app binary executable into $app_dir"
mkdir -p "$app_macos_dir"
cp ".build/release/lrcmd" "$app_executable"
chmod +x "$app_executable"

cat <<EOF > "$app_contents_dir/Info.plist"
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

cat <<EOF

Install complete (installed/updated).

Install root: $install_root
Installed:
- $bin_dir/lrcmd
- $bin_dir/inctl
- $app_dir
- $app_executable

service/config: not changed by installer
  - No config file was generated.
  - No LaunchAgent plist was generated.

Next steps:
- Run onboarding setup:
  - $bin_dir/lrcmd setup
- setup handles app open, Accessibility, and launchctl by default.
- Check status output with:
  - $bin_dir/lrcmd status
EOF
