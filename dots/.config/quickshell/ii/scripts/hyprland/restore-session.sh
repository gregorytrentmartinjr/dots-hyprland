#!/usr/bin/env bash
# Restore a previously saved Hyprland session.
# Reads the session file and relaunches each application on its
# original workspace. Position/size are restored via window rules.

SESSION_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland-session.json"

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

session_file = os.environ.get("SESSION_FILE", os.path.expanduser("~/.local/state/hyprland-session.json"))
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

    # Add temporary window rules to place the window correctly
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

    # Apply rules for the window class
    for rule in rules:
        subprocess.run(
            ["hyprctl", "keyword", "windowrulev2", f"{rule},class:^({cls})$"],
            capture_output=True
        )

    # Launch the application
    shell_cmd = " ".join(shlex.quote(a) for a in cmd)
    subprocess.Popen(
        ["bash", "-c", f"exec {shell_cmd}"],
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    print(f"  Launched: {cls} on workspace {workspace}")
' 2>&1

# Clear temporary rules after a delay so they don't affect future windows
(sleep 10 && hyprctl reload) &

# Clear the session file after restoring so we don't double-restore
rm -f "$SESSION_FILE"

echo "Session restore complete"
