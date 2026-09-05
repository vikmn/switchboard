# switchboard.zsh — entrypoint. Source this from ~/.zshrc:
#
#   source ~/code/switchboard/shell/switchboard.zsh
#
# It wires up: cloud/auth helpers, the my-commands cheatsheet, direnv, and your
# machine-local overrides.

SWITCHBOARD_DIR="${SWITCHBOARD_DIR:-$HOME/code/switchboard}"

# completion system (needed for the compdef lines in cloud.zsh)
autoload -Uz compinit && compinit -C 2>/dev/null

# generic helpers
source "$SWITCHBOARD_DIR/shell/cloud.zsh"

# direnv hook (per-directory cloud config / AWS profile / etc.)
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

# machine-local overrides (org profiles, extra aliases) — not committed
[ -f "$HOME/.config/switchboard/local.zsh" ] && source "$HOME/.config/switchboard/local.zsh"

# agreed toolset recorded by install.sh (sets SWITCHBOARD_TOOLS) — not committed
[ -f "$HOME/.config/switchboard/toolset.zsh" ] && source "$HOME/.config/switchboard/toolset.zsh"

# cheatsheet — shows only the sections for tools in your toolset.
# If SWITCHBOARD_TOOLS is unset (repo sourced without running install.sh),
# it falls back to showing everything.
function my-commands {
  local tools="${SWITCHBOARD_TOOLS:-direnv gh aws gcloud gpg}"
  _sb_has() { [[ " $tools " == *" $1 "* ]]; }
  echo "🛠️  Switchboard commands:"
  echo ""
  _sb_has aws    && echo "📋 AWS:    aws-login <profile> · aws-status · aws-profiles"
  _sb_has gcloud && echo "☁️  GCP:    gcp-login · gcp-status · gcp-switch <config> (Tab)"
  _sb_has gh     && echo "🐙 GitHub: gh-login · gh-status"
  echo "🔐 All:    login-all [aws-profile] · auth-status"
  echo "📍 Context: env-status / whereami   (● active / ○ expired, per shell)"
  echo ""
  echo "Identity & cloud switch automatically by directory via .envrc + git includeIf."
  echo "See: $SWITCHBOARD_DIR/README.md"
  unfunction _sb_has
}
