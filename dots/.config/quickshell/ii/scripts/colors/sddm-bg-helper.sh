#!/usr/bin/env bash
# Helper script for copying wallpaper to SDDM theme directory.
# Intended to be run via pkexec with a matching polkit rule that
# allows passwordless execution.
#
# Usage: sddm-bg-helper.sh <source> <dest>

set -euo pipefail

src="$1"
dest="$2"
dest_dir="$(dirname "$dest")"

# Validate paths
[[ "$dest_dir" == /usr/share/sddm/themes/*/assets/backgrounds ]] || exit 1
[[ -f "$src" ]] || exit 1

mkdir -p "$dest_dir"
cp "$src" "$dest"
chmod 644 "$dest"
