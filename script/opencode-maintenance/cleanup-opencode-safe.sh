#!/usr/bin/env bash
set -euo pipefail

APP_NAME="opencode"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

DATA_DIR="$XDG_DATA_HOME/$APP_NAME"
CACHE_DIR="$XDG_CACHE_HOME/$APP_NAME"

APPLY=0
DEEP=0

usage() {
  cat <<'EOF'
Usage: cleanup-opencode-safe.sh [options]

Safely cleans rebuildable OpenCode files without deleting chat history or LLM config.

Options:
  --apply      Execute deletion (default is dry-run)
  --deep       Also remove worktree scratch data
  -h, --help   Show this help
EOF
}

log() {
  printf '[cleanup] %s\n' "$*"
}

while (($# > 0)); do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --deep)
      DEEP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

targets=(
  "$CACHE_DIR"
  "$DATA_DIR/log"
  "$DATA_DIR/tool-output"
)

if [[ "$DEEP" -eq 1 ]]; then
  targets+=("$DATA_DIR/worktree")
fi

protected=(
  "$DATA_DIR/opencode.db"
  "$DATA_DIR/opencode.db-wal"
  "$DATA_DIR/opencode.db-shm"
  "$DATA_DIR/storage"
  "$DATA_DIR/auth.json"
)

log "Protected paths (never removed):"
for p in "${protected[@]}"; do
  printf '  - %s\n' "$p"
done

if [[ "$APPLY" -eq 0 ]]; then
  log "Dry-run mode. Nothing will be deleted."
fi

for p in "${targets[@]}"; do
  if [[ ! -e "$p" ]]; then
    log "Skip missing: $p"
    continue
  fi

  if [[ "$APPLY" -eq 1 ]]; then
    rm -rf "$p"
    log "Removed: $p"
  else
    log "Would remove: $p"
  fi
done

if [[ "$APPLY" -eq 0 ]]; then
  log "Done (dry-run). Re-run with --apply to execute."
else
  log "Cleanup complete. Persistent history/config were preserved."
fi
