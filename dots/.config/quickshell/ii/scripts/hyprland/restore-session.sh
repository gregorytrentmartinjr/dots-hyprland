#!/usr/bin/env bash
# Restore a previously saved Hyprland session.
# Reads the session file and relaunches each application on its
# original workspace using per-exec window rules to avoid conflicts.

SESSION_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland-session.json"
export SESSION_FILE

if [[ ! -f "$SESSION_FILE" ]]; then
    echo "No session file found at $SESSION_FILE"
    exit 0
fi

count=$(python3 -c "import json; print(len(json.load(open('$SESSION_FILE'))))" 2>/dev/null)
if [[ "$count" == "0" || -z "$count" ]]; then
    echo "Empty session, nothing to restore"
    exit 0
fi

echo "Restoring $count windows..."

python3 -c '
import json, subprocess, shlex, os, sys

session_file = os.environ["SESSION_FILE"]
with open(session_file) as f:
    windows = json.load(f)

for w in windows:
    cmd = w.get("command", [])
    if not cmd:
        continue

    cls = w.get("class", "")
    workspace = w.get("workspace", 1)
    floating = w.get("floating", False)
    at = w.get("at", [0, 0])
    size = w.get("size", [0, 0])
    fullscreen = w.get("fullscreen", 0)

    # Build per-exec rule string (avoids global windowrulev2 conflicts)
    rules = []
    if workspace and workspace > 0:
        rules.append(f"workspace {workspace} silent")
    if floating:
        rules.append("float")
        if size[0] > 0 and size[1] > 0:
            rules.append(f"size {size[0]} {size[1]}")
        if at[0] >= 0 and at[1] >= 0:
            rules.append(f"move {at[0]} {at[1]}")
    if fullscreen == 1:
        rules.append("fullscreen")
    elif fullscreen == 2:
        rules.append("maximize")

    shell_cmd = " ".join(shlex.quote(a) for a in cmd)

    # Use hyprctl dispatch exec with inline rules so each window
    # gets its own set of rules without affecting other windows
    rule_str = "; ".join(rules)
    if rule_str:
        exec_arg = f"[{rule_str}] {shell_cmd}"
    else:
        exec_arg = shell_cmd

    subprocess.run(
        ["hyprctl", "dispatch", "exec", "--", exec_arg],
        capture_output=True
    )

    print(f"  Launched: {cls} on workspace {workspace}")
' 2>&1

# Clear the session file after restoring so we don't double-restore
rm -f "$SESSION_FILE"

echo "Session restore complete"
