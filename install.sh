#!/usr/bin/env bash
# predator-kb - installer
#
# Builds the 'facer' driver through DKMS, installs the CLI and, on Omarchy,
# registers the menu and keybindings. Run it as your normal user - it calls
# sudo only for the privileged steps.
set -euo pipefail

FACER_REPO=https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module.git
FACER_VER=0.2
FACER_SRC=/usr/src/facer-$FACER_VER
RUN_USER=$(id -un)
REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN_DIR="$HOME/.local/bin"
WITH_OMARCHY=auto

for arg in "$@"; do
  case $arg in
    --no-omarchy) WITH_OMARCHY=no ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

say()  { printf '\n\033[1;36m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mxxx %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "run as your normal user (no sudo); the script calls sudo itself"

# --- 1. Preflight checks ---------------------------------------------------
say "1/7 Checking the hardware"

MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo unknown)
echo "    Model: $MODEL"
case $MODEL in
  Predator*|Nitro*) ;;
  *) warn "This doesn't look like an Acer Predator/Nitro. The driver may not work." ;;
esac

# Acer's gaming WMI interface
[[ -d /sys/bus/wmi/devices/7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56 ]] \
  || ls -d /sys/bus/wmi/devices/7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56-* >/dev/null 2>&1 \
  || warn "Acer gaming WMI not found; the RGB probably won't respond."

KVER=$(uname -r)
[[ -d /usr/lib/modules/$KVER/build || -d /lib/modules/$KVER/build ]] \
  || die "kernel headers for $KVER are missing. On Arch: sudo pacman -S linux-headers (or your kernel's -headers package)"

for c in dkms git make gcc; do
  command -v "$c" >/dev/null || die "'$c' not found. Install it before continuing."
done

SB_VAR=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [[ -r $SB_VAR ]]; then
  # 4 attribute bytes + 1 value byte; the last field is the one that matters.
  SB=$(od -An -t u1 "$SB_VAR" 2>/dev/null | awk 'NF{v=$NF} END{print v+0}')
  if [[ $SB == 1 ]]; then
    warn "Secure Boot is on: the module must be signed and its key enrolled in MOK."
  fi
fi

# --- 2. Driver source ------------------------------------------------------
say "2/7 Fetching the facer driver (upstream)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git clone -q --depth 1 "$FACER_REPO" "$TMP/facer"
echo "    commit $(git -C "$TMP/facer" rev-parse --short HEAD)"

say "3/7 Installing the source into $FACER_SRC"
sudo dkms remove -m facer -v $FACER_VER --all 2>/dev/null || true
sudo rm -rf "$FACER_SRC"
sudo mkdir -p "$FACER_SRC"
sudo cp -r "$TMP/facer/src" "$TMP/facer/Makefile" "$FACER_SRC"/
sudo tee "$FACER_SRC/dkms.conf" >/dev/null <<EOF
PACKAGE_NAME="facer"
PACKAGE_VERSION="$FACER_VER"
BUILT_MODULE_NAME[0]="facer"
BUILT_MODULE_LOCATION[0]="src"
DEST_MODULE_LOCATION[0]="/kernel/drivers/platform/x86"
MAKE[0]="make KERNELDIR=\${kernel_source_dir}"
AUTOINSTALL="yes"
EOF

# --- 3. DKMS ---------------------------------------------------------------
say "4/7 Building through DKMS (rebuilds itself on every new kernel)"
sudo dkms add -m facer -v $FACER_VER
sudo dkms install -m facer -v $FACER_VER --force

# --- 4. Boot and resume ----------------------------------------------------
say "5/7 Wiring up boot and resume"

# facer is a fork of acer-wmi and claims the same GUIDs; the two can't coexist.
sudo tee /etc/modprobe.d/facer.conf >/dev/null <<'EOF'
# facer replaces acer-wmi, adding the Predator's 4-zone RGB support.
blacklist acer_wmi
EOF
echo facer | sudo tee /etc/modules-load.d/facer.conf >/dev/null

# Firmware resets the backlight when waking from suspend.
sudo tee /usr/lib/systemd/system-sleep/predator-kb >/dev/null <<EOF
#!/bin/bash
[ "\$1" = "post" ] || exit 0
sleep 1
runuser -u $RUN_USER -- $BIN_DIR/predator-kb restore || true
EOF
sudo chmod +x /usr/lib/systemd/system-sleep/predator-kb

# --- 5. CLI and user service -----------------------------------------------
say "6/7 Installing the CLI and the user service"
mkdir -p "$BIN_DIR"
install -m755 "$REPO_DIR/bin/predator-kb" "$BIN_DIR/predator-kb"
echo "    $BIN_DIR/predator-kb"

mkdir -p "$HOME/.config/systemd/user"
install -m644 "$REPO_DIR/systemd/predator-kb-restore.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable predator-kb-restore.service >/dev/null
echo "    predator-kb-restore.service enabled"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH; add it to your shell rc." ;;
esac

# --- 6. Omarchy integration ------------------------------------------------
if [[ $WITH_OMARCHY == auto && -d $HOME/.config/omarchy ]]; then
  say "7/7 Setting up the Omarchy integration"
  "$REPO_DIR/omarchy/install-omarchy.sh"
else
  say "7/7 Skipping the Omarchy integration"
fi

# --- 7. Load it now --------------------------------------------------------
say "Swapping the modules now"
sudo modprobe -r acer_wmi 2>/dev/null || true
sudo modprobe -r facer 2>/dev/null || true
sudo modprobe facer
sleep 1

if [[ -w /dev/acer-gkbbl-0 && -w /dev/acer-gkbbl-static-0 ]]; then
  printf '\n\033[1;32mDone!\033[0m Try it:  predator-kb color ff0055\n\n'
else
  die "/dev/acer-gkbbl-* didn't show up. Check: sudo dmesg | tail -20"
fi
