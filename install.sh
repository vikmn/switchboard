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

# brew_install <formula-or-cask> [--cask] — install via Homebrew if brew exists.
brew_install() {
  local pkg="$1" cask="${2:-}"
  if ! have brew; then warn "Homebrew not found — install it first: https://brew.sh" >/dev/tty; return 1; fi
  if [ "$cask" = "--cask" ]; then brew install --cask "$pkg"; else brew install "$pkg"; fi
}

# want_tool "Label" <cmd> <brew-pkg> [--cask]
# Always shows the tool's state and asks whether switchboard should use it.
#   installed -> default YES (Enter includes it); answer n to opt out
#   missing   -> default NO; answering y installs via brew, then includes it
# Echoes "yes" on stdout when the tool is in the agreed toolset.
want_tool() {
  local label="$1" cmd="$2" pkg="$3" cask="${4:-}"
  if have "$cmd"; then
    printf "  ${G}✓${X} %s ${DIM}(installed)${X}\n" "$label" >/dev/tty
    ask "  use it for switchboard?" y && echo yes
    return
  fi
  printf "  ${Y}!${X} %s ${DIM}(not installed)${X}\n" "$label" >/dev/tty
  if ask "  install via Homebrew now?" n; then
    if brew_install "$pkg" $cask >/dev/tty 2>&1; then
      have "$cmd" && { echo yes; return; }
      warn "install attempted but $cmd still not found" >/dev/tty
    fi
  fi
  # not in play
}

# ── prerequisites: decide the toolset BEFORE scanning ────────────────────────
# Scan and component prompts are gated to the tools chosen here, so a machine
# that doesn't use (say) GCP is never probed or prompted for it.
prerequisites() {
  section "Prerequisites — choose your toolset"
  WANT_DIRENV=$(want_tool "direnv (per-directory switching)" direnv direnv)
  WANT_GH=$(want_tool "GitHub CLI" gh gh)
  WANT_AWS=$(want_tool "AWS CLI" aws awscli)
  WANT_GCP=$(want_tool "Google Cloud SDK" gcloud google-cloud-sdk --cask)
  WANT_GPG=$(want_tool "GnuPG (commit signing)" gpg gnupg)
  [ -n "$WANT_AWS" ] && WANT_JQ=$(want_tool "jq (used by AWS helpers)" jq jq)
  printf "${DIM}  toolset: %s%s%s%s%s${X}\n" \
    "${WANT_DIRENV:+direnv }" "${WANT_GH:+gh }" "${WANT_AWS:+aws }" "${WANT_GCP:+gcloud }" "${WANT_GPG:+gpg }"
}

# ── read-only machine scan: detect existing setup to use as prompt defaults ──
# Nothing here writes; it only reads local config so re-runs are confirm-only.
# Probes are gated to the agreed toolset (WANT_*).
scan_machine() {
  set +e  # detection is best-effort; individual failing probes must not abort
  DET_LOADER=$(grep -q "switchboard/shell/switchboard.zsh" "$HOME/.zshrc" 2>/dev/null && echo yes || true)
  DET_LOCAL=$([ -f "$CONFIG_HOME/local.zsh" ] && echo yes || true)
  DET_GITIGNORE=$([ -f "$HOME/.gitignore_global" ] && echo yes || true)

  # personal identity: prefer an existing personal include, else the base gitconfig
  if [ -f "$HOME/.gitconfig-personal" ]; then
    DET_P_NAME=$(git config -f "$HOME/.gitconfig-personal" user.name 2>/dev/null)
    DET_P_EMAIL=$(git config -f "$HOME/.gitconfig-personal" user.email 2>/dev/null)
    DET_P_KEY=$(git config -f "$HOME/.gitconfig-personal" user.signingkey 2>/dev/null)
  fi
  DET_P_NAME=${DET_P_NAME:-$(git config --global user.name 2>/dev/null)}
  DET_P_EMAIL=${DET_P_EMAIL:-$(git config --global user.email 2>/dev/null)}
  DET_P_KEY=${DET_P_KEY:-$(git config --global user.signingkey 2>/dev/null)}

  # work identity: only if a work include already exists
  if [ -f "$HOME/.gitconfig-work" ]; then
    DET_HAS_WORK=yes
    DET_W_NAME=$(git config -f "$HOME/.gitconfig-work" user.name 2>/dev/null)
    DET_W_EMAIL=$(git config -f "$HOME/.gitconfig-work" user.email 2>/dev/null)
    DET_W_KEY=$(git config -f "$HOME/.gitconfig-work" user.signingkey 2>/dev/null)
  fi

  # existing includeIf roots (extract the gitdir path between 'gitdir:' and the trailing '.path')
  DET_INCLUDES=$(git config --global --get-regexp 'includeIf\.gitdir:' 2>/dev/null | awk '{print $1}' | sed -E 's/^[Ii]nclud[Ee][Ii]f\.gitdir:(.*)\.path$/\1/' | sort -u | tr '\n' ' ')

  # GPG keys — only if signing is in the toolset
  [ -n "${WANT_GPG:-}" ] && DET_GPG_KEYS=$(gpg --list-secret-keys --keyid-format=long 2>/dev/null | awk '/^sec/{print $2}' | cut -d/ -f2 | tr '\n' ' ')

  # gcloud configs — only if GCP is in the toolset
  [ -n "${WANT_GCP:-}" ] && have gcloud && DET_GCLOUD_CFGS=$(gcloud config configurations list --format='value(name)' 2>/dev/null | tr '\n' ' ')

  # aws profiles — only if AWS is in the toolset
  [ -n "${WANT_AWS:-}" ] && have aws && DET_AWS_PROFILES=$(aws configure list-profiles 2>/dev/null | tr '\n' ' ')

  # existing github ssh aliases
  DET_SSH_ALIASES=$(grep -cE '^Host github\.com-(work|personal)' "$HOME/.ssh/config" 2>/dev/null || echo 0)
}

printf "${B}switchboard setup${X}\n"
prerequisites

printf "\n${DIM}Scanning machine for existing setup...${X}\n"
scan_machine

section "Detected"
[ -n "$DET_LOADER" ]      && ok "shell loader already in ~/.zshrc"        || skip "shell loader not present"
[ -n "$DET_P_EMAIL" ]     && ok "git personal identity: $DET_P_EMAIL"     || skip "no git identity found"
[ -n "${DET_HAS_WORK:-}" ] && ok "git work identity: ${DET_W_EMAIL:-?}"    || skip "no work git identity"
[ -n "$DET_INCLUDES" ]    && ok "includeIf roots: $DET_INCLUDES"          || skip "no includeIf rules"
[ -n "${DET_GPG_KEYS:-}" ] && ok "GPG keys: ${DET_GPG_KEYS}"              || { [ -n "${WANT_GPG:-}" ] && skip "no GPG secret keys"; }
[ -n "${DET_GCLOUD_CFGS:-}" ] && ok "gcloud configs: ${DET_GCLOUD_CFGS}"  || { [ -n "${WANT_GCP:-}" ] && skip "no gcloud configs"; }
[ -n "${DET_AWS_PROFILES:-}" ] && ok "AWS profiles: $(echo $DET_AWS_PROFILES | wc -w | tr -d ' ') found" || { [ -n "${WANT_AWS:-}" ] && skip "no AWS profiles"; }
[ "${DET_SSH_ALIASES:-0}" -gt 0 ] && ok "SSH github aliases present"      || skip "no SSH github aliases"
printf "${DIM}  (scan is read-only; nothing changed. Detected values are used as defaults below.)${X}\n"
set -e  # back to strict for the write phases

printf "\n${DIM}Answer per component; skip anything you don't use. Nothing is overwritten without a backup.${X}\n"

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
  p_name="$(prompt "Personal name" "$DET_P_NAME")"
  p_email="$(prompt "Personal email" "$DET_P_EMAIL")"
  [ -n "${DET_GPG_KEYS:-}" ] && printf "    ${DIM}(available GPG keys: %s)${X}\n" "$DET_GPG_KEYS" >/dev/tty
  p_key="$(prompt "Personal GPG signing key ID (blank to skip signing)" "$DET_P_KEY")"

  work_root=""
  if ask "Do you also have a WORK identity (separate email/key under a subfolder)?" "${DET_HAS_WORK:+y}"; then
    work_root="$(prompt "Work code root (must be under the personal root)" "$code_root/work")"
    w_name="$(prompt "Work name" "${DET_W_NAME:-$p_name}")"
    w_email="$(prompt "Work email" "${DET_W_EMAIL:-}")"
    w_key="$(prompt "Work GPG signing key ID (blank to skip)" "${DET_W_KEY:-}")"
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
if [ -z "${WANT_DIRENV:-}" ]; then
  skip "direnv not in toolset — skipping per-directory switching"
elif [ -z "${WANT_GCP:-}${WANT_AWS:-}" ]; then
  skip "neither GCP nor AWS in toolset — nothing to switch per-directory"
elif ask "Set up per-directory gcloud/AWS switching via .envrc?" y; then
  p_root="${code_root:-$HOME/code}"
  if [ -n "${WANT_GCP:-}" ]; then
    [ -n "${DET_GCLOUD_CFGS:-}" ] && printf "    ${DIM}(gcloud configs found: %s)${X}\n" "$DET_GCLOUD_CFGS" >/dev/tty
    if ask "Create ${p_root/#$HOME/\~}/.envrc (personal gcloud config)?" y; then
      gcfg="$(prompt "Personal gcloud config name" "personal")"
      backup "$p_root/.envrc"
      echo "export CLOUDSDK_ACTIVE_CONFIG_NAME=$gcfg" > "$p_root/.envrc"
      direnv allow "$p_root" 2>/dev/null && ok "wrote + allowed $p_root/.envrc"
    fi
  fi
  if [ -n "${work_root:-}" ] && ask "Create ${work_root/#$HOME/\~}/.envrc (work overrides)?" y; then
    backup "$work_root/.envrc"; mkdir -p "$work_root"
    {
      [ -n "${WANT_GCP:-}" ] && { wgcfg="$(prompt "Work gcloud config name" "work")"; echo "export CLOUDSDK_ACTIVE_CONFIG_NAME=$wgcfg"; }
      if [ -n "${WANT_AWS:-}" ]; then
        [ -n "${DET_AWS_PROFILES:-}" ] && printf "    ${DIM}(AWS profiles found: %s)${X}\n" "$DET_AWS_PROFILES" >/dev/tty
        wprof="$(prompt "Default work AWS profile (blank to skip)")"
        [ -n "$wprof" ] && echo "export AWS_PROFILE=$wprof"
      fi
    } > "$work_root/.envrc"
    direnv allow "$work_root" 2>/dev/null && ok "wrote + allowed $work_root/.envrc"
  fi
else
  skip "direnv cloud config"
fi

# ── 6. SSH host aliases ──────────────────────────────────────────────────────
section "6. SSH host aliases (work/personal)"
if [ "${DET_SSH_ALIASES:-0}" -gt 0 ]; then
  skip "github.com-work/personal aliases already in ~/.ssh/config"
elif ask "Append the github.com-work / github.com-personal aliases to ~/.ssh/config?" n; then
  backup "$HOME/.ssh/config"; mkdir -p "$HOME/.ssh"
  cat "$DIR/ssh/ssh-config.example" >> "$HOME/.ssh/config"
  ok "appended aliases — edit the IdentityFile paths in ~/.ssh/config"
else
  skip "SSH aliases (template at $DIR/ssh/ssh-config.example)"
fi

section "Done"
# persist the agreed toolset so my-commands reflects what was set up
mkdir -p "$CONFIG_HOME"
{
  echo "# written by switchboard install.sh — the toolset you opted into"
  echo "export SWITCHBOARD_TOOLS=\"${WANT_DIRENV:+direnv }${WANT_GH:+gh }${WANT_AWS:+aws }${WANT_GCP:+gcloud }${WANT_GPG:+gpg }\""
} > "$CONFIG_HOME/toolset.zsh"
ok "recorded toolset -> $CONFIG_HOME/toolset.zsh"
printf "  Toolset: %s%s%s%s%s\n" "${WANT_DIRENV:+direnv }" "${WANT_GH:+gh }" "${WANT_AWS:+aws }" "${WANT_GCP:+gcloud }" "${WANT_GPG:+gpg }"
printf "  Reload your shell: ${B}source ~/.zshrc${X}\n"
printf "  Then run: ${B}my-commands${X}  and  ${B}whereami${X}\n"
