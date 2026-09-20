#!/usr/bin/env bash
# predator-kb - instalador
#
# Compila o driver 'facer' via DKMS, instala a CLI e (no Omarchy) registra
# o menu e os atalhos. Rode como o seu usuario normal - o script pede sudo
# apenas nas partes privilegiadas.
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
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "opcao desconhecida: $arg" >&2; exit 1 ;;
  esac
done

say()  { printf '\n\033[1;36m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mxxx %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "rode como seu usuario normal (sem sudo); o script pede sudo sozinho"

# --- 1. Verificacoes -------------------------------------------------------
say "1/7 Verificando o hardware"

MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo desconhecido)
echo "    Modelo: $MODEL"
case $MODEL in
  Predator*|Nitro*) ;;
  *) warn "Este nao parece ser um Acer Predator/Nitro. O driver pode nao funcionar." ;;
esac

# GUID da interface WMI de gaming da Acer
[[ -d /sys/bus/wmi/devices/7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56 ]] \
  || ls -d /sys/bus/wmi/devices/7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56-* >/dev/null 2>&1 \
  || warn "WMI de gaming da Acer nao encontrada; o RGB provavelmente nao vai responder."

KVER=$(uname -r)
[[ -d /usr/lib/modules/$KVER/build || -d /lib/modules/$KVER/build ]] \
  || die "headers do kernel $KVER nao instalados. No Arch: sudo pacman -S linux-headers (ou o pacote -headers do seu kernel)"

for c in dkms git make gcc; do
  command -v "$c" >/dev/null || die "'$c' nao encontrado. Instale-o antes de continuar."
done

SB_VAR=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [[ -r $SB_VAR ]]; then
  # 4 bytes de atributos + 1 byte de valor; o ultimo campo e o que importa.
  SB=$(od -An -t u1 "$SB_VAR" 2>/dev/null | awk 'NF{v=$NF} END{print v+0}')
  if [[ $SB == 1 ]]; then
    warn "Secure Boot ativo: o modulo precisa ser assinado e a chave inscrita no MOK."
  fi
fi

# --- 2. Fonte do driver ----------------------------------------------------
say "2/7 Baixando o driver facer (upstream)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git clone -q --depth 1 "$FACER_REPO" "$TMP/facer"
echo "    commit $(git -C "$TMP/facer" rev-parse --short HEAD)"

say "3/7 Instalando a fonte em $FACER_SRC"
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
say "4/7 Compilando via DKMS (recompila sozinho a cada novo kernel)"
sudo dkms add -m facer -v $FACER_VER
sudo dkms install -m facer -v $FACER_VER --force

# --- 4. Boot e resume ------------------------------------------------------
say "5/7 Configurando boot e resume"

# facer e um fork do acer-wmi e registra os mesmos GUIDs; os dois nao convivem.
sudo tee /etc/modprobe.d/facer.conf >/dev/null <<'EOF'
# facer substitui o acer-wmi, adicionando o RGB de 4 zonas do Predator.
blacklist acer_wmi
EOF
echo facer | sudo tee /etc/modules-load.d/facer.conf >/dev/null

# O firmware reseta o backlight ao acordar da suspensao.
sudo tee /usr/lib/systemd/system-sleep/predator-kb >/dev/null <<EOF
#!/bin/bash
[ "\$1" = "post" ] || exit 0
sleep 1
runuser -u $RUN_USER -- $BIN_DIR/predator-kb restore || true
EOF
sudo chmod +x /usr/lib/systemd/system-sleep/predator-kb

# --- 5. CLI e servico ------------------------------------------------------
say "6/7 Instalando a CLI e o servico de usuario"
mkdir -p "$BIN_DIR"
install -m755 "$REPO_DIR/bin/predator-kb" "$BIN_DIR/predator-kb"
echo "    $BIN_DIR/predator-kb"

mkdir -p "$HOME/.config/systemd/user"
install -m644 "$REPO_DIR/systemd/predator-kb-restore.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable predator-kb-restore.service >/dev/null
echo "    predator-kb-restore.service habilitado"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR nao esta no seu PATH; adicione-o ao seu shell rc." ;;
esac

# --- 6. Integracao com o Omarchy -------------------------------------------
if [[ $WITH_OMARCHY == auto && -d $HOME/.config/omarchy ]]; then
  say "7/7 Integrando com o Omarchy"
  "$REPO_DIR/omarchy/install-omarchy.sh"
else
  say "7/7 Integracao com o Omarchy ignorada"
fi

# --- 7. Carregar agora -----------------------------------------------------
say "Trocando os modulos agora"
sudo modprobe -r acer_wmi 2>/dev/null || true
sudo modprobe -r facer 2>/dev/null || true
sudo modprobe facer
sleep 1

if [[ -w /dev/acer-gkbbl-0 && -w /dev/acer-gkbbl-static-0 ]]; then
  printf '\n\033[1;32mPronto!\033[0m Teste com:  predator-kb color ff0055\n\n'
else
  die "os devices /dev/acer-gkbbl-* nao apareceram. Veja: sudo dmesg | tail -20"
fi
