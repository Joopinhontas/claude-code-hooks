#!/usr/bin/env bash
# auto-backup.sh — Claude Code PreToolUse hook
# Backs up any existing file before Claude writes or edits it.
#
# Config via env vars (optional):
#   CLAUDE_BACKUP_DIR       backup root  (default: ~/.claude/backups)
#   CLAUDE_BACKUP_RETENTION days to keep (default: 7)

set -euo pipefail

BACKUP_ROOT="${CLAUDE_BACKUP_DIR:-$HOME/.claude/backups}"
RETENTION_DAYS="${CLAUDE_BACKUP_RETENTION:-7}"

# Read the tool call JSON from stdin
INPUT=$(cat)

# Extract file_path from tool_input (works for both Write and Edit tools)
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('file_path', ''))
except Exception:
    pass
" 2>/dev/null || true)

# Nothing to do if the file doesn't exist yet (new file creation)
[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Resolve to absolute path
FILE_PATH=$(realpath "$FILE_PATH")

# Backup: ~/.claude/backups/YYYY-MM-DD/HHMMSS_filename
DATE_DIR="$BACKUP_ROOT/$(date +%Y-%m-%d)"
mkdir -p "$DATE_DIR"

BACKUP_PATH="$DATE_DIR/$(date +%H%M%S)_$(basename "$FILE_PATH")"
cp "$FILE_PATH" "$BACKUP_PATH"

echo "[auto-backup] $FILE_PATH → $BACKUP_PATH" >&2

# Silently prune backups older than RETENTION_DAYS
find "$BACKUP_ROOT" -maxdepth 1 -type d -mtime "+$RETENTION_DAYS" \
    -exec rm -rf {} + 2>/dev/null || true
