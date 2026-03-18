#!/usr/bin/env bash
# Save current Hyprland session (open windows) for later restoration.
# Captures each client's class, workspace, position, size, and the
# command line that launched it (read from /proc/<pid>/cmdline).

SESSION_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland-session.json"
mkdir -p "$(dirname "$SESSION_FILE")"

clients_json=$(hyprctl clients -j 2>/dev/null)
if [[ -z "$clients_json" || "$clients_json" == "null" ]]; then
    echo "[]" > "$SESSION_FILE"
    exit 0
fi

# Build a JSON array of restorable windows
echo "$clients_json" | python3 -c '
import json, sys, os

clients = json.load(sys.stdin)
saved = []

# Desktop entries we should skip (shell components, not user apps)
SKIP_CLASSES = {
    "quickshell", "quickshell:session", "quickshell:bar",
    "quickshell:lock", "quickshell:osd", "quickshell:overlay",
    "", "(null)"
}

for c in clients:
    cls = c.get("class", "")
    if cls.lower() in {s.lower() for s in SKIP_CLASSES}:
        continue

    pid = c.get("pid", 0)
    if pid <= 0:
        continue

    # Read the original command line from /proc
    cmdline_path = f"/proc/{pid}/cmdline"
    try:
        with open(cmdline_path, "rb") as f:
            raw = f.read()
        args = [a.decode("utf-8", errors="replace") for a in raw.split(b"\x00") if a]
    except (FileNotFoundError, PermissionError):
        continue

    if not args:
        continue

    entry = {
        "class": cls,
        "initialClass": c.get("initialClass", cls),
        "workspace": c.get("workspace", {}).get("id", 1),
        "at": c.get("at", [0, 0]),
        "size": c.get("size", [0, 0]),
        "floating": c.get("floating", False),
        "fullscreen": c.get("fullscreen", 0),
        "command": args,
    }
    saved.append(entry)

json.dump(saved, sys.stdout, indent=2)
' > "$SESSION_FILE"

echo "Session saved to $SESSION_FILE ($(python3 -c "import json; print(len(json.load(open('$SESSION_FILE'))))" 2>/dev/null || echo '?') windows)"
