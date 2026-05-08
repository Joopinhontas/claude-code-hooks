#!/usr/bin/env bash
# git-autocommit.sh — Claude Code Stop hook
# Stages and commits files modified by Claude at the end of each session.
#
# Opt-in: add to ~/.bashrc or ~/.zshrc:
#   export CLAUDE_AUTO_COMMIT=1

set -euo pipefail

[[ "${CLAUDE_AUTO_COMMIT:-0}" != "1" ]] && exit 0

INPUT=$(cat)

TRANSCRIPT=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('transcript_path', ''))
except Exception:
    pass
" 2>/dev/null || true)

[[ ! -f "$TRANSCRIPT" ]] && exit 0

# Extract files modified by Claude and find their git repo
RESULT=$(python3 - "$TRANSCRIPT" <<'PYEOF'
import json, sys, os, subprocess

try:
    with open(sys.argv[1]) as f:
        raw = f.read().strip()
    try:
        messages = json.loads(raw)
    except json.JSONDecodeError:
        messages = [json.loads(line) for line in raw.splitlines() if line.strip()]

    # Collect modified files
    files = []
    last_user_msg = ""
    for msg in messages:
        if msg.get('role') == 'user':
            content = msg.get('content', '')
            if isinstance(content, str):
                last_user_msg = content
            elif isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get('type') == 'text':
                        last_user_msg = block.get('text', '')
        if msg.get('role') != 'assistant':
            continue
        for block in msg.get('content', []) if isinstance(msg.get('content'), list) else []:
            if isinstance(block, dict) and block.get('type') == 'tool_use':
                inp = block.get('input', {})
                path = inp.get('file_path', '')
                if path and os.path.isfile(path):
                    files.append(os.path.abspath(path))

    if not files:
        sys.exit(0)

    # Find the git repo from the first modified file
    repo = None
    for f in files:
        r = subprocess.run(
            ['git', '-C', os.path.dirname(f), 'rev-parse', '--show-toplevel'],
            capture_output=True, text=True
        )
        if r.returncode == 0:
            repo = r.stdout.strip()
            break

    if not repo:
        sys.exit(0)

    # Filter files that belong to this repo and have actual changes
    changed = []
    for f in files:
        if not f.startswith(repo):
            continue
        r = subprocess.run(
            ['git', '-C', repo, 'diff', '--name-only', f],
            capture_output=True, text=True
        )
        if r.stdout.strip():
            changed.append(f)
        # Also check untracked
        r2 = subprocess.run(
            ['git', '-C', repo, 'ls-files', '--others', '--exclude-standard', f],
            capture_output=True, text=True
        )
        if r2.stdout.strip():
            changed.append(f)

    if not changed:
        sys.exit(0)

    # Build commit message from last user prompt
    task = last_user_msg.strip().splitlines()[0][:72] if last_user_msg.strip() else ''
    file_names = ', '.join(sorted({os.path.basename(f) for f in changed})[:4])
    if task:
        msg = f"{task[:50]} [{file_names}]"
    else:
        msg = f"chore: update {file_names}"

    print(repo)
    print(msg)
    for f in changed:
        print(f"FILE:{f}")

except Exception as e:
    pass
PYEOF
)

[[ -z "$RESULT" ]] && exit 0

REPO_DIR=$(echo "$RESULT" | sed -n '1p')
COMMIT_MSG=$(echo "$RESULT" | sed -n '2p')
FILES=$(echo "$RESULT" | grep '^FILE:' | sed 's/^FILE://')

[[ -z "$REPO_DIR" || -z "$FILES" ]] && exit 0

# Stage only the files Claude touched
while IFS= read -r file; do
    git -C "$REPO_DIR" add "$file"
done <<< "$FILES"

# Check there's actually something staged
git -C "$REPO_DIR" diff --cached --quiet && exit 0

git -C "$REPO_DIR" commit -m "$COMMIT_MSG"
echo "[git-autocommit] Committed: $COMMIT_MSG" >&2
