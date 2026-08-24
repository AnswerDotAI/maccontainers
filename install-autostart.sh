#!/bin/sh
set -eu

label=com.fastai.maccontainers.container-system-start
domain="gui/$(id -u)"
launch_agents="$HOME/Library/LaunchAgents"
log_dir="$HOME/Library/Logs"
plist="$launch_agents/$label.plist"
container_bin=$(command -v container)

mkdir -p "$launch_agents" "$log_dir"

if launchctl print "$domain/$label" >/dev/null 2>&1; then
    launchctl bootout "$domain/$label"
fi

cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$container_bin</string>
    <string>system</string>
    <string>start</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$log_dir/container-system-start.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/container-system-start-error.log</string>
</dict>
</plist>
EOF

chmod 0644 "$plist"
plutil -lint "$plist"
launchctl bootstrap "$domain" "$plist"

echo "Installed $plist"
