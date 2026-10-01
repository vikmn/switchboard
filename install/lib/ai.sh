#!/usr/bin/env bash
# install/lib/ai.sh — opt-in AI ecosystem step for install.sh. First ecosystem:
# kiro. Detect-and-guide for kiro-cli (never auto-install), locate-or-clone the
# agents source repo, delegate agent install to that repo's own setup.sh, and
# template the kiro login values into local.zsh.
#
# Requires ui.sh (ask/ok/skip/warn/have/section) sourced first, plus CONFIG_HOME
# and DIR set by install.sh.

# The agents repo switchboard installs from by default.
AI_DEFAULT_SOURCE="$HOME/code/kiro-pit-crew"
AI_SOURCE_REPO_URL="https://github.com/vikmn/kiro-pit-crew.git"

# _ai_locate_or_clone <dir> — ensure the agents source repo exists at <dir>. If
# it isn't there, offer to clone it. Echoes the resolved dir on success, empty
# on skip/failure. Messages go to the terminal so they aren't captured by $( ).
_ai_locate_or_clone() {
  local dir="$1"
  if [ -d "$dir/agents" ] && [ -f "$dir/agents/setup.sh" ]; then
    echo "$dir"; return 0
  fi
  warn "agents source not found at $dir" >/dev/tty
  if ask "  clone it from $AI_SOURCE_REPO_URL?" n; then
    if git clone "$AI_SOURCE_REPO_URL" "$dir" >/dev/tty 2>&1; then
      [ -f "$dir/agents/setup.sh" ] && { echo "$dir"; return 0; }
      warn "cloned, but $dir/agents/setup.sh is missing" >/dev/tty
    else
      warn "clone failed" >/dev/tty
    fi
  fi
  return 1
}

# ai_setup — the opt-in step. Called from install.sh.
ai_setup() {
  section "8. AI ecosystem (kiro)"
  if ! ask "Set up the AI agent ecosystem (kiro)?" n; then
    skip "AI ecosystem"
    return
  fi

  # 1. detect-and-guide: kiro-cli must be installed; never auto-install.
  if ! have kiro-cli; then
    warn "kiro-cli not found. Install it, then re-run this step:"
    warn "  macOS:  brew install --cask kiro-cli"
    warn "  Docs:   https://kiro.dev/docs/cli/"
    skip "AI ecosystem (install kiro-cli first)"
    return
  fi
  ok "kiro-cli detected ($(kiro-cli --version 2>/dev/null | head -1))"

  # 2. local config: template the kiro login values so `ai kiro login` works.
  mkdir -p "$CONFIG_HOME"
  if [ ! -f "$CONFIG_HOME/local.zsh" ]; then
    cp "$DIR/shell/local.zsh.example" "$CONFIG_HOME/local.zsh"
    ok "created $CONFIG_HOME/local.zsh from template"
  fi
  if grep -q "KIRO_IDENTITY_PROVIDER" "$CONFIG_HOME/local.zsh" 2>/dev/null; then
    skip "local.zsh already has KIRO_* entries — edit them with your org SSO values"
  else
    cat >> "$CONFIG_HOME/local.zsh" <<'EOF'

# ── AI module: kiro login values (added by install.sh; fill these in) ────────
# export KIRO_IDENTITY_PROVIDER="https://d-xxxxxxxxxx.awsapps.com/start"
# export KIRO_REGION="eu-west-1"
# export KIRO_LICENSE="pro"
EOF
    ok "appended KIRO_* template to local.zsh — edit it with your org SSO values"
  fi

  # 3. agents: locate-or-clone the source repo, delegate install to its setup.sh.
  if ask "  install kiro agents from a source repo now?" n; then
    local src resolved
    src="$(prompt "Agents source repo" "$AI_DEFAULT_SOURCE")"
    if resolved="$(_ai_locate_or_clone "$src")"; then
      if bash "$resolved/agents/setup.sh" --source "$resolved/agents" --ecosystem kiro >/dev/tty 2>&1; then
        ok "installed agents from $resolved"
      else
        warn "agent setup.sh returned an error — check output above"
      fi
    else
      skip "agents (no source repo; clone it later and re-run)"
    fi
  else
    skip "agents (run the source repo's agents/setup.sh when ready)"
  fi

  ok "AI ecosystem wired — reload your shell, then: ai kiro status"
}
