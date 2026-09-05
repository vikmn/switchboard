#!/usr/bin/env bash
# install.sh — wire switchboard into a machine. Idempotent and non-destructive:
# it never overwrites an existing real config; it backs up and prints next steps.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="$HOME/.config/switchboard"
TS="$(date +%Y%m%d-%H%M%S)"

say()  { printf "  %s\n" "$*"; }
head() { printf "\n\033[1m%s\033[0m\n" "$*"; }

backup() { # backup <file> — move aside if it exists and isn't our symlink
  local f="$1"
  if [ -e "$f" ] && [ ! -L "$f" ]; then
    cp "$f" "$f.bak-$TS"
    say "backed up existing $f -> $f.bak-$TS"
  fi
}

head "1. Shell loader"
if ! grep -q "switchboard/shell/switchboard.zsh" "$HOME/.zshrc" 2>/dev/null; then
  {
    echo ""
    echo "# switchboard: cloud/identity context helpers"
    echo "source $DIR/shell/switchboard.zsh"
  } >> "$HOME/.zshrc"
  say "added source line to ~/.zshrc"
else
  say "~/.zshrc already sources switchboard (skipped)"
fi

head "2. Machine-local overrides"
mkdir -p "$CONFIG_HOME"
if [ ! -f "$CONFIG_HOME/local.zsh" ]; then
  cp "$DIR/shell/local.zsh.example" "$CONFIG_HOME/local.zsh"
  say "created $CONFIG_HOME/local.zsh (edit with your org profiles)"
else
  say "$CONFIG_HOME/local.zsh exists (left as-is)"
fi

head "3. Global gitignore"
backup "$HOME/.gitignore_global"
cp "$DIR/git/gitignore_global" "$HOME/.gitignore_global"
say "installed ~/.gitignore_global"

head "4. Git identity (templates — fill in, not auto-installed to avoid clobbering)"
for t in gitconfig gitconfig-personal gitconfig-work; do
  target="$HOME/.${t}"
  if [ ! -f "$target" ]; then
    say "cp $DIR/git/${t}.example  $target   # then edit name/email/GPG key"
  else
    say "$target exists (left as-is)"
  fi
done

head "5. SSH host aliases"
say "review and append: $DIR/ssh/ssh-config.example  ->  ~/.ssh/config"

head "6. Per-directory cloud config (direnv)"
say "cp $DIR/direnv/envrc.personal.example  ~/code/.envrc         && direnv allow ~/code"
say "cp $DIR/direnv/envrc.work.example      ~/code/<ORG>/.envrc   && direnv allow ~/code/<ORG>"

head "Done."
say "Prerequisites: brew install direnv gh awscli jq  + gcloud SDK"
say "Reload: source ~/.zshrc   then run: my-commands"
