#!/bin/sh

set -eu

install_root=${LRCMD_INSTALL_ROOT:-"$HOME/Applications/lrcmd"}
config_dir=${LRCMD_CONFIG_DIR:-"$HOME/.config/lrcmd"}
bin_dir="$install_root/bin"
config_file="$config_dir/config.json"

echo "==> Building release binaries"
swift build -c release

echo "==> Installing binaries into $bin_dir"
mkdir -p "$bin_dir"
cp ".build/release/lrcmd" "$bin_dir/lrcmd"
cp ".build/release/inctl" "$bin_dir/inctl"

echo "==> Ensuring config directory exists at $config_dir"
mkdir -p "$config_dir"

if [ ! -f "$config_file" ]; then
  echo "==> Creating config at $config_file"
  cat >"$config_file" <<EOF
{
  "leftCommand": {
    "command": "$bin_dir/inctl",
    "arguments": ["select", "com.apple.keylayout.ABC"]
  },
  "rightCommand": {
    "command": "$bin_dir/inctl",
    "arguments": ["select", "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"]
  }
}
EOF
else
  echo "==> Keeping existing config at $config_file"
fi

cat <<EOF

Install complete.

Install root: $install_root
Config path:  $config_file

Next steps:
- Allow Accessibility access for the installed lrcmd binary before using key monitoring.
- v0.0.1 does not register a LaunchAgent or run launchctl for you.
- If you want background launch behavior, migrate any LaunchAgent setup manually for now.
EOF
