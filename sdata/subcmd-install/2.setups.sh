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
function detect_gpu_vendors(){
  # Returns space-separated list of: nvidia amd intel vm
  local vendors=()

  # Check for VM/virtual GPU first
  if [[ -d /sys/class/dmi/id ]]; then
    local sys_vendor
    sys_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "")
    case "$sys_vendor" in
      *QEMU*|*VirtualBox*|*VMware*|*Microsoft*|*Parallels*|*Xen*)
        vendors+=(vm)
        ;;
    esac
  fi

  # Check PCI devices for GPU vendors
  if command -v lspci >/dev/null 2>&1; then
    local gpu_lines
    gpu_lines=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)
    if echo "$gpu_lines" | grep -qi 'nvidia'; then
      vendors+=(nvidia)
    fi
    if echo "$gpu_lines" | grep -qi 'amd\|ati\|radeon'; then
      vendors+=(amd)
    fi
    if echo "$gpu_lines" | grep -qi 'intel'; then
      vendors+=(intel)
    fi
  else
    # Fallback: check sysfs vendor IDs
    for d in /sys/class/drm/card*/device; do
      [[ -r "$d/vendor" ]] || continue
      local vid
      vid=$(<"$d/vendor")
      case "$vid" in
        0x10de) [[ ! " ${vendors[*]} " =~ " nvidia " ]] && vendors+=(nvidia);;
        0x1002) [[ ! " ${vendors[*]} " =~ " amd " ]] && vendors+=(amd);;
        0x8086) [[ ! " ${vendors[*]} " =~ " intel " ]] && vendors+=(intel);;
      esac
    done
  fi

  echo "${vendors[*]}"
}

function setup_gpu_drivers(){
  local vendors
  vendors=$(detect_gpu_vendors)

  if [[ -z "$vendors" ]]; then
    echo -e "${STY_YELLOW}[$0]: No GPU detected. Skipping driver installation.${STY_RST}"
    return 0
  fi

  echo -e "${STY_CYAN}[$0]: Detected GPU vendor(s): ${vendors}${STY_RST}"

  for vendor in $vendors; do
    case "$vendor" in
      nvidia)
        echo -e "${STY_CYAN}[$0]: Installing NVIDIA drivers...${STY_RST}"
        case "$OS_GROUP_ID" in
          arch)
            # nvidia-dkms works across kernels; nvidia-utils for OpenGL, nvidia-settings for GUI config
            x sudo pacman -S --needed --noconfirm nvidia-dkms nvidia-utils nvidia-settings egl-wayland
            # Enable DRM kernel mode setting for Wayland
            if ! grep -q 'nvidia_drm.modeset=1' /etc/default/grub 2>/dev/null && [[ -f /etc/default/grub ]]; then
              echo -e "${STY_YELLOW}[$0]: NOTE: You may need to add 'nvidia_drm.modeset=1' to your kernel parameters for Wayland.${STY_RST}"
            fi
            # Ensure nvidia modules load early
            local mconf="/etc/modprobe.d/nvidia.conf"
            if [[ ! -f "$mconf" ]]; then
              echo -e "${STY_CYAN}[$0]: Creating modprobe config for early nvidia module loading...${STY_RST}"
              x sudo tee "$mconf" > /dev/null <<'NVIDIAEOF'
options nvidia_drm modeset=1 fbdev=1
NVIDIAEOF
            fi
            ;;
          fedora)
            # Use RPM Fusion for NVIDIA on Fedora
            if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
              echo -e "${STY_YELLOW}[$0]: RPM Fusion (nonfree) is needed for NVIDIA drivers.${STY_RST}"
              x sudo dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
            fi
            x sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda nvidia-vaapi-driver
            ;;
          gentoo)
            echo -e "${STY_YELLOW}[$0]: For NVIDIA on Gentoo, please ensure your kernel config and USE flags are set.${STY_RST}"
            echo -e "${STY_YELLOW}[$0]: See: https://wiki.gentoo.org/wiki/NVIDIA/nvidia-drivers${STY_RST}"
            x sudo emerge --noreplace x11-drivers/nvidia-drivers
            ;;
          *)
            echo -e "${STY_YELLOW}[$0]: NVIDIA detected but no automatic driver install for OS_GROUP_ID=${OS_GROUP_ID}.${STY_RST}"
            echo -e "${STY_YELLOW}[$0]: Please install NVIDIA drivers manually.${STY_RST}"
            ;;
        esac
        ;;
      amd)
        echo -e "${STY_CYAN}[$0]: Installing AMD GPU drivers...${STY_RST}"
        case "$OS_GROUP_ID" in
          arch)
            x sudo pacman -S --needed --noconfirm mesa vulkan-radeon libva-mesa-driver
            ;;
          fedora)
            x sudo dnf install -y mesa-dri-drivers mesa-vulkan-drivers mesa-va-drivers
            ;;
          gentoo)
            echo -e "${STY_YELLOW}[$0]: For AMD on Gentoo, ensure VIDEO_CARDS=\"amdgpu radeonsi\" in make.conf.${STY_RST}"
            x sudo emerge --noreplace media-libs/mesa
            ;;
          *)
            echo -e "${STY_YELLOW}[$0]: AMD GPU detected but no automatic driver install for OS_GROUP_ID=${OS_GROUP_ID}.${STY_RST}"
            ;;
        esac
        ;;
      intel)
        echo -e "${STY_CYAN}[$0]: Installing Intel GPU drivers...${STY_RST}"
        case "$OS_GROUP_ID" in
          arch)
            x sudo pacman -S --needed --noconfirm mesa vulkan-intel intel-media-driver
            ;;
          fedora)
            x sudo dnf install -y mesa-dri-drivers mesa-vulkan-drivers intel-media-driver
            ;;
          gentoo)
            echo -e "${STY_YELLOW}[$0]: For Intel on Gentoo, ensure VIDEO_CARDS=\"intel\" in make.conf.${STY_RST}"
            x sudo emerge --noreplace media-libs/mesa
            ;;
          *)
            echo -e "${STY_YELLOW}[$0]: Intel GPU detected but no automatic driver install for OS_GROUP_ID=${OS_GROUP_ID}.${STY_RST}"
            ;;
        esac
        ;;
      vm)
        echo -e "${STY_CYAN}[$0]: Virtual machine detected. Installing VM display drivers...${STY_RST}"
        case "$OS_GROUP_ID" in
          arch)
            x sudo pacman -S --needed --noconfirm mesa xf86-video-vmware
            ;;
          fedora)
            x sudo dnf install -y mesa-dri-drivers xorg-x11-drv-vmware
            ;;
          gentoo)
            x sudo emerge --noreplace media-libs/mesa
            ;;
          *)
            echo -e "${STY_YELLOW}[$0]: VM detected but no automatic driver install for OS_GROUP_ID=${OS_GROUP_ID}.${STY_RST}"
            ;;
        esac
        ;;
    esac
  done
}

#####################################################################################
# These python packages are installed using uv into the venv (virtual environment). Once the folder of the venv gets deleted, they are all gone cleanly. So it's considered as setups, not dependencies.
if [[ "${SKIP_GPUDRIVERS}" != true ]]; then
  showfun setup_gpu_drivers
  v setup_gpu_drivers
fi

showfun install-python-packages
v install-python-packages

showfun setup_user_group
v setup_user_group

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
    x sudo bash "${REPO_ROOT}/scripts/limine-snapper/setup-limine-snapper.sh" --yes
  else
    echo -e "${STY_BLUE}[$0]: Skipping limine + snapper setup.${STY_RST}"
  fi
}
showfun setup_limine_snapper
v setup_limine_snapper
