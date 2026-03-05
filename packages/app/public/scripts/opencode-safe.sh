#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
APP_NAME="opencode"
YES=0
DRY_RUN=0
VERBOSE=0
JSON=0
FROM=""

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

DATA_DIR="${OPENCODE_DATA_DIR:-$XDG_DATA_HOME/$APP_NAME}"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$XDG_CONFIG_HOME/$APP_NAME}"
STATE_DIR="${OPENCODE_STATE_DIR:-$XDG_STATE_HOME/$APP_NAME}"
BACKUP_ROOT="${OPENCODE_BACKUP_ROOT:-$HOME/.opencode-backups}"

usage() {
  cat <<'EOF'
Usage: opencode-safe.sh <command> [options]

Commands:
  update            Backup + safe cleanup
  backup            Backup persistent OpenCode data
  cleanup           Remove rebuildable cache/log/temp files
  restore           Restore from backup (--from required)
  status            Show detected paths and file presence

Options:
  --yes             Apply destructive steps without prompt
  --dry-run         Print what would change
  --from <path>     Backup folder or .tar.gz file (restore)
  --json            Print machine-readable status output
  --verbose         Print extra logs
  -h, --help        Show this help

Examples:
  opencode-safe.sh update --yes
  opencode-safe.sh backup
  opencode-safe.sh cleanup --dry-run
  opencode-safe.sh restore --from "$HOME/.opencode-backups/20260305_120000.tar.gz" --yes
EOF
}

log() {
  if [[ "$JSON" -eq 0 ]]; then
    printf '[opencode-safe] %s\n' "$*"
  fi
}

vlog() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    log "$*"
  fi
}

fail() {
  if [[ "$JSON" -eq 1 ]]; then
    printf '{"ok":false,"error":"%s"}\n' "$*"
  else
    printf '[opencode-safe] ERROR: %s\n' "$*" >&2
  fi
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

confirm_or_fail() {
  local action="$1"
  if [[ "$YES" -eq 1 ]]; then
    return
  fi
  fail "$action requires --yes"
}

copy_if_exists() {
  local src="$1"
  local dst="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
    vlog "Copied $src -> $dst"
  else
    vlog "Skipped missing: $src"
  fi
}

backup_now() {
  require tar
  local ts target archive
  ts="$(date +%Y%m%d_%H%M%S)"
  target="$BACKUP_ROOT/$ts"
  archive="$BACKUP_ROOT/$ts.tar.gz"

  mkdir -p "$BACKUP_ROOT"
  [[ -e "$target" ]] && fail "Backup folder already exists: $target"
  mkdir -p "$target/data" "$target/config" "$target/state"

  copy_if_exists "$DATA_DIR/opencode.db" "$target/data/opencode.db"
  copy_if_exists "$DATA_DIR/opencode.db-wal" "$target/data/opencode.db-wal"
  copy_if_exists "$DATA_DIR/opencode.db-shm" "$target/data/opencode.db-shm"
  copy_if_exists "$DATA_DIR/storage" "$target/data/storage"
  copy_if_exists "$DATA_DIR/auth.json" "$target/data/auth.json"
  copy_if_exists "$CONFIG_DIR" "$target/config/opencode"
  copy_if_exists "$STATE_DIR" "$target/state/opencode"

  if [[ -f "$target/data/auth.json" ]]; then
    chmod 600 "$target/data/auth.json" || true
  fi

  cat >"$target/metadata.txt" <<EOF
version=$VERSION
created_at=$ts
source_data_dir=$DATA_DIR
source_config_dir=$CONFIG_DIR
source_state_dir=$STATE_DIR
EOF

  (
    cd "$target"
    find . -type f -print0 | sort -z | xargs -0 sha256sum > checksums.sha256
  )

  tar -czf "$archive" -C "$BACKUP_ROOT" "$ts"

  if [[ "$JSON" -eq 1 ]]; then
    printf '{"ok":true,"action":"backup","folder":"%s","archive":"%s"}\n' "$target" "$archive"
  else
    log "Backup complete"
    log "Folder: $target"
    log "Archive: $archive"
  fi
}

cleanup_now() {
  local targets
  targets=(
    "$HOME/.cache/opencode"
    "$DATA_DIR/log"
    "$DATA_DIR/tool-output"
    "$DATA_DIR/worktree"
  )

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Dry-run cleanup"
    for p in "${targets[@]}"; do
      if [[ -e "$p" ]]; then
        log "Would remove: $p"
      else
        vlog "Missing: $p"
      fi
    done
    return
  fi

  confirm_or_fail "cleanup"
  for p in "${targets[@]}"; do
    if [[ -e "$p" ]]; then
      rm -rf "$p"
      vlog "Removed: $p"
    fi
  done
  log "Cleanup complete"
}

resolve_restore_source() {
  local from="$1"
  if [[ -d "$from" ]]; then
    printf '%s\n' "$from"
    return
  fi
  if [[ -f "$from" ]]; then
    local tmp
    tmp="$(mktemp -d)"
    tar -xzf "$from" -C "$tmp"
    local children
    mapfile -t children < <(find "$tmp" -mindepth 1 -maxdepth 1 -type d)
    [[ "${#children[@]}" -eq 1 ]] || fail "Archive must contain exactly one folder"
    printf '%s\n' "${children[0]}"
    return
  fi
  fail "Restore source not found: $from"
}

restore_now() {
  [[ -n "$FROM" ]] || fail "restore requires --from <path>"
  confirm_or_fail "restore"

  local src
  src="$(resolve_restore_source "$FROM")"

  local ts snap
  ts="$(date +%Y%m%d_%H%M%S)"
  snap="$BACKUP_ROOT/pre-restore-$ts"
  mkdir -p "$snap"

  copy_if_exists "$DATA_DIR/opencode.db" "$snap/opencode.db"
  copy_if_exists "$DATA_DIR/opencode.db-wal" "$snap/opencode.db-wal"
  copy_if_exists "$DATA_DIR/opencode.db-shm" "$snap/opencode.db-shm"
  copy_if_exists "$DATA_DIR/storage" "$snap/storage"
  copy_if_exists "$DATA_DIR/auth.json" "$snap/auth.json"
  copy_if_exists "$CONFIG_DIR" "$snap/config"
  copy_if_exists "$STATE_DIR" "$snap/state"

  mkdir -p "$DATA_DIR" "$CONFIG_DIR" "$STATE_DIR"

  rm -rf "$DATA_DIR/storage" "$CONFIG_DIR" "$STATE_DIR"
  mkdir -p "$DATA_DIR"

  copy_if_exists "$src/data/opencode.db" "$DATA_DIR/opencode.db"
  copy_if_exists "$src/data/opencode.db-wal" "$DATA_DIR/opencode.db-wal"
  copy_if_exists "$src/data/opencode.db-shm" "$DATA_DIR/opencode.db-shm"
  copy_if_exists "$src/data/storage" "$DATA_DIR/storage"
  copy_if_exists "$src/data/auth.json" "$DATA_DIR/auth.json"
  copy_if_exists "$src/config/opencode" "$CONFIG_DIR"
  copy_if_exists "$src/state/opencode" "$STATE_DIR"

  if [[ -f "$DATA_DIR/auth.json" ]]; then
    chmod 600 "$DATA_DIR/auth.json" || true
  fi

  if [[ "$JSON" -eq 1 ]]; then
    printf '{"ok":true,"action":"restore","source":"%s","snapshot":"%s"}\n' "$FROM" "$snap"
  else
    log "Restore complete"
    log "Safety snapshot: $snap"
  fi
}

status_now() {
  local db auth cfg stg
  db=0
  auth=0
  cfg=0
  stg=0
  [[ -f "$DATA_DIR/opencode.db" ]] && db=1
  [[ -f "$DATA_DIR/auth.json" ]] && auth=1
  [[ -d "$CONFIG_DIR" ]] && cfg=1
  [[ -d "$DATA_DIR/storage" ]] && stg=1

  if [[ "$JSON" -eq 1 ]]; then
    printf '{"ok":true,"data_dir":"%s","config_dir":"%s","state_dir":"%s","db":%s,"auth":%s,"config":%s,"storage":%s}\n' \
      "$DATA_DIR" "$CONFIG_DIR" "$STATE_DIR" "$db" "$auth" "$cfg" "$stg"
  else
    log "Version: $VERSION"
    log "Data dir: $DATA_DIR"
    log "Config dir: $CONFIG_DIR"
    log "State dir: $STATE_DIR"
    log "Found opencode.db: $db"
    log "Found auth.json: $auth"
    log "Found config dir: $cfg"
    log "Found storage dir: $stg"
  fi
}

parse_args() {
  COMMAND="${1:-}"
  [[ -n "$COMMAND" ]] || {
    usage
    exit 1
  }
  shift || true

  while (($# > 0)); do
    case "$1" in
      --yes)
        YES=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --json)
        JSON=1
        ;;
      --verbose)
        VERBOSE=1
        ;;
      --from)
        FROM="${2:-}"
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
    shift
  done
}

main() {
  parse_args "$@"
  case "$COMMAND" in
    backup)
      backup_now
      ;;
    cleanup)
      cleanup_now
      ;;
    restore)
      restore_now
      ;;
    status)
      status_now
      ;;
    update)
      backup_now
      if [[ "$DRY_RUN" -eq 1 ]]; then
        cleanup_now
      else
        DRY_RUN=1
        cleanup_now
        DRY_RUN=0
        cleanup_now
      fi
      ;;
    *)
      fail "Unknown command: $COMMAND"
      ;;
  esac
}

main "$@"
