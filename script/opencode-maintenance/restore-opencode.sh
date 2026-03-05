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

FROM=""
FORCE=0
SNAPSHOT=1

usage() {
  cat <<'EOF'
Usage: restore-opencode.sh --from <backup-dir|backup.tar.gz> [options]

Restores OpenCode persistence files from a backup created by backup-opencode.sh.

Options:
  --from <path>    Source backup folder or .tar.gz (required)
  --force          Overwrite destination files if they already exist
  --no-snapshot    Skip automatic pre-restore safety backup
  -h, --help       Show this help
EOF
}

log() {
  printf '[restore] %s\n' "$*"
}

fail() {
  printf '[restore] ERROR: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --from)
      FROM="${2:-}"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --no-snapshot)
      SNAPSHOT=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$FROM" ]] || {
  usage
  fail "--from is required"
}

[[ -e "$FROM" ]] || fail "Backup not found: $FROM"

TMP_DIR=""
SOURCE_DIR="$FROM"
if [[ -f "$FROM" ]]; then
  case "$FROM" in
    *.tar.gz|*.tgz)
      TMP_DIR="$(mktemp -d)"
      tar -xzf "$FROM" -C "$TMP_DIR"
      mapfile -t roots < <(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d)
      [[ "${#roots[@]}" -eq 1 ]] || fail "Archive must contain exactly one top-level directory"
      SOURCE_DIR="${roots[0]}"
      ;;
    *)
      fail "Unsupported backup file format: $FROM"
      ;;
  esac
fi

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

mkdir -p "$DATA_DIR" "$CONFIG_DIR" "$STATE_DIR"

if [[ "$SNAPSHOT" -eq 1 ]]; then
  SNAP_NAME="pre-restore-$TS"
  SNAP_ROOT="$HOME/.opencode-backups"
  mkdir -p "$SNAP_ROOT"
  SNAP_DIR="$SNAP_ROOT/$SNAP_NAME"
  mkdir -p "$SNAP_DIR"
  [[ -e "$DATA_DIR/opencode.db" ]] && cp -a "$DATA_DIR/opencode.db" "$SNAP_DIR/"
  [[ -e "$DATA_DIR/opencode.db-wal" ]] && cp -a "$DATA_DIR/opencode.db-wal" "$SNAP_DIR/"
  [[ -e "$DATA_DIR/opencode.db-shm" ]] && cp -a "$DATA_DIR/opencode.db-shm" "$SNAP_DIR/"
  [[ -e "$DATA_DIR/storage" ]] && cp -a "$DATA_DIR/storage" "$SNAP_DIR/"
  [[ -e "$DATA_DIR/auth.json" ]] && cp -a "$DATA_DIR/auth.json" "$SNAP_DIR/"
  [[ -e "$CONFIG_DIR" ]] && cp -a "$CONFIG_DIR" "$SNAP_DIR/"
  [[ -e "$STATE_DIR" ]] && cp -a "$STATE_DIR" "$SNAP_DIR/"
  log "Safety snapshot created at $SNAP_DIR"
fi

must_absent_or_force() {
  local dst="$1"
  if [[ -e "$dst" && "$FORCE" -ne 1 ]]; then
    fail "Destination exists (use --force): $dst"
  fi
}

restore_item() {
  local src="$1"
  local dst="$2"
  if [[ ! -e "$src" ]]; then
    log "Skip missing in backup: $src"
    return
  fi
  must_absent_or_force "$dst"
  if [[ -e "$dst" && "$FORCE" -eq 1 ]]; then
    rm -rf "$dst"
  fi
  cp -a "$src" "$dst"
  log "Restored: $dst"
}

restore_item "$SOURCE_DIR/data/opencode.db" "$DATA_DIR/opencode.db"
restore_item "$SOURCE_DIR/data/opencode.db-wal" "$DATA_DIR/opencode.db-wal"
restore_item "$SOURCE_DIR/data/opencode.db-shm" "$DATA_DIR/opencode.db-shm"
restore_item "$SOURCE_DIR/data/storage" "$DATA_DIR/storage"
restore_item "$SOURCE_DIR/data/auth.json" "$DATA_DIR/auth.json"
restore_item "$SOURCE_DIR/config/$APP_NAME" "$CONFIG_DIR"
restore_item "$SOURCE_DIR/state/$APP_NAME" "$STATE_DIR"

if [[ -f "$DATA_DIR/auth.json" ]]; then
  chmod 600 "$DATA_DIR/auth.json"
fi

log "Restore complete"
