#!/usr/bin/env bash
set -euo pipefail

umask 077

APP_NAME="opencode"
TS="$(date +%Y%m%d_%H%M%S)"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

DATA_DIR="$XDG_DATA_HOME/$APP_NAME"
CONFIG_DIR="$XDG_CONFIG_HOME/$APP_NAME"
STATE_DIR="$XDG_STATE_HOME/$APP_NAME"

BACKUP_ROOT="${OPENCODE_BACKUP_ROOT:-$HOME/.opencode-backups}"
NAME="$TS"
NO_ARCHIVE=0

usage() {
  cat <<'EOF'
Usage: backup-opencode.sh [options]

Creates a production backup for OpenCode persistence files.

Options:
  --name <label>         Backup folder name (default: timestamp)
  --backup-root <path>   Root backup directory (default: ~/.opencode-backups)
  --no-archive           Keep folder only (skip .tar.gz generation)
  -h, --help             Show this help

Env:
  OPENCODE_BACKUP_ROOT   Same as --backup-root
EOF
}

log() {
  printf '[backup] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

while (($# > 0)); do
  case "$1" in
    --name)
      NAME="${2:-}"
      shift 2
      ;;
    --backup-root)
      BACKUP_ROOT="${2:-}"
      shift 2
      ;;
    --no-archive)
      NO_ARCHIVE=1
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

require_cmd cp
require_cmd tar
require_cmd sha256sum

if [[ -z "$NAME" ]]; then
  printf 'Backup name cannot be empty\n' >&2
  exit 1
fi

mkdir -p "$BACKUP_ROOT"
TARGET_DIR="$BACKUP_ROOT/$NAME"
if [[ -e "$TARGET_DIR" ]]; then
  printf 'Backup target already exists: %s\n' "$TARGET_DIR" >&2
  exit 1
fi

log "Creating backup at $TARGET_DIR"
mkdir -p "$TARGET_DIR"

copy_if_exists() {
  local src="$1"
  local dst_parent="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$dst_parent"
    cp -a "$src" "$dst_parent/"
    log "Copied: $src"
  else
    log "Skipped (not found): $src"
  fi
}

# Data: sessions/history/auth
mkdir -p "$TARGET_DIR/data"
copy_if_exists "$DATA_DIR/opencode.db" "$TARGET_DIR/data"
copy_if_exists "$DATA_DIR/opencode.db-wal" "$TARGET_DIR/data"
copy_if_exists "$DATA_DIR/opencode.db-shm" "$TARGET_DIR/data"
copy_if_exists "$DATA_DIR/storage" "$TARGET_DIR/data"
copy_if_exists "$DATA_DIR/auth.json" "$TARGET_DIR/data"

# Config: models/providers/agents
mkdir -p "$TARGET_DIR/config"
copy_if_exists "$CONFIG_DIR" "$TARGET_DIR/config"

# State: useful for TUI and local state continuity
mkdir -p "$TARGET_DIR/state"
copy_if_exists "$STATE_DIR" "$TARGET_DIR/state"

if [[ -f "$TARGET_DIR/data/auth.json" ]]; then
  chmod 600 "$TARGET_DIR/data/auth.json"
fi

cat >"$TARGET_DIR/metadata.txt" <<EOF
created_at=$TS
hostname=$(hostname)
user=$(id -un)
source_data_dir=$DATA_DIR
source_config_dir=$CONFIG_DIR
source_state_dir=$STATE_DIR
EOF

(
  cd "$TARGET_DIR"
  find . -type f ! -name checksums.sha256 -print0 | sort -z | xargs -0 sha256sum > checksums.sha256
)

ARCHIVE="$BACKUP_ROOT/$NAME.tar.gz"
if [[ "$NO_ARCHIVE" -eq 0 ]]; then
  log "Creating archive $ARCHIVE"
  tar -czf "$ARCHIVE" -C "$BACKUP_ROOT" "$NAME"
  tar -tzf "$ARCHIVE" >/dev/null
fi

log "Backup complete"
printf 'Folder: %s\n' "$TARGET_DIR"
if [[ "$NO_ARCHIVE" -eq 0 ]]; then
  printf 'Archive: %s\n' "$ARCHIVE"
fi
