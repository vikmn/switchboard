#!/usr/bin/env bash
# install/lib/migrate.sh — comment out inline copies of switchboard functions in
# ~/.zshrc so the sourced repo becomes the single source. Matches only the known
# managed names (below); unrelated config is never touched.
#
# When you add/rename a helper in shell/lib/*.zsh, update SB_MANAGED_* here.
#
# shellcheck disable=SC2034  # SB_MANAGED_* are consumed by install.sh's migrate step

SB_MANAGED_FUNCS="_aws_env_color _aws_expiry _aws_box aws-login aws-status gcp-login gcp-status gcp-switch gh-login gh-status login-all auth-status env-status my-commands"
SB_MANAGED_ALIASES="aws-profiles whereami"

# comment out one 'function NAME { ... }' block in a file, matching balanced
# braces. Wraps it in [switchboard-migrated] markers. Idempotent.
_sb_comment_func() {
  local file="$1" name="$2"
  awk -v fn="$name" '
    BEGIN { depth=0; inblk=0 }
    { line=$0 }
    (!inblk && ($0 ~ "^function[ \t]+" fn "[ \t]*(\\(\\))?[ \t]*\\{" || $0 ~ "^" fn "[ \t]*\\(\\)[ \t]*\\{")) {
      inblk=1; depth=0
      print "# [switchboard-migrated] " fn " now provided by the repo:"
    }
    inblk {
      n=gsub(/\{/,"{"); m=gsub(/\}/,"}"); depth += n - m
      print "# " line
      if (depth<=0) { inblk=0 }
      next
    }
    { print line }
  ' "$file"
}

# comment out an 'alias NAME=...' line
_sb_comment_alias() {
  local file="$1" name="$2"
  awk -v al="$name" '
    $0 ~ "^alias[ \t]+" al "=" { print "# [switchboard-migrated] " al ":"; print "# " $0; next }
    { print }
  ' "$file"
}
