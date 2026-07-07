#!/usr/bin/env bash
set -euo pipefail

HERMES_USER=""
SERVICE_LABEL=""

usage() {
  cat <<'USAGE'
Usage:
  bash verify-hermes-daemon.sh --user USER --label LABEL

Example:
  bash verify-hermes-daemon.sh --user user --label ai.hermes.gateway.user
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) HERMES_USER="${2:-}"; shift 2 ;;
    --label) SERVICE_LABEL="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$HERMES_USER" && -n "$SERVICE_LABEL" ]] || { usage; exit 2; }

USER_HOME="/Users/$HERMES_USER"
HERMES_HOME="$USER_HOME/.hermes"
DAEMON_PLIST="/Library/LaunchDaemons/$SERVICE_LABEL.plist"
USER_AGENT="$USER_HOME/Library/LaunchAgents/ai.hermes.gateway.plist"
DISABLED_DIR="$USER_HOME/Library/LaunchAgents.disabled"
HERMES_BIN="$USER_HOME/.local/bin/hermes"

section() { printf '\n--- %s ---\n' "$*"; }

section "Identity"
printf 'current_user=%s\ntarget_user=%s\nhost=%s\n' "$(whoami)" "$HERMES_USER" "$(hostname)"
sw_vers || true
uname -m || true

section "FileVault"
fdesetup status || true

section "Paths"
for p in "$HERMES_HOME" "$HERMES_HOME/config.yaml" "$HERMES_HOME/.env" "$DAEMON_PLIST" "$USER_AGENT" "$DISABLED_DIR" "$HERMES_BIN"; do
  if [[ -e "$p" ]]; then
    printf 'exists: %s\n' "$p"
  else
    printf 'missing: %s\n' "$p"
  fi
done

section "LaunchDaemon plist"
if [[ -f "$DAEMON_PLIST" ]]; then
  plutil -lint "$DAEMON_PLIST" || true
  stat -f 'owner=%Su group=%Sg mode=%OLp path=%N' "$DAEMON_PLIST" || true
  /usr/libexec/PlistBuddy -c 'Print :Label' "$DAEMON_PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Print :UserName' "$DAEMON_PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Print :WorkingDirectory' "$DAEMON_PLIST" 2>/dev/null || true
fi

section "LaunchDaemon status"
sudo launchctl print "system/$SERVICE_LABEL" 2>/dev/null | egrep 'state =|pid =|path =|domain =|username =|runs =|last exit' || echo "Daemon not loaded or sudo required"

section "User LaunchAgent active?"
launchctl print "gui/$(id -u "$HERMES_USER")" 2>/dev/null | grep -i 'ai.hermes.gateway' || echo "No active ai.hermes.gateway in gui domain"

section "Gateway processes"
ps -axo pid=,ppid=,user=,args= | egrep -i 'hermes_cli.main gateway|hermes.*gateway' | grep -v egrep || echo "No gateway process found"

section "Hermes status"
if [[ -x "$HERMES_BIN" ]]; then
  "$HERMES_BIN" gateway status || true
  "$HERMES_BIN" status --all | sed -n '1,120p' || true
else
  echo "Hermes binary not executable at $HERMES_BIN"
fi

section "Daemon logs stderr"
tail -60 "$HERMES_HOME/logs/gateway.daemon.error.log" 2>/dev/null || echo "No daemon stderr log"

section "Daemon logs stdout"
tail -40 "$HERMES_HOME/logs/gateway.daemon.log" 2>/dev/null || echo "No daemon stdout log"

section "Summary"
echo "If FileVault is Off, daemon is running in system domain, and Telegram responds after reboot without graphical login, installation is complete."
