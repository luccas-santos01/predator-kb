#!/usr/bin/env bash
# predator-kb - uninstaller. Removes the facer driver and restores the kernel's acer_wmi.
set -uo pipefail

FACER_VER=0.2
BIN_DIR="$HOME/.local/bin"

[[ $EUID -ne 0 ]] || { echo "run as your normal user (no sudo)"; exit 1; }

echo ">>> Removing the module"
sudo dkms remove -m facer -v $FACER_VER --all 2>/dev/null || true
sudo rm -rf "/usr/src/facer-$FACER_VER"
sudo rm -f /etc/modprobe.d/facer.conf /etc/modules-load.d/facer.conf
sudo rm -f /usr/lib/systemd/system-sleep/predator-kb
sudo modprobe -r facer 2>/dev/null || true
sudo modprobe acer_wmi 2>/dev/null || true

echo ">>> Removing the CLI and the user service"
systemctl --user disable --now predator-kb-restore.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/predator-kb-restore.service"
systemctl --user daemon-reload
rm -f "$BIN_DIR/predator-kb"

echo ">>> Removing the Omarchy integration"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
BINDINGS="$HOME/.config/hypr/bindings.lua"
for f in "$MENU" "$BINDINGS"; do
  [[ -f $f ]] || continue
  if grep -q 'predator-kb:begin' "$f"; then
    cp "$f" "$f.bak.$(date +%s)"
    sed -i '/predator-kb:begin/,/predator-kb:end/d' "$f"
    echo "    cleaned: $f (backup alongside it)"
  fi
done
command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1

echo
echo "Done. Your settings in ~/.config/predator-kb/ were kept;"
echo "remove them with: rm -rf ~/.config/predator-kb"
