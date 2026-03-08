# This script is meant to be sourced.
# It's not for directly running.

function prepare_systemd_user_service(){
  if [[ ! -e "/usr/lib/systemd/user/ydotool.service" ]]; then
    x sudo ln -s /usr/lib/systemd/{system,user}/ydotool.service
  fi
}

function setup_user_group(){
  if [[ -z $(getent group i2c) ]] && [[ "$OS_GROUP_ID" != "fedora" ]]; then
    # On Fedora this is not needed. Tested with desktop computer with NVIDIA video card.
    x sudo groupadd i2c
  fi

  if [[ "$OS_GROUP_ID" == "fedora" ]]; then
    x sudo usermod -aG video,input "$(whoami)"
  else
    x sudo usermod -aG video,i2c,input "$(whoami)"
  fi
}

function setup_sddm_bg_polkit(){
  # Install polkit policy and rule so wallpaper changes can update SDDM background without a password
  local helper_src="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/scripts/colors/sddm-bg-helper.sh"
  x sudo cp "$helper_src" /usr/local/bin/sddm-bg-helper
  x sudo chmod 755 /usr/local/bin/sddm-bg-helper
  x sudo cp "${REPO_ROOT}/sdata/polkit/org.illogicalimpulse.sddm-bg.policy" /usr/share/polkit-1/actions/
  x sudo cp "${REPO_ROOT}/sdata/polkit/50-sddm-bg.rules" /usr/share/polkit-1/rules.d/
}

function setup_power_key_polkit(){
  # Install helper script and polkit policy/rule so the settings panel can change HandlePowerKey without a password
  x sudo cp "${REPO_ROOT}/sdata/polkit/power-key-helper.sh" /usr/local/bin/power-key-helper
  x sudo chmod 755 /usr/local/bin/power-key-helper
  x sudo cp "${REPO_ROOT}/sdata/polkit/org.illogicalimpulse.power-key.policy" /usr/share/polkit-1/actions/
  x sudo cp "${REPO_ROOT}/sdata/polkit/50-power-key.rules" /usr/share/polkit-1/rules.d/
  # Create default logind drop-in if it doesn't exist yet
  if [[ ! -f "/etc/systemd/logind.conf.d/10-power-key.conf" ]]; then
    x sudo mkdir -p /etc/systemd/logind.conf.d
    x sudo tee /etc/systemd/logind.conf.d/10-power-key.conf > /dev/null << 'EOF'
[Login]
HandlePowerKey=suspend
EOF
  fi
}

function setup_kill_fprintd_service(){
  # Fix fingerprint bug when sleeping
  # Fprintd waits 30 seconds after a successful login before quitting, so sleeping during that time period may cause fprintd to break.
  if [[ ! -f "/etc/systemd/system/kill-fprintd.service" ]]; then
    x sudo tee /etc/systemd/system/kill-fprintd.service > /dev/null << 'EOF'
[Unit]
Description=Kill fprintd before sleep
Before=sleep.target

[Service]
ExecStart=killall fprintd

[Install]
WantedBy=sleep.target
EOF
  fi
}
#####################################################################################
# These python packages are installed using uv into the venv (virtual environment). Once the folder of the venv gets deleted, they are all gone cleanly. So it's considered as setups, not dependencies.
showfun install-python-packages
v install-python-packages

showfun setup_user_group
v setup_user_group

showfun setup_sddm_bg_polkit
v setup_sddm_bg_polkit

if [[ ! -z $(systemctl --version) ]]; then
  # For Fedora, uinput is required for the virtual keyboard to function, and udev rules enable input group users to utilize it.
  if [[ "$OS_GROUP_ID" == "fedora" ]]; then
    v bash -c "echo uinput | sudo tee /etc/modules-load.d/uinput.conf"
    v bash -c 'echo SUBSYSTEM==\"misc\", KERNEL==\"uinput\", MODE=\"0660\", GROUP=\"input\" | sudo tee /etc/udev/rules.d/99-uinput.rules'
  else
    v bash -c "echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf"
  fi
  # TODO: find a proper way for enable Nix installed ydotool. When running `systemctl --user enable ydotool, it errors "Failed to enable unit: Unit ydotool.service does not exist".
  if [[ ! "${INSTALL_VIA_NIX}" == true ]]; then
    if [[ "$OS_GROUP_ID" == "fedora" ]]; then
      v prepare_systemd_user_service
    fi
    # When $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR are empty, it commonly means that the current user has been logged in with `su - user` or `ssh user@hostname`. In such case `systemctl --user enable <service>` is not usable. It should be `sudo systemctl --machine=$(whoami)@.host --user enable <service>` instead.
    if [[ ! -z "${DBUS_SESSION_BUS_ADDRESS}" ]]; then
      v systemctl --user enable ydotool --now
    else
      v sudo systemctl --machine=$(whoami)@.host --user enable ydotool --now
    fi
  fi
  v sudo systemctl enable bluetooth --now
  # Install power button helper and polkit policy
  showfun setup_power_key_polkit
  v setup_power_key_polkit
  # Fix fingerprint bug when sleeping by killing fprintd before sleep
  showfun setup_kill_fprintd_service
  v setup_kill_fprintd_service
  v sudo systemctl enable kill-fprintd.service
elif [[ ! -z $(openrc --version) ]]; then
  v bash -c "echo 'modules=i2c-dev' | sudo tee -a /etc/conf.d/modules"
  v sudo rc-update add modules boot
  v sudo rc-update add ydotool default
  v sudo rc-update add bluetooth default

  x sudo rc-service ydotool start
  x sudo rc-service bluetooth start
else
  printf "${STY_RED}"
  printf "====================INIT SYSTEM NOT FOUND====================\n"
  printf "${STY_RST}"
  pause
fi

if [[ "$OS_GROUP_ID" == "gentoo" ]]; then
  v sudo chown -R $(whoami):$(whoami) ~/.local/
fi

v gsettings set org.gnome.desktop.interface font-name 'Google Sans Flex Medium 11 @opsz=11,wght=500'
v gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Optional: Limine + Snapper automatic backup setup (Arch, btrfs, UEFI only)
function setup_limine_snapper(){
  local ROOT_FSTYPE
  ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "")
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    echo -e "${STY_YELLOW}[$0]: Limine + Snapper setup is only supported on Arch Linux. Skipping.${STY_RST}"
    return 0
  fi
  if [[ ! -d /sys/firmware/efi ]]; then
    echo -e "${STY_YELLOW}[$0]: System is not booted in UEFI mode. Skipping limine + snapper setup.${STY_RST}"
    return 0
  fi
  if [[ "$ROOT_FSTYPE" != "btrfs" ]]; then
    echo -e "${STY_YELLOW}[$0]: Root filesystem is not btrfs (found: ${ROOT_FSTYPE:-unknown}). Skipping limine + snapper setup.${STY_RST}"
    return 0
  fi
  echo -e "${STY_CYAN}[$0]: Your system qualifies for limine + snapper automatic backup setup.${STY_RST}"
  echo "  This will:"
  echo "    - Replace your current bootloader with limine"
  echo "    - Configure snapper for automatic btrfs snapshots (20% space, max 5)"
  echo "    - Add snapshot entries to the limine boot menu"
  echo ""
  local p
  read -rp "Set up limine + snapper? [y/N] " p
  if [[ "$p" =~ ^[Yy]$ ]]; then
    x sudo bash "${REPO_ROOT}/scripts/limine-snapper/setup-limine-snapper.sh"
  else
    echo -e "${STY_BLUE}[$0]: Skipping limine + snapper setup.${STY_RST}"
  fi
}
showfun setup_limine_snapper
v setup_limine_snapper
