#!/usr/bin/env bash
# ==============================================================================
# mcp_start.sh — Startet die sichtbare SnipWar-Runtime mit dem MCP-Server.
#  MCP braucht einen echten Renderer: Headless wird vom Server verweigert.
#  Nutzung: ./mcp_start.sh [player|qa|dev]     (Standard: player)
#  Port:    127.0.0.1:9090 (Runtime) | 9091 (Editor).
# ==============================================================================
set -euo pipefail

PROFILE="${1:-player}"
case "$PROFILE" in
  player|qa|dev) ;;
  *) echo "Unbekanntes Profil '$PROFILE' (erlaubt: player|qa|dev)"; exit 2;;
esac

BIN="${GODOT_BIN:-C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe}"
if [ ! -f "$BIN" ]; then
  echo "GODOT_BIN nicht auffindbar: $BIN (env GODOT_BIN setzen oder Binär liegt woanders)."
  exit 1
fi

# Skill mcp-connect: Listener-Check VOR dem Start — nie doppelt/Probe unterbrechen.
if [ "$(command -v netstat)" != "" ]; then
  if netstat -ano 2>/dev/null | grep -qE "TCP.*:9090 .*LISTENING"; then
    echo "Port 9090 lauscht bereits — bestehenden Runtime/Editor verwenden, kein zweiter Server."
    exit 0
  fi
fi

echo "Starte sichtbare Runtime mit MCP auf 127.0.0.1:9090 (Profil=$PROFILE) …"
exec "$BIN" --path . -- --mcp --mcp-port 9090 --mcp-profile="$PROFILE"