# cloud.zsh — AWS / GCP / GitHub helpers + a unified context view.
# Generic and machine-agnostic. Anything account/profile-specific belongs in
# ~/.config/switchboard/local.zsh (see local.zsh.example), not here.

# ── AWS ────────────────────────────────────────────────────────────────────
# Colour by environment: prod=red, stage=yellow, else green.
function _aws_env_color() {
  if [[ "$1" == *prod* || "$1" == *Production* ]]; then echo "\033[1;31m"
  elif [[ "$1" == *stage* ]]; then echo "\033[33m"
  else echo "\033[32m"; fi
}

# Time remaining on the most recent SSO cache token.
function _aws_expiry() {
  local latest=$(find ~/.aws/sso/cache -name '*.json' -exec jq -r 'select(.startUrl and .expiresAt) | .expiresAt' {} \; 2>/dev/null | sort -r | head -1)
  if [ -n "$latest" ]; then
    local exp_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${latest%%.*}" "+%s" 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$latest" "+%s" 2>/dev/null)
    local now_epoch=$(date "+%s")
    if [ -n "$exp_epoch" ] && [ "$exp_epoch" -gt "$now_epoch" ]; then
      local diff=$(( (exp_epoch - now_epoch) / 60 ))
      echo "$(( diff / 60 ))h $(( diff % 60 ))m remaining"; return
    fi
  fi
  echo "unknown"
}

function _aws_box() {
  local profile=$1 account=$2 region=$3 expiry=$4 icon=$5
  local color=$(_aws_env_color "$profile")
  printf "${color}┌──────────────────────────────────┐\033[0m\n"
  printf "${color}│  ${icon} %-28s │\033[0m\n" "$profile"
  printf "${color}│  Account: %-22s │\033[0m\n" "$account"
  printf "${color}│  Region:  %-22s │\033[0m\n" "$region"
  printf "${color}│  Expires: %-22s │\033[0m\n" "$expiry"
  printf "${color}└──────────────────────────────────┘\033[0m\n"
}

# aws-login <profile> — reuse cached creds or SSO login; confirms on prod.
function aws-login {
  local profile=$1
  local color=$(_aws_env_color "$profile")
  if [[ "$profile" == *prod* || "$profile" == *Production* ]]; then
    printf "${color}┌──────────────────────────────────┐\033[0m\n"
    printf "${color}│  ⚠️  %-27s │\033[0m\n" "${profile%%.*}  PROD"
    printf "${color}└──────────────────────────────────┘\033[0m\n"
    printf "Continue? (y/n) "; read -r confirm
    [[ $confirm != "y" ]] && echo "❌ Login cancelled" && return 1
  fi
  if aws configure export-credentials --profile $profile --format env >/dev/null 2>&1; then
    echo "Using existing credentials for profile $profile"
  else
    echo "No valid credentials found, initiating SSO login..."
    aws sso login --profile=$profile
  fi
  eval $(aws configure export-credentials --profile $profile --format env)
  export AWS_PROFILE=$profile
  local account=$(AWS_PAGER="" aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
  _aws_box "$profile" "$account" "${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-west-1}}" "$(_aws_expiry)" "✅"
}
alias aws-profiles='aws configure list-profiles'

function aws-status {
  local profile=${AWS_PROFILE:-"(none)"}
  if AWS_PAGER="" aws sts get-caller-identity >/dev/null 2>&1; then
    local account=$(AWS_PAGER="" aws sts get-caller-identity --query Account --output text 2>/dev/null)
    _aws_box "$profile" "$account" "${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-west-1}}" "$(_aws_expiry)" "✅"
  else
    printf "\033[31m❌ AWS: no valid session (profile=%s) — run aws-login\033[0m\n" "$profile"
  fi
}

# ── GCP ────────────────────────────────────────────────────────────────────
function gcp-login {
  echo "🔐 Authenticating with Google Cloud..."
  gcloud auth login --quiet
  gcloud auth application-default login --quiet
  echo "✅ $(gcloud config get-value account 2>/dev/null) (project: $(gcloud config get-value project 2>/dev/null || echo unset))"
}

function gcp-status {
  if gcloud auth print-access-token >/dev/null 2>&1; then
    echo "✅ GCP: $(gcloud config get-value account 2>/dev/null) (project: $(gcloud config get-value project 2>/dev/null || echo unset))"
  else
    echo "❌ GCP: token expired — run gcp-login"
  fi
}

# gcp-switch <config> — manual gcloud config switch (direnv auto-switches in dirs
# that set CLOUDSDK_ACTIVE_CONFIG_NAME). Sets the override for THIS shell too.
function gcp-switch {
  local target="$1"
  local avail=$(gcloud config configurations list --format='value(name)' 2>/dev/null | paste -sd' ' -)
  if [ -z "$target" ]; then
    echo "usage: gcp-switch <config>   (available: $avail)"; return 1
  fi
  if ! gcloud config configurations list --format='value(name)' 2>/dev/null | grep -qx "$target"; then
    echo "❌ no gcloud config named '$target' (available: $avail)"; return 1
  fi
  export CLOUDSDK_ACTIVE_CONFIG_NAME="$target"
  gcloud config configurations activate "$target" >/dev/null 2>&1
  echo "☁️  gcloud → $target ($(gcloud config get-value account 2>/dev/null), project: $(gcloud config get-value project 2>/dev/null || echo unset))"
}
_gcp_switch_completions() { compadd $(gcloud config configurations list --format='value(name)' 2>/dev/null) }
compdef _gcp_switch_completions gcp-switch 2>/dev/null

# ── GitHub ───────────────────────────────────────────────────────────────────
function gh-login {
  echo "🔐 Authenticating with GitHub..."
  gh auth login --web --git-protocol ssh
  echo "✅ $(gh auth status 2>&1 | grep 'Logged in')"
}
function gh-status {
  if gh auth status >/dev/null 2>&1; then echo "✅ $(gh auth status 2>&1 | grep 'Logged in')"
  else echo "❌ GitHub: not authenticated — run gh-login"; fi
}

# ── Unified views ────────────────────────────────────────────────────────────
function login-all {
  echo "🏁 Logging in to all services..."; echo ""
  aws-login ${1:-default}; echo ""
  gcp-login; echo ""
  gh-status; echo ""
  echo "Done. Run 'auth-status' to check all sessions."
}

function auth-status {
  echo "🔐 Auth Status:"; echo ""
  aws-status; echo ""
  gcp-status; echo ""
  gh-status
}

# env-status / whereami — active context for THIS shell (● active / ○ expired).
function env-status {
  local G=$'\033[32m' R=$'\033[31m' DIM=$'\033[2m' X=$'\033[0m'
  local ON="${G}●${X}" OFF="${R}○${X}"
  local awsp=${AWS_PROFILE:-"-"}
  local awsacct; awsacct=$(AWS_PAGER="" aws sts get-caller-identity --query Account --output text 2>/dev/null)
  local gcfg=${CLOUDSDK_ACTIVE_CONFIG_NAME:-$(gcloud config configurations list --filter='is_active=true' --format='value(name)' 2>/dev/null)}
  local gacct=$(gcloud config get-value account 2>/dev/null)
  local gproj=$(gcloud config get-value project 2>/dev/null); [ -z "$gproj" ] && gproj="-"
  local gtok=$(gcloud auth print-access-token >/dev/null 2>&1 && echo yes)
  local ghuser; ghuser=$(gh api user --jq .login 2>/dev/null)
  local rc=$(direnv status 2>/dev/null | awk '/Found RC path/{print $4}'); rc=${rc/#$HOME/\~}
  local gitid
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    gitid=$(git config user.email 2>/dev/null || echo "-")
  else
    gitid="${DIM}<not a git repo — global default applies>${X}"
  fi
  printf "\n"
  if [ -n "$awsacct" ]; then printf "  %b  %-8s %s\n" "$ON"  "AWS"    "${awsp}  ${DIM}·${X}  acct ${awsacct}  ${DIM}·${X}  $(_aws_expiry)"
  else                       printf "  %b  %-8s %s\n" "$OFF" "AWS"    "${awsp}  ${DIM}· run: aws-login ${awsp%.*}${X}"; fi
  if [ -n "$gtok" ]; then    printf "  %b  %-8s %s\n" "$ON"  "GCP"    "${gcfg}  ${DIM}·${X}  ${gacct}  ${DIM}·${X}  proj ${gproj}"
  else                       printf "  %b  %-8s %s\n" "$OFF" "GCP"    "${gcfg:-"-"}  ${DIM}· run: gcp-login${X}"; fi
  if [ -n "$ghuser" ]; then  printf "  %b  %-8s %s\n" "$ON"  "GitHub" "${ghuser}"
  else                       printf "  %b  %-8s %s\n" "$OFF" "GitHub" "${DIM}run: gh-login${X}"; fi
  printf "  %s  %-8s %s\n" " " "git" "${gitid}"
  printf "${DIM}  📍 %s   🧭 %s${X}\n\n" "$(pwd | sed "s|$HOME|~|")" "${rc:-<none>}"
}
alias whereami='env-status'
