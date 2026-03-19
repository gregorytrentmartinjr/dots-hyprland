#!/usr/bin/env bash
# =============================================================================
# init-qs.sh — Initialize Python venv if needed, then launch Quickshell
# Place at: ~/.config/hypr/scripts/init-qs.sh
# Called from execs.conf: exec-once = bash ~/.config/hypr/scripts/init-qs.sh
# =============================================================================

VENV_PATH="$HOME/.local/state/quickshell/.venv"
DOTFILES_DIR="$HOME/dots-hyprland"
REQUIREMENTS="$DOTFILES_DIR/sdata/uv/requirements.txt"

# Create venv if it doesn't exist or is incomplete
if [[ ! -f "$VENV_PATH/bin/python" ]]; then
    mkdir -p "$(dirname "$VENV_PATH")"

    if command -v uv &>/dev/null && [[ -f "$REQUIREMENTS" ]]; then
        uv venv "$VENV_PATH"
        uv pip install --python "$VENV_PATH/bin/python" -r "$REQUIREMENTS"
    fi
fi

# Export for this session and all child processes
export ILLOGICAL_IMPULSE_VIRTUAL_ENV="$VENV_PATH"

# Write to fish config for future sessions if not already there
FISH_CONF="$HOME/.config/fish/conf.d/illogical-impulse-venv.fish"
if [[ ! -f "$FISH_CONF" ]] || ! grep -q "ILLOGICAL_IMPULSE_VIRTUAL_ENV" "$FISH_CONF"; then
    mkdir -p "$(dirname "$FISH_CONF")"
    echo "set -gx ILLOGICAL_IMPULSE_VIRTUAL_ENV '$VENV_PATH'" > "$FISH_CONF"
fi

# Launch Quickshell
exec qs -c ii
