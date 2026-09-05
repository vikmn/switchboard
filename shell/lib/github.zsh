# lib/github.zsh — GitHub CLI helpers (gh-login, gh-status).

function gh-login {
  echo "🔐 Authenticating with GitHub..."
  gh auth login --web --git-protocol ssh
  echo "✅ $(gh auth status 2>&1 | grep 'Logged in')"
}

function gh-status {
  if gh auth status >/dev/null 2>&1; then echo "✅ $(gh auth status 2>&1 | grep 'Logged in')"
  else echo "❌ GitHub: not authenticated — run gh-login"; fi
}
