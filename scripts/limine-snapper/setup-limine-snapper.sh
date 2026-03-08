#!/usr/bin/env bash
# setup-limine-snapper.sh
# Post-install script for Arch Linux with btrfs
# Sets up limine bootloader + snapper snapshots selectable from boot menu
# Requirements: Fresh Arch install on btrfs with subvolume layout (@, @home, etc.)

set -euo pipefail

# --- Options ---
AUTO_YES=false
if [[ "${1:-}" == "--yes" ]]; then
  AUTO_YES=true
fi

# --- Configuration ---
SNAPPER_SPACE_LIMIT="0.2"       # 20% of drive
SNAPPER_NUMBER_LIMIT="5"        # Max 5 snapshots
ESP="/boot"                     # EFI System Partition mount point

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Checks ---
[[ $EUID -eq 0 ]] || error "This script must be run as root"
[[ -d /sys/firmware/efi ]] || error "System must be booted in UEFI mode"

# Verify btrfs root
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)
[[ "$ROOT_FSTYPE" == "btrfs" ]] || error "Root filesystem must be btrfs (found: $ROOT_FSTYPE)"

# Get root device and subvolume
ROOT_DEV=$(findmnt -n -o SOURCE /)
ROOT_PART=$(findmnt -n -o SOURCE -T / | sed 's/\[.*\]//')
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
ROOT_SUBVOL=$(findmnt -n -o OPTIONS / | grep -oP 'subvol=\K[^,]+')

info "Root device: $ROOT_PART"
info "Root UUID: $ROOT_UUID"
info "Root subvolume: $ROOT_SUBVOL"
info "ESP mount: $ESP"

echo ""
echo -e "${YELLOW}This will:${NC}"
echo "  1. Remove any existing bootloader (GRUB/systemd-boot)"
echo "  2. Install limine as the UEFI bootloader"
echo "  3. Install and configure snapper (20% space, max 5 snapshots)"
echo "  4. Install hooks to auto-generate limine boot entries from snapshots"
echo ""
if [[ "$AUTO_YES" != true ]]; then
  read -rp "Continue? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
fi

# --- Step 1: Remove existing bootloaders ---
info "Removing existing bootloaders..."

if pacman -Qi grub &>/dev/null; then
    pacman -Rns --noconfirm grub 2>/dev/null || true
    rm -rf "$ESP/grub" 2>/dev/null || true
    rm -f "$ESP/EFI/BOOT/grubx64.efi" 2>/dev/null || true
    info "Removed GRUB"
fi

if bootctl is-installed &>/dev/null 2>&1; then
    bootctl remove 2>/dev/null || true
    info "Removed systemd-boot"
fi

# --- Step 2: Install limine ---
info "Installing limine..."
pacman -S --needed --noconfirm limine

# Install limine EFI binary
install -Dm644 /usr/share/limine/BOOTX64.EFI "$ESP/EFI/BOOT/BOOTX64.EFI"
install -Dm644 /usr/share/limine/BOOTX64.EFI "$ESP/EFI/limine/BOOTX64.EFI"

# Detect kernel and initramfs
KERNEL=$(ls "$ESP"/vmlinuz-linux* 2>/dev/null | head -1)
INITRAMFS=$(ls "$ESP"/initramfs-linux*.img 2>/dev/null | grep -v fallback | head -1)
INITRAMFS_FB=$(ls "$ESP"/initramfs-linux*-fallback.img 2>/dev/null | head -1)

if [[ -z "$KERNEL" ]]; then
    # Kernel might be at /boot inside root, not on ESP
    # Check if ESP is /boot or separate
    if [[ "$ESP" == "/boot" ]]; then
        KERNEL="/boot/vmlinuz-linux"
        INITRAMFS="/boot/initramfs-linux.img"
        INITRAMFS_FB="/boot/initramfs-linux-fallback.img"
    else
        error "Cannot find kernel at $ESP/vmlinuz-linux*"
    fi
fi

KERNEL_BASENAME=$(basename "$KERNEL")
INITRAMFS_BASENAME=$(basename "$INITRAMFS")
INITRAMFS_FB_BASENAME=$(basename "$INITRAMFS_FB")

# Determine kernel cmdline - silent boot (no text on boot/reboot/shutdown)
CMDLINE="root=UUID=$ROOT_UUID rootflags=subvol=$ROOT_SUBVOL rw quiet loglevel=0 systemd.show_status=false rd.systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0"

# Add any existing kernel parameters
if [[ -f /etc/kernel/cmdline ]]; then
    EXTRA_ARGS=$(cat /etc/kernel/cmdline | sed "s|root=[^ ]*||g; s|rootflags=[^ ]*||g; s|rw||g; s|quiet||g; s|loglevel=[^ ]*||g; s|systemd\.show_status=[^ ]*||g; s|rd\.systemd\.show_status=[^ ]*||g; s|rd\.udev\.log_level=[^ ]*||g; s|vt\.global_cursor_default=[^ ]*||g" | xargs)
    [[ -n "$EXTRA_ARGS" ]] && CMDLINE="$CMDLINE $EXTRA_ARGS"
fi

info "Writing limine.conf..."
cat > "$ESP/limine.conf" <<LIMINE_EOF
timeout: 5

/Arch Linux
    protocol: linux
    kernel_path: boot():///$KERNEL_BASENAME
    kernel_cmdline: $CMDLINE
    module_path: boot():///$INITRAMFS_BASENAME

/Arch Linux (Fallback)
    protocol: linux
    kernel_path: boot():///$KERNEL_BASENAME
    kernel_cmdline: $CMDLINE
    module_path: boot():///$INITRAMFS_FB_BASENAME

# --- Snapper Snapshots (auto-generated below) ---
# SNAPPER_ENTRIES_START
# SNAPPER_ENTRIES_END
LIMINE_EOF

info "Limine installed and configured"

# --- Step 3: Install and configure snapper ---
info "Installing snapper..."
pacman -S --needed --noconfirm snapper snap-pac

# If /.snapshots is already a subvolume mounted, unmount and remove for snapper to manage
if findmnt /.snapshots &>/dev/null; then
    umount /.snapshots 2>/dev/null || true
fi

if btrfs subvolume show /.snapshots &>/dev/null 2>&1; then
    btrfs subvolume delete /.snapshots 2>/dev/null || true
fi
rmdir /.snapshots 2>/dev/null || true

# Create snapper config for root
if snapper -c root list &>/dev/null 2>&1; then
    warn "Snapper config 'root' already exists, reconfiguring..."
else
    snapper -c root create-config /
fi

# snapper creates its own .snapshots subvolume, but we may want to manage it ourselves
# For snapshot booting, we need /.snapshots accessible

# Configure snapper limits
info "Configuring snapper (20% space limit, max 5 snapshots)..."
snapper -c root set-config "SPACE_LIMIT=$SNAPPER_SPACE_LIMIT"
snapper -c root set-config "NUMBER_LIMIT=$SNAPPER_NUMBER_LIMIT"
snapper -c root set-config "NUMBER_LIMIT_IMPORTANT=$SNAPPER_NUMBER_LIMIT"

# Timeline snapshots - enable with conservative settings
snapper -c root set-config "TIMELINE_CREATE=yes"
snapper -c root set-config "TIMELINE_CLEANUP=yes"
snapper -c root set-config "TIMELINE_MIN_AGE=1800"
snapper -c root set-config "TIMELINE_LIMIT_HOURLY=2"
snapper -c root set-config "TIMELINE_LIMIT_DAILY=3"
snapper -c root set-config "TIMELINE_LIMIT_WEEKLY=0"
snapper -c root set-config "TIMELINE_LIMIT_MONTHLY=0"
snapper -c root set-config "TIMELINE_LIMIT_YEARLY=0"

# Enable snapper timers
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

info "Snapper configured"

# --- Step 4: Install limine-snapper entry generator ---
info "Installing limine-snapper entry generator..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install -Dm755 "$SCRIPT_DIR/limine-snapper-update.sh" /usr/local/bin/limine-snapper-update

# Install pacman hooks
install -Dm644 "$SCRIPT_DIR/hooks/90-limine-snapper.hook" /etc/pacman.d/hooks/90-limine-snapper.hook
install -Dm644 "$SCRIPT_DIR/hooks/60-limine-kernel.hook" /etc/pacman.d/hooks/60-limine-kernel.hook

# Run the generator once to populate entries
/usr/local/bin/limine-snapper-update

# --- Step 5: Create initial snapshot ---
info "Creating initial snapshot..."
snapper -c root create --description "Fresh install" --type single

# Regenerate limine entries with the new snapshot
/usr/local/bin/limine-snapper-update

# --- Step 6: Install pixie-sddm theme ---
info "Installing pixie-sddm theme..."
pacman -S --needed --noconfirm git sddm

PIXIE_TMPDIR=$(mktemp -d)
trap 'rm -rf "$PIXIE_TMPDIR" "$TMPFILE"' EXIT
git clone https://github.com/gregorytrentmartinjr/pixie-sddm.git "$PIXIE_TMPDIR"

PIXIE_THEME_DIR="/usr/share/sddm/themes/pixie"
rm -rf "$PIXIE_THEME_DIR" 2>/dev/null || true
mkdir -p "$PIXIE_THEME_DIR"
cp -r "$PIXIE_TMPDIR"/{assets,components,Main.qml,metadata.desktop,theme.conf,LICENSE} "$PIXIE_THEME_DIR/"
chmod -R 755 "$PIXIE_THEME_DIR"

# Apply as active SDDM theme
mkdir -p /etc/sddm.conf.d
echo -e "[Theme]\nCurrent=pixie" > /etc/sddm.conf.d/theme.conf

# Enable SDDM
systemctl enable sddm

info "Pixie SDDM theme installed and applied"

# --- Step 7: Configure silent boot/reboot/shutdown ---
info "Configuring silent boot (no verbose text)..."

# Suppress systemd startup/shutdown messages
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/silent-boot.conf <<'SILENT_EOF'
[Manager]
ShowStatus=no
StatusUnitFormat=
SILENT_EOF

# Suppress getty login prompt messages on TTY
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/silent.conf <<'GETTY_EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --skip-login --nonewline --noissue --noclear --login-options "-f root" %I $TERM
GETTY_EOF

# Suppress fsck messages during boot
if [[ ! -f /etc/sysctl.d/20-quiet-printk.conf ]]; then
    echo "kernel.printk = 3 3 3 3" > /etc/sysctl.d/20-quiet-printk.conf
fi

info "Silent boot configured"

info "Setup complete!"
echo ""
echo -e "${GREEN}Summary:${NC}"
echo "  Bootloader: limine (UEFI, silent boot)"
echo "  Snapshots:  snapper (root config)"
echo "  Space limit: 20% of drive"
echo "  Max snapshots: 5"
echo "  SDDM theme: pixie-sddm"
echo "  Config: $ESP/limine.conf"
echo "  Generator: /usr/local/bin/limine-snapper-update"
echo ""
echo "  Pacman hooks installed - snapshot entries auto-update on:"
echo "    - Kernel/initramfs updates"
echo "    - Package installs/removals (via snap-pac)"
echo ""
echo "  Silent boot: no text on boot, reboot, or shutdown"
echo ""
echo "  Run 'limine-snapper-update' manually to refresh boot entries"
echo "  Run 'snapper -c root list' to view snapshots"
echo "  Run 'snapper -c root create -d \"description\"' to create a manual snapshot"
