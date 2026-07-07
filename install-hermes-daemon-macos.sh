#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/ai.hermes.gateway.plist.template"

HERMES_USER=""
SERVICE_LABEL=""
SKIP_CUTOVER="0"

usage() {
  cat <<'USAGE'
Usage:
  bash install-hermes-daemon-macos.sh --user USER --label LABEL [--skip-cutover]

Example:
  bash install-hermes-daemon-macos.sh --user user --label ai.hermes.gateway.user

What it does:
  - Creates /Library/LaunchDaemons/<LABEL>.plist
  - Moves the user LaunchAgent to ~/Library/LaunchAgents.disabled/
  - Loads and starts the LaunchDaemon in the system domain
  - Verifies status and rolls back to LaunchAgent if daemon startup fails

Options:
  --user USER       macOS user that owns ~/.hermes and should run gateway
  --label LABEL     launchd label, e.g. ai.hermes.gateway.user
  --skip-cutover    create/validate plist only; do not bootout agent or bootstrap daemon
  -h, --help        show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) HERMES_USER="${2:-}"; shift 2 ;;
    --label) SERVICE_LABEL="${2:-}"; shift 2 ;;
    --skip-cutover) SKIP_CUTOVER="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$HERMES_USER" || -z "$SERVICE_LABEL" ]]; then
  echo "ERROR: --user and --label are required" >&2
  usage
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: this installer is for macOS only" >&2
  exit 1
fi

USER_HOME="/Users/$HERMES_USER"
HERMES_HOME="$USER_HOME/.hermes"
HERMES_PYTHON="$HERMES_HOME/hermes-agent/venv/bin/python"
USER_AGENT="$USER_HOME/Library/LaunchAgents/ai.hermes.gateway.plist"
USER_AGENT_DISABLED_DIR="$USER_HOME/Library/LaunchAgents.disabled"
DAEMON_PLIST="/Library/LaunchDaemons/$SERVICE_LABEL.plist"
STDOUT_LOG="$HERMES_HOME/logs/gateway.daemon.log"
STDERR_LOG="$HERMES_HOME/logs/gateway.daemon.error.log"
DAEMON_PATH="/Users/$HERMES_USER/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
TS="$(date +%Y%m%d-%H%M%S)"

step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

step "Validating prerequisites"
id "$HERMES_USER" >/dev/null 2>&1 || fail "User does not exist: $HERMES_USER"
[[ -d "$HERMES_HOME" ]] || fail "Hermes home not found: $HERMES_HOME"
[[ -x "$HERMES_PYTHON" ]] || fail "Hermes venv python not executable: $HERMES_PYTHON"
[[ -f "$TEMPLATE" ]] || fail "Template not found: $TEMPLATE"
mkdir -p "$HERMES_HOME/logs"

if [[ -f "$HERMES_HOME/.env" ]]; then
  echo ".env exists: yes (not printed)"
else
  warn ".env not found at $HERMES_HOME/.env"
fi

step "Checking FileVault"
if command -v fdesetup >/dev/null 2>&1; then
  fdesetup status || true
fi

step "Preparing plist"
TMP_PLIST="/tmp/$SERVICE_LABEL.$TS.plist"
python3 - "$TEMPLATE" "$TMP_PLIST" "$SERVICE_LABEL" "$HERMES_USER" "$USER_HOME" "$HERMES_HOME" "$HERMES_PYTHON" "$DAEMON_PATH" "$STDOUT_LOG" "$STDERR_LOG" <<'PY'
from pathlib import Path
import sys
(template, out, label, user, home, hermes_home, python, path, stdout, stderr) = sys.argv[1:]
s = Path(template).read_text()
repl = {
    "__LABEL__": label,
    "__USER__": user,
    "__HOME__": home,
    "__HERMES_HOME__": hermes_home,
    "__PYTHON__": python,
    "__PATH__": path,
    "__STDOUT__": stdout,
    "__STDERR__": stderr,
}
for k, v in repl.items():
    s = s.replace(k, v)
Path(out).write_text(s)
PY
plutil -lint "$TMP_PLIST"

step "Installing LaunchDaemon plist"
echo "sudo is required to write /Library/LaunchDaemons and load system launchd services."
sudo -v
if [[ -f "$DAEMON_PLIST" ]]; then
  BACKUP="$DAEMON_PLIST.backup-$TS"
  sudo cp "$DAEMON_PLIST" "$BACKUP"
  echo "Existing daemon backed up: $BACKUP"
else
  echo "No existing daemon plist to back up"
fi
sudo cp "$TMP_PLIST" "$DAEMON_PLIST"
sudo chown root:wheel "$DAEMON_PLIST"
sudo chmod 644 "$DAEMON_PLIST"
plutil -lint "$DAEMON_PLIST"
stat -f 'owner=%Su group=%Sg mode=%OLp path=%N' "$DAEMON_PLIST"

if [[ "$SKIP_CUTOVER" == "1" ]]; then
  step "Skip cutover requested; daemon plist created but not loaded"
  exit 0
fi

rollback_to_agent() {
  warn "Daemon did not start cleanly; attempting rollback to user LaunchAgent"
  sudo launchctl bootout "system/$SERVICE_LABEL" >/dev/null 2>&1 || true
  local uid
  uid="$(id -u "$HERMES_USER")"
  local candidate=""
  if [[ -f "$USER_AGENT" ]]; then
    candidate="$USER_AGENT"
  else
    candidate="$(ls -t "$USER_AGENT_DISABLED_DIR"/ai.hermes.gateway.plist.disabled-* 2>/dev/null | head -1 || true)"
    if [[ -n "$candidate" ]]; then
      cp "$candidate" "$USER_AGENT"
      chown "$HERMES_USER":staff "$USER_AGENT" || true
      chmod 644 "$USER_AGENT" || true
      echo "Restored LaunchAgent from: $candidate"
    fi
  fi
  if [[ -f "$USER_AGENT" ]]; then
    launchctl bootstrap "gui/$uid" "$USER_AGENT" >/dev/null 2>&1 || true
    launchctl kickstart -k "gui/$uid/ai.hermes.gateway" >/dev/null 2>&1 || true
    echo "Rollback attempted: LaunchAgent bootstrapped"
  else
    warn "No LaunchAgent available for rollback"
  fi
}

step "Stopping old user LaunchAgent if present"
USER_UID="$(id -u "$HERMES_USER")"
if [[ -f "$USER_AGENT" ]]; then
  launchctl bootout "gui/$USER_UID" "$USER_AGENT" >/dev/null 2>&1 || true
  mkdir -p "$USER_AGENT_DISABLED_DIR"
  DISABLED_PATH="$USER_AGENT_DISABLED_DIR/ai.hermes.gateway.plist.disabled-$TS"
  mv "$USER_AGENT" "$DISABLED_PATH"
  echo "LaunchAgent moved to: $DISABLED_PATH"
else
  echo "No active user LaunchAgent at $USER_AGENT"
fi
sleep 3

step "Loading LaunchDaemon"
sudo launchctl bootout "system/$SERVICE_LABEL" >/dev/null 2>&1 || true
sudo launchctl bootstrap system "$DAEMON_PLIST"
sudo launchctl kickstart -k "system/$SERVICE_LABEL"
sleep 6

step "Verifying LaunchDaemon"
set +e
sudo launchctl print "system/$SERVICE_LABEL" | egrep 'state =|pid =|path =|domain =|username =|runs =|last exit'
PRINT_RC=${PIPESTATUS[0]}
ps -axo pid=,ppid=,user=,args= | egrep -i 'hermes_cli.main gateway|hermes.*gateway' | grep -v egrep
PS_RC=$?
set -e

if [[ "$PRINT_RC" -ne 0 || "$PS_RC" -ne 0 ]]; then
  rollback_to_agent
  fail "LaunchDaemon verification failed"
fi

step "Recent daemon logs"
tail -30 "$STDERR_LOG" 2>/dev/null || true
tail -20 "$STDOUT_LOG" 2>/dev/null || true

step "Hermes status"
if command -v "$USER_HOME/.local/bin/hermes" >/dev/null 2>&1; then
  "$USER_HOME/.local/bin/hermes" gateway status || true
  "$USER_HOME/.local/bin/hermes" status --all | sed -n '1,120p' || true
elif command -v hermes >/dev/null 2>&1; then
  hermes gateway status || true
  hermes status --all | sed -n '1,120p' || true
else
  warn "hermes CLI not found in PATH; skipped hermes status"
fi

step "Done"
echo "LaunchDaemon installed and running: $SERVICE_LABEL"
echo "Next final test: sudo shutdown -r now, do not log in graphically, wait 2-3 minutes, test Telegram response."
