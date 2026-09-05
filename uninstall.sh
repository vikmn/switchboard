#!/usr/bin/env bash
# uninstall.sh — reverse what install.sh wired into the shell. Conservative:
# removes the loader line and un-comments migrated inline functions (so your
# original ~/.zshrc definitions come back), backing up first. It does NOT delete
# your identity files, keys, or .envrc data — those are yours; it only prints
# what's left so you can remove them manually if you want.
#
# shellcheck disable=SC2059  # printf format uses fixed colour-code vars, no user data
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
zrc="$HOME/.zshrc"
B=$'\033[1m'; DIM=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; X=$'\033[0m'
section() { printf "\n${B}%s${X}\n" "$*"; }
ok()   { printf "  ${G}✓${X} %s\n" "$*"; }
skip() { printf "  ${DIM}– %s${X}\n" "$*"; }
warn() { printf "  ${Y}!${X} %s\n" "$*"; }
ask() { local q="$1" d="${2:-n}" h="[y/N]" a; [ "$d" = y ] && h="[Y/n]"; printf "  %s %s " "$q" "$h" >/dev/tty; read -r a </dev/tty; a="${a:-$d}"; [[ "$a" == [Yy]* ]]; }
backup() { [ -e "$1" ] && cp "$1" "$1.bak-$TS" && warn "backed up $1 -> $(basename "$1").bak-$TS"; }

printf "${B}switchboard uninstall${X}\n"

section "1. Remove the shell loader line"
if grep -q "switchboard/shell/switchboard.zsh" "$zrc" 2>/dev/null; then
  if ask "Remove the switchboard source line from ~/.zshrc?" y; then
    backup "$zrc"
    # drop the loader line and the preceding comment line if present
    awk '
      /^# switchboard: cloud\/identity context helpers$/ { hold=$0; next }
      /switchboard\/shell\/switchboard\.zsh/ { hold=""; next }
      { if (hold!="") { print hold; hold="" } print }
      END { if (hold!="") print hold }
    ' "$zrc" > "$zrc.tmp" && mv "$zrc.tmp" "$zrc"
    ok "removed loader line"
  fi
else
  skip "no loader line found"
fi

section "2. Restore migrated inline functions"
if grep -q "^# \[switchboard-migrated\]" "$zrc" 2>/dev/null; then
  n=$(grep -c "^# \[switchboard-migrated\]" "$zrc")
  if ask "Un-comment $n migrated block(s) so your original inline definitions return?" y; then
    backup "$zrc"
    # strip the marker line and un-prefix the "# " from the block body until a
    # non-'# ' line (mirrors how install.sh commented them).
    awk '
      /^# \[switchboard-migrated\]/ { skipping=1; next }
      skipping {
        if ($0 ~ /^# /) { sub(/^# /, "", $0); print; next }
        else if ($0 ~ /^#$/) { print ""; next }
        else { skipping=0 }
      }
      { print }
    ' "$zrc" > "$zrc.tmp" && mv "$zrc.tmp" "$zrc"
    ok "restored inline definitions (review ~/.zshrc)"
  fi
else
  skip "no migrated blocks found"
fi

section "3. Config files left in place (remove manually if you want)"
for f in "$HOME/.config/switchboard/local.zsh" "$HOME/.config/switchboard/toolset.zsh"; do
  [ -f "$f" ] && printf "  %s\n" "$f"
done
warn "NOT touched (yours): ~/.gitconfig*, GPG keys, ~/.ssh/config, ~/.gitignore_global, .envrc files"
printf "  To remove switchboard config dir: ${B}rm -rf ~/.config/switchboard${X}\n"

section "Done"
printf "  Reload your shell: ${B}source ~/.zshrc${X}  (or open a new terminal)\n"
printf "  ${DIM}A backup of ~/.zshrc was saved as ~/.zshrc.bak-%s${X}\n" "$TS"
