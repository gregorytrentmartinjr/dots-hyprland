#!/usr/bin/env bash
# auto_scale.sh - Automatically set display scaling so that every monitor
# provides the same effective DPI as a 32-inch 3840x2160 display at 1.5x scale.
#
# Reference effective (logical) PPI:
#   physical_ppi = sqrt(3840² + 2160²) / 32 ≈ 137.68
#   logical_ppi  = 137.68 / 1.5            ≈ 91.79
#
# For each connected monitor the script reads the EDID from sysfs to obtain
# the physical panel size, computes the native PPI, and derives:
#   scale = native_ppi / 91.79
# The result is rounded to the nearest 0.25 and clamped to [1.0, 3.0].

REFERENCE_LOGICAL_PPI=91.79

# ---------------------------------------------------------------------------
# Read a single byte from a binary file at a given offset and print its
# decimal value.  Works with either xxd or od.
# ---------------------------------------------------------------------------
read_edid_byte() {
    local file="$1" offset="$2"
    if command -v xxd &>/dev/null; then
        printf "%d" "0x$(xxd -p -l 1 -s "$offset" "$file")"
    else
        od -A n -t u1 -j "$offset" -N 1 "$file" | tr -d ' '
    fi
}

# ---------------------------------------------------------------------------
# Locate the sysfs EDID file for a given DRM connector name.
# Hyprland names like "eDP-1" map to sysfs entries like "card0-eDP-1".
# ---------------------------------------------------------------------------
find_edid_for_connector() {
    local connector="$1"
    for path in /sys/class/drm/card*-"${connector}"/edid; do
        if [ -f "$path" ] && [ -s "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
apply_auto_scale() {
    local monitors
    monitors=$(hyprctl monitors -j 2>/dev/null) || {
        echo "auto_scale: hyprctl not available" >&2
        return 1
    }

    echo "$monitors" | jq -c '.[]' | while read -r mon; do
        local name width height
        name=$(echo "$mon" | jq -r '.name')
        width=$(echo "$mon" | jq -r '.width')
        height=$(echo "$mon" | jq -r '.height')

        # Locate EDID in sysfs
        local edid_file
        edid_file=$(find_edid_for_connector "$name") || {
            echo "auto_scale: no EDID for $name, skipping" >&2
            continue
        }

        # EDID base block bytes 21-22: max horizontal / vertical size in cm
        local h_cm v_cm
        h_cm=$(read_edid_byte "$edid_file" 21)
        v_cm=$(read_edid_byte "$edid_file" 22)

        if [ "$h_cm" -eq 0 ] || [ "$v_cm" -eq 0 ]; then
            echo "auto_scale: invalid physical size for $name (${h_cm}x${v_cm} cm), skipping" >&2
            continue
        fi

        # Compute scale
        local scale
        scale=$(awk -v w="$width" -v h="$height" \
                    -v hcm="$h_cm" -v vcm="$v_cm" \
                    -v ref="$REFERENCE_LOGICAL_PPI" '
            BEGIN {
                diag_cm = sqrt(hcm*hcm + vcm*vcm)
                diag_in = diag_cm / 2.54
                ppi     = sqrt(w*w + h*h) / diag_in
                scale   = ppi / ref

                # Round to nearest 0.25
                scale = int(scale * 4 + 0.5) / 4

                # Clamp to [1.0, 3.0]
                if (scale < 1.0) scale = 1.0
                if (scale > 3.0) scale = 3.0

                printf "%.2f", scale
            }')

        echo "auto_scale: $name ${width}x${height} (${h_cm}x${v_cm} cm) -> scale $scale"
        hyprctl keyword monitor "$name,preferred,auto,$scale"
    done
}

apply_auto_scale
