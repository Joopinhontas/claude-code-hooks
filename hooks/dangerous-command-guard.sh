#!/usr/bin/env bash
# dangerous-command-guard.sh — Claude Code PreToolUse hook
# Blocks destructive shell commands before Claude executes them.
#
# Blocked patterns: rm -rf, git reset --hard, git push --force,
#                   DROP TABLE/DATABASE, dd, mkfs, chmod 777, fork bomb, shred

set -euo pipefail

INPUT=$(cat)

COMMAND=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null || true)

[[ -z "$COMMAND" ]] && exit 0

# Dangerous patterns (case-insensitive)
PATTERNS=(
    'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive)'  # rm -rf / rm -fr
    'git\s+reset\s+--hard'
    'git\s+push\s+(-f\b|--force\b)'
    'DROP\s+(TABLE|DATABASE|SCHEMA|INDEX)'                               # SQL drops
    'TRUNCATE\s+TABLE'
    'chmod\s+(-R\s+777|777\s+-R)'
    'dd\s+if='                                                           # disk write
    '>\s*/dev/(sd|nvme|hd|vd)'                                          # raw device write
    'mkfs\.'                                                             # format disk
    'shred\s+'
    ':\(\)\s*\{[^}]*\|[^}]*&[^}]*\}'                                    # fork bomb
    'history\s+-[cw]'                                                    # clear history
)

MATCHED_PATTERN=""
for pattern in "${PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qiE "$pattern"; then
        MATCHED_PATTERN="$pattern"
        break
    fi
done

[[ -z "$MATCHED_PATTERN" ]] && exit 0

# Block the command with a clear reason
REASON="Dangerous command blocked: $(echo "$COMMAND" | head -c 200)"

python3 -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': sys.argv[1]
    }
}))" "$REASON"

exit 0
