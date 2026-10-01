# lib/ai.zsh — AI agent ecosystem helpers. First ecosystem: kiro.
#
# Canonical command: `ai kiro <action>` (login, status, agent <name>, agents).
# Flat `kiro-login` / `kiro-agent` aliases are transitional and guarded, so an
# existing ~/.zshrc definition keeps winning. They are slated for removal in a
# later phase (see docs/ai-module.md).
#
# Org/machine-specific values (SSO start URL, region, license) are NOT here.
# They live in ~/.config/switchboard/local.zsh as KIRO_* exports; see
# shell/local.zsh.example.

# Where the agents repo lives, used by `ai kiro agent/agents` and by the
# installer when it delegates to the source repo's setup.sh. Overridable in
# local.zsh or the environment.
export KIRO_AGENTS_HOME="${KIRO_AGENTS_HOME:-$HOME/code/kiro-pit-crew/agents}"

# kiro-cli ships zsh shell-integration (pre/post blocks). Source the pre block
# here if present so completions and keybindings work when switchboard loads it.
# A hand-written ~/.zshrc may already source these; sourcing twice is harmless.
[[ -f "$HOME/Library/Application Support/kiro-cli/shell/zshrc.pre.zsh" ]] && \
  builtin source "$HOME/Library/Application Support/kiro-cli/shell/zshrc.pre.zsh"

# _ai_have_kiro_cli — kiro-cli present? Prints install guidance and returns 1 if
# not. Detect-and-guide only; switchboard never auto-installs the CLI.
function _ai_have_kiro_cli {
  command -v kiro-cli >/dev/null 2>&1 && return 0
  printf '\033[33m!\033[0m kiro-cli not found. Install it, then re-run.\n'
  printf '  macOS:  brew install --cask kiro-cli\n'
  printf '  Docs:   https://kiro.dev/docs/cli/\n'
  return 1
}

# ai kiro login — authenticate kiro-cli. Reads the org SSO values from
# local.zsh (KIRO_IDENTITY_PROVIDER, KIRO_REGION, KIRO_LICENSE); falls back to
# the device-flow pro login with no provider if they are unset.
function _ai_kiro_login {
  _ai_have_kiro_cli || return 1
  local provider="${KIRO_IDENTITY_PROVIDER:-}"
  local region="${KIRO_REGION:-eu-west-1}"
  local license="${KIRO_LICENSE:-pro}"
  if [ -z "$provider" ]; then
    printf '\033[33m!\033[0m KIRO_IDENTITY_PROVIDER not set (see local.zsh.example); logging in without a provider URL.\n'
    kiro-cli login --license "$license" --use-device-flow
    return $?
  fi
  kiro-cli login --license "$license" --identity-provider "$provider" --region "$region" --use-device-flow
}

# ai kiro status — show the current kiro-cli login, via `kiro-cli whoami`.
# Degrades gracefully if the CLI is missing or no session exists.
function _ai_kiro_status {
  _ai_have_kiro_cli || return 1
  local who
  if who=$(kiro-cli whoami 2>/dev/null); then
    printf '\033[32m✅ kiro:\033[0m %s\n' "$(printf '%s' "$who" | head -1)"
  else
    printf '\033[31m❌ kiro:\033[0m not logged in — run: ai kiro login\n'
  fi
}

# ai kiro agents — list installed agents.
function _ai_kiro_agents {
  _ai_have_kiro_cli || return 1
  kiro-cli agent list
}

# ai kiro agent <name> — start a chat with the named agent.
function _ai_kiro_agent {
  _ai_have_kiro_cli || return 1
  if [ -z "${1:-}" ]; then
    echo "usage: ai kiro agent <name>   (list: ai kiro agents)"
    return 1
  fi
  kiro-cli chat --agent "$1"
}

# ai — top-level dispatcher. Today only the `kiro` ecosystem is wired.
function ai {
  local ecosystem="${1:-}"; shift 2>/dev/null || true
  case "$ecosystem" in
    kiro)
      local action="${1:-}"; shift 2>/dev/null || true
      case "$action" in
        login)  _ai_kiro_login ;;
        status) _ai_kiro_status ;;
        agents) _ai_kiro_agents ;;
        agent)  _ai_kiro_agent "${1:-}" ;;
        ""|-h|--help|help)
          echo "usage: ai kiro <login|status|agents|agent <name>>" ;;
        *) echo "ai kiro: unknown action '$action' (login|status|agents|agent)"; return 1 ;;
      esac ;;
    ""|-h|--help|help)
      echo "usage: ai <ecosystem> <action>"
      echo "  ecosystems: kiro"
      echo "  e.g. ai kiro status · ai kiro login · ai kiro agents · ai kiro agent <name>" ;;
    *) echo "ai: unknown ecosystem '$ecosystem' (supported: kiro)"; return 1 ;;
  esac
}

# completion for `ai`: ecosystem, then action, then agent names after `agent`.
function _ai_completions {
  local -a words; words=("${(@)words}")
  case "$CURRENT" in
    2) compadd kiro ;;
    3) [[ "${words[2]}" == kiro ]] && compadd login status agents agent ;;
    4) [[ "${words[2]}" == kiro && "${words[3]}" == agent ]] && \
       compadd ${(f)"$(kiro-cli agent list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/Global|Built-in|Workspace/{print $1}' | sed 's/^\*//')"} ;;
  esac
}
(( $+functions[compdef] )) && compdef _ai_completions ai 2>/dev/null

# ── Transitional flat aliases (guarded; existing ~/.zshrc definitions win) ───
# These map the old hyphenated names onto the canonical `ai kiro` commands. They
# are defined ONLY if not already defined, so a hand-written ~/.zshrc copy keeps
# precedence. Deprecated: a later phase removes them.
command -v kiro-login >/dev/null 2>&1 || function kiro-login { ai kiro login "$@"; }
command -v kiro-agent >/dev/null 2>&1 || function kiro-agent {
  [ -z "${1:-}" ] && { ai kiro agents; return; }
  ai kiro agent "$1"
}
# completion for the transitional kiro-agent (only if we defined it ourselves).
if ! command -v _kiro_agent_completions >/dev/null 2>&1; then
  function _kiro_agent_completions {
    compadd ${(f)"$(kiro-cli agent list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/Global|Built-in|Workspace/{print $1}' | sed 's/^\*//')"}
  }
  (( $+functions[compdef] )) && compdef _kiro_agent_completions kiro-agent 2>/dev/null
fi

# whereami integration: contribute a kiro auth line. env-status calls this if
# defined, passing "fast" in --fast mode so we skip the network whoami call.
function _sb_whereami_extra {
  local fast="${1:-}"
  local G=$'\033[32m' R=$'\033[31m' DIM=$'\033[2m' X=$'\033[0m'
  local ON="${G}●${X}" OFF="${R}○${X}" UNK="${DIM}?${X}"
  if ! command -v kiro-cli >/dev/null 2>&1; then
    printf "  %b  %-8s %s\n" "$UNK" "kiro" "${DIM}kiro-cli not installed${X}"
    return
  fi
  if [ -n "$fast" ]; then
    printf "  %b  %-8s %s\n" "$UNK" "kiro" "${DIM}(--fast: not checked)${X}"
    return
  fi
  local who
  if who=$(kiro-cli whoami 2>/dev/null | head -1); then
    printf "  %b  %-8s %s\n" "$ON" "kiro" "${who}"
  else
    printf "  %b  %-8s %s\n" "$OFF" "kiro" "${DIM}run: ai kiro login${X}"
  fi
}
