# lib/aws.zsh — AWS helpers (aws-login, aws-status) + env colouring.
# Environment awareness is OPT-IN and OFF by default. Set these in
# ~/.config/switchboard/local.zsh to enable the prod confirm-guard and env
# colouring for profiles whose name matches:
#   SWITCHBOARD_PROD_PATTERN='prod|Production|live'
#   SWITCHBOARD_STAGE_PATTERN='stage|staging'
# Unset (default) => aws-login never guards or colours by environment.

# _aws_is_prod <profile> -> 0 if it matches the configured prod pattern
_aws_is_prod() { [ -n "${SWITCHBOARD_PROD_PATTERN:-}" ] && [[ "$1" =~ (${SWITCHBOARD_PROD_PATTERN}) ]]; }

# Colour by environment (only if a pattern is configured; neutral otherwise).
function _aws_env_color() {
  if _aws_is_prod "$1"; then printf '%s' $'\033[1;31m'
  elif [ -n "${SWITCHBOARD_STAGE_PATTERN:-}" ] && [[ "$1" =~ (${SWITCHBOARD_STAGE_PATTERN}) ]]; then printf '%s' $'\033[33m'
  else printf '%s' $'\033[32m'; fi
}

# Convert an ISO-8601 timestamp to epoch seconds, portably (BSD date on macOS,
# GNU date on Linux). Echoes nothing on failure.
function _epoch_from_iso() {
  local ts="$1"
  date -j -f "%Y-%m-%dT%H:%M:%S" "${ts%%.*}" "+%s" 2>/dev/null && return   # BSD (macOS)
  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null && return
  date -d "$ts" "+%s" 2>/dev/null && return                                # GNU (Linux)
}

# Time remaining on the most recent SSO cache token. NOTE: newest token across
# all cached SSO sessions — may not be the current profile's. Rough indicator.
function _aws_expiry() {
  local latest=$(find ~/.aws/sso/cache -name '*.json' -exec jq -r 'select(.startUrl and .expiresAt) | .expiresAt' {} \; 2>/dev/null | sort -r | head -1)
  if [ -n "$latest" ]; then
    local exp_epoch=$(_epoch_from_iso "$latest")
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

# aws-login <profile> — reuse cached creds or SSO login. If SWITCHBOARD_PROD_PATTERN
# is set and the profile matches, shows a red confirm-guard first.
function aws-login {
  local profile=$1
  local color=$(_aws_env_color "$profile")
  if _aws_is_prod "$profile"; then
    printf "${color}┌──────────────────────────────────┐\033[0m\n"
    printf "${color}│  ⚠️  %-27s │\033[0m\n" "${profile%%.*}  PROD"
    printf "${color}└──────────────────────────────────┘\033[0m\n"
    printf "Continue? (y/n) " > /dev/tty; local confirm; read -r confirm < /dev/tty
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
