#!/usr/bin/env bash
# install/lib/ui.sh — terminal output + prompt helpers for the installer.
# Requires TS to be set by the caller (for backup()). Sourced by install.sh
# and uninstall.sh.
#
# shellcheck disable=SC2059  # printf format uses fixed colour-code vars, no user data
# shellcheck disable=SC2034  # R and other colour vars are used by callers

B=$'\033[1m'; DIM=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; X=$'\033[0m'
section() { printf "\n${B}%s${X}\n" "$*"; }
ok()      { printf "  ${G}✓${X} %s\n" "$*"; }
skip()    { printf "  ${DIM}– %s${X}\n" "$*"; }
warn()    { printf "  ${Y}!${X} %s\n" "$*"; }

# ask "Question?" [default y|n]  -> returns 0 for yes. Reads from the terminal.
ask() {
  local q="$1" def="${2:-n}" hint="[y/N]" ans
  [ "$def" = "y" ] && hint="[Y/n]"
  printf "  %s %s " "$q" "$hint" >/dev/tty
  read -r ans </dev/tty
  ans="${ans:-$def}"
  [[ "$ans" == [Yy]* ]]
}

# prompt "Label" "default" -> echoes ONLY the entered (or default) value on stdout.
# The label goes to the terminal so it is never captured by $( ).
prompt() {
  local label="$1" def="${2:-}" val
  if [ -n "$def" ]; then printf "    %s [%s]: " "$label" "$def" >/dev/tty; else printf "    %s: " "$label" >/dev/tty; fi
  read -r val </dev/tty
  echo "${val:-$def}"
}

# backup <file> — copy aside with a timestamp if it exists and isn't a symlink.
backup() {
  local f="$1"
  if [ -e "$f" ] && [ ! -L "$f" ]; then cp "$f" "$f.bak-$TS"; warn "backed up $f -> $(basename "$f").bak-$TS"; fi
}

have() { command -v "$1" >/dev/null 2>&1; }
