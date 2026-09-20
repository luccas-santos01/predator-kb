#!/usr/bin/env bash
# predator-kb - desinstalador. Remove o driver facer e devolve o acer_wmi do kernel.
set -uo pipefail

FACER_VER=0.2
BIN_DIR="$HOME/.local/bin"

[[ $EUID -ne 0 ]] || { echo "rode como seu usuario normal (sem sudo)"; exit 1; }

echo ">>> Removendo o modulo"
sudo dkms remove -m facer -v $FACER_VER --all 2>/dev/null || true
sudo rm -rf "/usr/src/facer-$FACER_VER"
sudo rm -f /etc/modprobe.d/facer.conf /etc/modules-load.d/facer.conf
sudo rm -f /usr/lib/systemd/system-sleep/predator-kb
sudo modprobe -r facer 2>/dev/null || true
sudo modprobe acer_wmi 2>/dev/null || true

echo ">>> Removendo a CLI e o servico"
systemctl --user disable --now predator-kb-restore.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/predator-kb-restore.service"
systemctl --user daemon-reload
rm -f "$BIN_DIR/predator-kb"

echo ">>> Removendo a integracao com o Omarchy"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
BINDINGS="$HOME/.config/hypr/bindings.lua"
for f in "$MENU" "$BINDINGS"; do
  [[ -f $f ]] || continue
  if grep -q 'predator-kb' "$f"; then
    cp "$f" "$f.bak.$(date +%s)"
    sed -i '/predator-kb:begin/,/predator-kb:end/d' "$f"
    echo "    limpo: $f (backup ao lado)"
  fi
done
command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1

echo
echo "Feito. Suas configuracoes em ~/.config/predator-kb/ foram mantidas;"
echo "apague com: rm -rf ~/.config/predator-kb"
