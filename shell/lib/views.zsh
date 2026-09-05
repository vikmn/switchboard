# lib/views.zsh — cross-service views: login-all, auth-status, env-status/whereami.
# Depends on the per-service libs (aws/gcp/github) being sourced first.

function login-all {
  echo "🏁 Logging in to all services..."; echo ""
  local awsp="${1:-${SWITCHBOARD_DEFAULT_AWS_PROFILE:-}}"
  if [ -n "$awsp" ]; then aws-login "$awsp"; else echo "⏭️  AWS: no profile given and SWITCHBOARD_DEFAULT_AWS_PROFILE unset — skipping (run: aws-login <profile>)"; fi
  echo ""
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
# Live checks by default (aws sts, gcloud token, gh api). --fast/-f skips all
# network calls and shows configured names only (status shown as '?').
function env-status {
  local fast=""
  [[ "$1" == "--fast" || "$1" == "-f" ]] && fast=yes
  local G=$'\033[32m' R=$'\033[31m' DIM=$'\033[2m' X=$'\033[0m'
  local ON="${G}●${X}" OFF="${R}○${X}" UNK="${DIM}?${X}"
  local awsp=${AWS_PROFILE:-"-"}
  local gcfg=${CLOUDSDK_ACTIVE_CONFIG_NAME:-$(gcloud config configurations list --filter='is_active=true' --format='value(name)' 2>/dev/null)}
  local gacct=$(gcloud config get-value account 2>/dev/null)
  local gproj=$(gcloud config get-value project 2>/dev/null); [ -z "$gproj" ] && gproj="-"
  local rc=$(direnv status 2>/dev/null | awk '/Found RC path/{print $4}'); rc=${rc/#$HOME/\~}
  local gitid
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    gitid=$(git config user.email 2>/dev/null || echo "-")
  else
    gitid="${DIM}<not a git repo — global default applies>${X}"
  fi

  local awsacct="" gtok="" ghuser=""
  if [ -z "$fast" ]; then   # live checks (skipped in --fast mode)
    awsacct=$(AWS_PAGER="" aws sts get-caller-identity --query Account --output text 2>/dev/null)
    gtok=$(gcloud auth print-access-token >/dev/null 2>&1 && echo yes)
    ghuser=$(gh api user --jq .login 2>/dev/null)
  fi

  printf "\n"
  if [ -n "$fast" ]; then
    printf "  %b  %-8s %s\n" "$UNK" "AWS"    "${awsp}"
    printf "  %b  %-8s %s\n" "$UNK" "GCP"    "${gcfg:-"-"}  ${DIM}·${X}  ${gacct}  ${DIM}·${X}  proj ${gproj}"
    printf "  %b  %-8s %s\n" "$UNK" "GitHub" "${DIM}(--fast: not checked)${X}"
  else
    if [ -n "$awsacct" ]; then printf "  %b  %-8s %s\n" "$ON"  "AWS"    "${awsp}  ${DIM}·${X}  acct ${awsacct}  ${DIM}·${X}  $(_aws_expiry)"
    else                       printf "  %b  %-8s %s\n" "$OFF" "AWS"    "${awsp}  ${DIM}· run: aws-login ${awsp%.*}${X}"; fi
    if [ -n "$gtok" ]; then    printf "  %b  %-8s %s\n" "$ON"  "GCP"    "${gcfg}  ${DIM}·${X}  ${gacct}  ${DIM}·${X}  proj ${gproj}"
    else                       printf "  %b  %-8s %s\n" "$OFF" "GCP"    "${gcfg:-"-"}  ${DIM}· run: gcp-login${X}"; fi
    if [ -n "$ghuser" ]; then  printf "  %b  %-8s %s\n" "$ON"  "GitHub" "${ghuser}"
    else                       printf "  %b  %-8s %s\n" "$OFF" "GitHub" "${DIM}run: gh-login${X}"; fi
  fi
  printf "  %s  %-8s %s\n" " " "git" "${gitid}"
  printf "${DIM}  📍 %s   🧭 %s${X}\n\n" "$(pwd | sed "s|$HOME|~|")" "${rc:-<none>}"
}
alias whereami='env-status'
