#!/usr/bin/env bash
# notify.sh — Claude Code Stop hook
# Sends a notification when Claude finishes a task.
#
# Backends (set the env vars for the ones you want, combine freely):
#
#   Desktop  — automatic if $DISPLAY or $WAYLAND_DISPLAY is set (no config needed)
#              Linux: requires notify-send (apt install libnotify-bin)
#              macOS: uses osascript (built-in)
#              Windows: uses PowerShell toast (built-in)
#
#   Discord  — set CLAUDE_DISCORD_WEBHOOK to your webhook URL
#
# Add to ~/.bashrc or ~/.zshrc:
#   export CLAUDE_DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."

set -euo pipefail

INPUT=$(cat)

TRANSCRIPT=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('transcript_path', ''))
except Exception:
    pass
" 2>/dev/null || true)

TITLE="Claude Code — Done"
BODY="Task complete"

# Parse transcript to list edited files
if [[ -f "$TRANSCRIPT" ]]; then
    BODY=$(python3 - "$TRANSCRIPT" <<'PYEOF'
import json, sys, os
try:
    with open(sys.argv[1]) as f:
        raw = f.read().strip()
    try:
        messages = json.loads(raw)
    except json.JSONDecodeError:
        messages = [json.loads(line) for line in raw.splitlines() if line.strip()]

    files = set()
    for msg in messages:
        if msg.get('role') != 'assistant':
            continue
        content = msg.get('content', [])
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'tool_use':
                path = block.get('input', {}).get('file_path', '')
                if path:
                    files.add(os.path.basename(path))

    if files:
        names = ', '.join(sorted(files)[:5])
        extra = f' (+{len(files)-5} more)' if len(files) > 5 else ''
        print(f'{len(files)} file(s) edited: {names}{extra}')
    else:
        print('Task complete — no files modified')
except Exception:
    print('Task complete')
PYEOF
    )
fi

# ── Backend: Desktop notification ────────────────────────────────────────────
if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    case "$(uname -s)" in
        Linux)
            command -v notify-send &>/dev/null && \
                notify-send \
                    --icon=dialog-information \
                    --app-name="Claude Code" \
                    --expire-time=6000 \
                    "$TITLE" "$BODY" || true
            ;;
        Darwin)
            osascript -e "display notification \"$BODY\" with title \"$TITLE\" sound name \"Glass\""
            ;;
        MINGW*|CYGWIN*|MSYS*)
            powershell.exe -NoProfile -Command "
\$xml = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]::GetTemplateContent('ToastText02')
\$xml.GetElementsByTagName('text')[0].InnerText = '$TITLE'
\$xml.GetElementsByTagName('text')[1].InnerText = '$BODY'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show(
    [Windows.UI.Notifications.ToastNotification]::new(\$xml)
)" 2>/dev/null || true
            ;;
    esac
fi

# ── Backend: Discord webhook ──────────────────────────────────────────────────
if [[ -n "${CLAUDE_DISCORD_WEBHOOK:-}" ]]; then
    python3 - <<PYEOF
import json, subprocess, os

title = os.environ.get('CLAUDE_NOTIFY_TITLE', '$TITLE')
body  = """$BODY"""

payload = json.dumps({
    "embeds": [{
        "title": title,
        "description": body,
        "color": 5763719,
        "footer": {"text": "$(hostname)"},
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }]
})

subprocess.run(
    ["curl", "-s", "-X", "POST", "$CLAUDE_DISCORD_WEBHOOK",
     "-H", "Content-Type: application/json", "-d", payload],
    stdout=subprocess.DEVNULL
)
PYEOF
fi
