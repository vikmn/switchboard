# lib/gcp.zsh — Google Cloud helpers (gcp-login, gcp-status, gcp-switch).

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
# register completion only if the completion system is loaded (compinit has run)
(( $+functions[compdef] )) && compdef _gcp_switch_completions gcp-switch 2>/dev/null
