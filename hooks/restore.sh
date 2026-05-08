#!/usr/bin/env bash
# restore.sh — List and restore files backed up by auto-backup.sh

set -euo pipefail

BACKUP_ROOT="${CLAUDE_BACKUP_DIR:-$HOME/.claude/backups}"

usage() {
    cat <<EOF
Usage:
  restore.sh --list [pattern]          List all backups (optionally filtered)
  restore.sh --restore <backup_path>   Restore a specific backup
  restore.sh --restore <backup_path> --to <dest_path>   Restore to a custom path
EOF
    exit 1
}

cmd_list() {
    local pattern="${1:-}"
    if [[ ! -d "$BACKUP_ROOT" ]]; then
        echo "No backups found at $BACKUP_ROOT"
        exit 0
    fi
    find "$BACKUP_ROOT" -type f -name "*${pattern}*" | sort
}

cmd_restore() {
    local backup="$1"
    local dest="${2:-}"

    [[ ! -f "$backup" ]] && { echo "Error: backup not found: $backup"; exit 1; }

    if [[ -z "$dest" ]]; then
        # Strip the HHMMSS_ prefix to recover the original filename
        orig_name=$(basename "$backup" | sed 's/^[0-9]\{6\}_//')
        dest="./$orig_name"
    fi

    echo "Restore '$backup' → '$dest'? [y/N] "
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Aborted."; exit 0; }

    cp "$backup" "$dest"
    echo "Restored to $dest"
}

# Parse arguments
[[ $# -eq 0 ]] && usage

case "$1" in
    --list)
        cmd_list "${2:-}"
        ;;
    --restore)
        [[ -z "${2:-}" ]] && usage
        backup_path="$2"
        dest_path=""
        if [[ "${3:-}" == "--to" ]]; then
            [[ -z "${4:-}" ]] && usage
            dest_path="$4"
        fi
        cmd_restore "$backup_path" "$dest_path"
        ;;
    *)
        usage
        ;;
esac
