#!/usr/bin/env bash
set -euo pipefail

HERMES_USER=""
SERVICE_LABEL=""

usage() {
  cat <<'USAGE'
Usage:
  bash rollback-to-launchagent.sh --user USER --label LABEL

Example:
  bash rollback-to-launchagent.sh --user user --label ai.hermes.gateway.user

This stops the system LaunchDaemon and restores the newest disabled user LaunchAgent backup.
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
USER_UID="$(id -u "$HERMES_USER")"
DAEMON_PLIST="/Library/LaunchDaemons/$SERVICE_LABEL.plist"
USER_AGENT="$USER_HOME/Library/LaunchAgents/ai.hermes.gateway.plist"
DISABLED_DIR="$USER_HOME/Library/LaunchAgents.disabled"
TS="$(date +%Y%m%d-%H%M%S)"

step() { printf '\n==> %s\n' "$*"; }

step "Stopping LaunchDaemon if loaded"
echo "sudo is required to unload system LaunchDaemon."
sudo -v
sudo launchctl bootout "system/$SERVICE_LABEL" >/dev/null 2>&1 || true

step "Restoring LaunchAgent"
if [[ -f "$USER_AGENT" ]]; then
  echo "Active LaunchAgent already exists: $USER_AGENT"
else
  BACKUP="$(ls -t "$DISABLED_DIR"/ai.hermes.gateway.plist.disabled-* 2>/dev/null | head -1 || true)"
  if [[ -z "$BACKUP" ]]; then
    echo "ERROR: no disabled LaunchAgent backup found in $DISABLED_DIR" >&2
    exit 1
  fi
  cp "$BACKUP" "$USER_AGENT"
  chown "$HERMES_USER":staff "$USER_AGENT" || true
  chmod 644 "$USER_AGENT"
  echo "Restored LaunchAgent from: $BACKUP"
fi

step "Loading LaunchAgent"
launchctl bootout "gui/$USER_UID" "$USER_AGENT" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$USER_UID" "$USER_AGENT"
launchctl kickstart -k "gui/$USER_UID/ai.hermes.gateway"
sleep 5

step "Optionally preserving daemon plist"
if [[ -f "$DAEMON_PLIST" ]]; then
  sudo mv "$DAEMON_PLIST" "$DAEMON_PLIST.disabled-$TS"
  echo "Daemon plist moved to: $DAEMON_PLIST.disabled-$TS"
fi

step "Verification"
launchctl print "gui/$USER_UID/ai.hermes.gateway" | egrep 'state =|pid =|path =|domain =|runs =|last exit' || true
ps -axo pid=,ppid=,user=,args= | egrep -i 'hermes_cli.main gateway|hermes.*gateway' | grep -v egrep || true

echo "Rollback complete: gateway should now be running as user LaunchAgent."
