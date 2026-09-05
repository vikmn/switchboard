#!/usr/bin/env bash
# install.sh — interactive switchboard setup. Asks about each component so you
# can skip the parts you don't use (e.g. no GCP, no work identity). Safe:
# backs up before overwriting and confirms on anything destructive.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="$HOME/.config/switchboard"
TS="$(date +%Y%m%d-%H%M%S)"

# ── ui helpers ───────────────────────────────────────────────────────────────
B=$'\033[1m'; DIM=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; X=$'\033[0m'
section() { printf "\n${B}%s${X}\n" "$*"; }
ok()      { printf "  ${G}✓${X} %s\n" "$*"; }
skip()    { printf "  ${DIM}– %s${X}\n" "$*"; }
warn()    { printf "  ${Y}!${X} %s\n" "$*"; }

# ask "Question?" [default y|n]  -> returns 0 for yes
ask() {
  local q="$1" def="${2:-n}" hint="[y/N]" ans
  [ "$def" = "y" ] && hint="[Y/n]"
  printf "  %s %s " "$q" "$hint" >/dev/tty
  read -r ans </dev/tty
  ans="${ans:-$def}"
  [[ "$ans" == [Yy]* ]]
}

# prompt "Label" "default" -> echoes ONLY the entered (or default) value on stdout.
# The label is written to the terminal so it is never captured by $( ).
prompt() {
  local label="$1" def="${2:-}" val
  if [ -n "$def" ]; then printf "    %s [%s]: " "$label" "$def" >/dev/tty; else printf "    %s: " "$label" >/dev/tty; fi
  read -r val </dev/tty
  echo "${val:-$def}"
}

backup() {
  local f="$1"
  if [ -e "$f" ] && [ ! -L "$f" ]; then cp "$f" "$f.bak-$TS"; warn "backed up $f -> $(basename "$f").bak-$TS"; fi
}

have() { command -v "$1" >/dev/null 2>&1; }

printf "${B}switchboard setup${X}\n"
printf "${DIM}Answer per component; skip anything you don't use. Nothing is overwritten without a backup.${X}\n"

# ── 1. shell loader (always; it's the point) ─────────────────────────────────
section "1. Shell loader (~/.zshrc)"
if grep -q "switchboard/shell/switchboard.zsh" "$HOME/.zshrc" 2>/dev/null; then
  skip "~/.zshrc already sources switchboard"
elif ask "Add the switchboard source line to ~/.zshrc?" y; then
  printf '\n# switchboard: cloud/identity context helpers\nsource %s/shell/switchboard.zsh\n' "$DIR" >> "$HOME/.zshrc"
  ok "added source line to ~/.zshrc"
else
  skip "shell loader (you can add it later)"
fi

# ── 2. machine-local overrides ───────────────────────────────────────────────
section "2. Machine-local overrides (~/.config/switchboard/local.zsh)"
if [ -f "$CONFIG_HOME/local.zsh" ]; then
  skip "local.zsh already exists"
elif ask "Create local.zsh from template (for org-specific profiles/aliases)?" y; then
  mkdir -p "$CONFIG_HOME"
  cp "$DIR/shell/local.zsh.example" "$CONFIG_HOME/local.zsh"
  ok "created $CONFIG_HOME/local.zsh — edit it to add org dispatchers"
else
  skip "local overrides"
fi

# ── 3. global gitignore ──────────────────────────────────────────────────────
section "3. Global gitignore (~/.gitignore_global)"
if ask "Install the global gitignore (ignores .envrc, .DS_Store, ...)?" y; then
  backup "$HOME/.gitignore_global"
  cp "$DIR/git/gitignore_global" "$HOME/.gitignore_global"
  git config --global core.excludesfile "$HOME/.gitignore_global"
  ok "installed ~/.gitignore_global and set core.excludesfile"
else
  skip "global gitignore"
fi

# ── 4. git identity (personal always; work optional) ─────────────────────────
section "4. Git identity (directory-based)"
if ask "Configure git identity switching?" y; then
  code_root="$(prompt "Personal code root" "$HOME/code")"
  p_name="$(prompt "Personal name" "$(git config --global user.name 2>/dev/null)")"
  p_email="$(prompt "Personal email")"
  p_key="$(prompt "Personal GPG signing key ID (blank to skip signing)")"

  work_root=""
  if ask "Do you also have a WORK identity (separate email/key under a subfolder)?" y; then
    work_root="$(prompt "Work code root (must be under the personal root)" "$code_root/work")"
    w_name="$(prompt "Work name" "$p_name")"
    w_email="$(prompt "Work email")"
    w_key="$(prompt "Work GPG signing key ID (blank to skip)")"
  fi

  write_identity() { # write_identity <file> <name> <email> <key>
    local f="$1" n="$2" e="$3" k="$4"
    backup "$f"
    { echo "[user]"; echo "    name = $n"; echo "    email = $e"
      [ -n "$k" ] && echo "    signingkey = $k"
      if [ -n "$k" ]; then echo "[commit]"; echo "    gpgsign = true"; echo "[tag]"; echo "    gpgsign = true"; fi
    } > "$f"
  }
  write_identity "$HOME/.gitconfig-personal" "$p_name" "$p_email" "$p_key"
  ok "wrote ~/.gitconfig-personal"
  [ -n "$work_root" ] && { write_identity "$HOME/.gitconfig-work" "$w_name" "$w_email" "$w_key"; ok "wrote ~/.gitconfig-work"; }

  # base ~/.gitconfig: default identity + includeIf rules (personal, then work)
  if [ -f "$HOME/.gitconfig" ] && ! ask "Overwrite ~/.gitconfig base (backup will be made)?" n; then
    warn "left ~/.gitconfig as-is — add these includeIf rules manually:"
    printf "      [includeIf \"gitdir:%s/\"]\n        path = ~/.gitconfig-personal\n" "${code_root/#$HOME/\~}"
    [ -n "$work_root" ] && printf "      [includeIf \"gitdir:%s/\"]\n        path = ~/.gitconfig-work\n" "${work_root/#$HOME/\~}"
  else
    backup "$HOME/.gitconfig"
    {
      echo "[user]"; echo "    name = $p_name"; echo "    email = $p_email"
      [ -n "$p_key" ] && echo "    signingkey = $p_key"
      [ -n "$p_key" ] && { echo "[commit]"; echo "    gpgsign = true"; echo "[tag]"; echo "    gpgsign = true"; }
      have gpg && { echo "[gpg]"; echo "    program = $(command -v gpg)"; }
      echo "[core]"; echo "    excludesfile = ~/.gitignore_global"
      echo "# directory-based identity (last-match-wins: work after personal)"
      echo "[includeIf \"gitdir:${code_root/#$HOME/\~}/\"]"; echo "    path = ~/.gitconfig-personal"
      [ -n "$work_root" ] && { echo "[includeIf \"gitdir:${work_root/#$HOME/\~}/\"]"; echo "    path = ~/.gitconfig-work"; }
    } > "$HOME/.gitconfig"
    ok "wrote ~/.gitconfig with includeIf rules"
  fi
else
  skip "git identity"
fi

# ── 5. direnv per-directory cloud config ─────────────────────────────────────
section "5. Per-directory cloud config (direnv)"
if ! have direnv; then
  warn "direnv not installed — 'brew install direnv' then re-run this section"
elif ask "Set up per-directory gcloud/AWS switching via .envrc?" y; then
  p_root="${code_root:-$HOME/code}"
  if ask "Create ${p_root/#$HOME/\~}/.envrc (personal gcloud config)?" y; then
    gcfg="$(prompt "Personal gcloud config name" "personal")"
    backup "$p_root/.envrc"
    echo "export CLOUDSDK_ACTIVE_CONFIG_NAME=$gcfg" > "$p_root/.envrc"
    direnv allow "$p_root" 2>/dev/null && ok "wrote + allowed $p_root/.envrc"
  fi
  if [ -n "${work_root:-}" ] && ask "Create ${work_root/#$HOME/\~}/.envrc (work gcloud + AWS)?" y; then
    wgcfg="$(prompt "Work gcloud config name" "work")"
    wprof="$(prompt "Default work AWS profile (blank to skip)")"
    backup "$work_root/.envrc"
    { echo "export CLOUDSDK_ACTIVE_CONFIG_NAME=$wgcfg"; [ -n "$wprof" ] && echo "export AWS_PROFILE=$wprof"; } > "$work_root/.envrc"
    mkdir -p "$work_root"; direnv allow "$work_root" 2>/dev/null && ok "wrote + allowed $work_root/.envrc"
  fi
else
  skip "direnv cloud config"
fi

# ── 6. SSH host aliases ──────────────────────────────────────────────────────
section "6. SSH host aliases (work/personal)"
if ask "Append the github.com-work / github.com-personal aliases to ~/.ssh/config?" n; then
  backup "$HOME/.ssh/config"; mkdir -p "$HOME/.ssh"
  cat "$DIR/ssh/ssh-config.example" >> "$HOME/.ssh/config"
  ok "appended aliases — edit the IdentityFile paths in ~/.ssh/config"
else
  skip "SSH aliases (template at $DIR/ssh/ssh-config.example)"
fi

# ── prerequisites report ─────────────────────────────────────────────────────
section "Prerequisites"
for t in direnv gh aws jq gcloud gpg; do
  have "$t" && ok "$t" || warn "$t missing"
done

section "Done"
printf "  Reload your shell: ${B}source ~/.zshrc${X}\n"
printf "  Then run: ${B}my-commands${X}  and  ${B}whereami${X}\n"
