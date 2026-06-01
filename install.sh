#!/bin/bash
# Installa claude-discord-presence: servizio launchd + plugin SwiftBar, puntando
# a QUESTA cartella (ovunque sia). Idempotente: rilancialo dopo uno spostamento.
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UID_N="$(id -u)"
NODE="$(command -v node || echo /opt/homebrew/bin/node)"
LABEL="com.jarvis.discord-presence"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SB_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"

echo "→ repo dir: $DIR"
echo "→ node:     $NODE"

# --- launchd plist ---
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$NODE</string>
        <string>$DIR/presence.mjs</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>StandardOutPath</key><string>$DIR/presence.log</string>
    <key>StandardErrorPath</key><string>$DIR/presence.log</string>
    <key>WorkingDirectory</key><string>$DIR</string>
</dict>
</plist>
EOF
echo "→ plist scritto: $PLIST"

# bootout è asincrono: attendi che sparisca prima di ri-bootstrappare
launchctl bootout "gui/$UID_N/$LABEL" 2>/dev/null || true
for _ in 1 2 3 4 5; do
  launchctl list | grep -q "$LABEL" || break
  sleep 1
done
if launchctl bootstrap "gui/$UID_N" "$PLIST" 2>/dev/null; then
  echo "→ daemon avviato"
else
  # già caricato → ricarica a caldo
  launchctl kickstart -k "gui/$UID_N/$LABEL"
  echo "→ daemon ricaricato (kickstart)"
fi

# --- SwiftBar plugin (opzionale) ---
if [ -d "$SB_DIR" ] || [ -d "/Applications/SwiftBar.app" ]; then
  mkdir -p "$SB_DIR"
  PLUGIN="$SB_DIR/claude-sessions.5s.sh"
  sed "s#__DIR__#$DIR#g" "$DIR/claude-sessions.5s.sh" > "$PLUGIN"
  chmod +x "$PLUGIN"
  echo "→ plugin SwiftBar installato: $PLUGIN"
  open -a SwiftBar 2>/dev/null || true
  open -g "swiftbar://refreshallplugins" 2>/dev/null || true
else
  echo "→ SwiftBar non trovato, skip plugin (installalo con: brew install --cask swiftbar)"
fi

echo "✓ fatto. Stato: launchctl list | grep discord-presence"
