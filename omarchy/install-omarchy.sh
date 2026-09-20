#!/usr/bin/env bash
# Registers the predator-kb menu and keybindings with Omarchy.
# Idempotent: re-running replaces the blocks instead of duplicating them.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
BINDINGS="$HOME/.config/hypr/bindings.lua"

# Drop a previously installed block, keeping a backup.
strip_block() {
  local f=$1
  [[ -f $f ]] || return 0
  grep -q 'predator-kb:begin' "$f" || return 0
  cp "$f" "$f.bak.$(date +%s)"
  sed -i '/predator-kb:begin/,/predator-kb:end/d' "$f"
}

# --- menu ------------------------------------------------------------------
if [[ -f $MENU ]]; then
  strip_block "$MENU"
  # Entries go in just before the brace that closes the root object.
  python3 - "$MENU" "$HERE/menu-entries.jsonc" <<'PY'
import sys
target, snippet = sys.argv[1], sys.argv[2]
src = open(target, encoding='utf-8').read()
block = open(snippet, encoding='utf-8').read()
i = src.rstrip().rfind('}')
open(target, 'w', encoding='utf-8').write(src[:i] + '\n' + block + src[i:])
PY
  echo "    menu: $MENU"
else
  echo "    (omarchy-menu.jsonc not found; skipping the menu)"
fi

# --- keybindings -----------------------------------------------------------
if [[ -f $BINDINGS ]]; then
  strip_block "$BINDINGS"
  cat "$HERE/bindings.lua" >> "$BINDINGS"
  echo "    keybindings: $BINDINGS"
  if command -v hyprctl >/dev/null; then
    hyprctl reload >/dev/null 2>&1 || true
    errs=$(hyprctl configerrors 2>/dev/null | grep -v '^$' || true)
    if [[ -n $errs ]]; then
      echo "    Hyprland warning: $errs"
    fi
  fi
else
  echo "    (bindings.lua not found; skipping keybindings)"
fi
