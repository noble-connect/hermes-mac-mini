#!/usr/bin/env bash
#
# Hermes Mac mini bootstrap — one-liner installer
#
# Usage from any Mac terminal:
#   curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/bootstrap.sh | bash -s -- --user USER --label LABEL
#
# Example:
#   curl -fsSL https://raw.githubusercontent.com/noble-connect/hermes-mac-mini/main/bootstrap.sh | bash -s -- --user user --label ai.hermes.gateway.user
#
# What it does:
#   1. Verifies macOS + prerequisites
#   2. Clones (or updates) the repo into a stable local path
#   3. Delegates to install-hermes-daemon-macos.sh with the same args
#
# Rationale: install-hermes-daemon-macos.sh needs a companion `templates/`
# directory. A bare `curl | bash` cannot ship both files atomically, so this
# bootstrap first materializes the whole repo, then runs the real installer.

set -euo pipefail

REPO_URL_DEFAULT="https://github.com/noble-connect/hermes-mac-mini.git"
CLONE_DIR_DEFAULT="$HOME/.hermes-mac-mini"

REPO_URL="${HERMES_MAC_MINI_REPO_URL:-$REPO_URL_DEFAULT}"
CLONE_DIR="${HERMES_MAC_MINI_CLONE_DIR:-$CLONE_DIR_DEFAULT}"
BRANCH="${HERMES_MAC_MINI_BRANCH:-main}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: this bootstrap targets macOS only (uname -s = $(uname -s))" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git not found in PATH — install Xcode Command Line Tools first:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

echo "==> Bootstrapping Hermes Mac mini installer"
echo "    repo:   $REPO_URL"
echo "    branch: $BRANCH"
echo "    local:  $CLONE_DIR"

if [[ -d "$CLONE_DIR/.git" ]]; then
  echo "==> Existing checkout found, fetching latest $BRANCH"
  git -C "$CLONE_DIR" fetch --quiet origin "$BRANCH"
  git -C "$CLONE_DIR" checkout --quiet "$BRANCH"
  git -C "$CLONE_DIR" reset --hard --quiet "origin/$BRANCH"
else
  echo "==> Cloning $REPO_URL to $CLONE_DIR"
  git clone --quiet --branch "$BRANCH" "$REPO_URL" "$CLONE_DIR"
fi

INSTALLER="$CLONE_DIR/install-hermes-daemon-macos.sh"
if [[ ! -x "$INSTALLER" ]]; then
  chmod +x "$INSTALLER" 2>/dev/null || true
fi
if [[ ! -f "$INSTALLER" ]]; then
  echo "ERROR: installer not found at $INSTALLER" >&2
  exit 1
fi

echo "==> Handing off to $(basename "$INSTALLER") $*"
exec bash "$INSTALLER" "$@"
