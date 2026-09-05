#!/usr/bin/env bash
# install/lib/pkg.sh — cross-platform package manager abstraction.
# Requires ui.sh (have/warn/ask) sourced first. Sets PKG_MGR.
#
# To add a tool: add its per-manager rows to the pkg_install case table, and a
# want_tool call in install.sh's prerequisites().

# Detected once. Supported: brew, apt, dnf, pacman, zypper. Unknown -> manual.
detect_pkg_mgr() {
  if have brew; then echo brew
  elif have apt-get; then echo apt
  elif have dnf; then echo dnf
  elif have pacman; then echo pacman
  elif have zypper; then echo zypper
  else echo none; fi
}
PKG_MGR="$(detect_pkg_mgr)"

# pkg_install <tool-key> — install a tool by its logical key using PKG_MGR.
# Package names differ per manager; unknown/unavailable tools print a manual
# hint and return non-zero rather than pretending.
pkg_install() {
  local key="$1" pkg="" sudo=""
  [ "$PKG_MGR" != brew ] && [ "$(id -u)" -ne 0 ] && sudo="sudo"
  case "$PKG_MGR:$key" in
    brew:direnv|apt:direnv|dnf:direnv|pacman:direnv|zypper:direnv) pkg=direnv ;;
    brew:gh)     pkg=gh ;;
    zypper:gh)   pkg=gh ;;
    pacman:gh)   pkg=github-cli ;;
    apt:gh|dnf:gh)
      # gh is not in default Ubuntu/Debian/Fedora repos — needs GitHub's repo added first.
      warn "GitHub CLI isn't in default $PKG_MGR repos. Add GitHub's repo then install:" >/dev/tty
      warn "  https://github.com/cli/cli/blob/trunk/docs/install_linux.md" >/dev/tty
      return 1 ;;
    brew:aws)    pkg=awscli ;;
    apt:aws|dnf:aws|zypper:aws) pkg=awscli ;;
    pacman:aws)  pkg=aws-cli-v2 ;;
    brew:jq|apt:jq|dnf:jq|pacman:jq|zypper:jq) pkg=jq ;;
    brew:gpg)    pkg=gnupg ;;
    apt:gpg)     pkg=gnupg ;;
    dnf:gpg|zypper:gpg) pkg=gnupg2 ;;
    pacman:gpg)  pkg=gnupg ;;
    brew:gcloud) pkg="--cask google-cloud-sdk" ;;
    *:gcloud)    warn "gcloud isn't in $PKG_MGR repos — install: https://cloud.google.com/sdk/docs/install" >/dev/tty; return 1 ;;
    *)           warn "no package mapping for '$key' on $PKG_MGR — install it manually" >/dev/tty; return 1 ;;
  esac
  case "$PKG_MGR" in
    brew)   # shellcheck disable=SC2086  # pkg may include --cask, must split
            brew install $pkg ;;
    apt)    $sudo apt-get update -qq && $sudo apt-get install -y "$pkg" ;;
    dnf)    $sudo dnf install -y "$pkg" ;;
    pacman) $sudo pacman -S --noconfirm "$pkg" ;;
    zypper) $sudo zypper install -y "$pkg" ;;
    none)   warn "no supported package manager found — install '$key' manually" >/dev/tty; return 1 ;;
  esac
}

# want_tool "Label" <cmd> <tool-key>
# Shows state and asks whether switchboard should use it.
#   installed -> default YES; missing -> offer install via the detected manager.
# Echoes "yes" when the tool is in the agreed toolset.
want_tool() {
  local label="$1" cmd="$2" key="$3"
  if have "$cmd"; then
    printf "  ${G}✓${X} %s ${DIM}(installed)${X}\n" "$label" >/dev/tty
    ask "  use it for switchboard?" y && echo yes
    return
  fi
  printf "  ${Y}!${X} %s ${DIM}(not installed)${X}\n" "$label" >/dev/tty
  if [ "$PKG_MGR" = none ]; then
    warn "no supported package manager detected — install $cmd manually, then re-run" >/dev/tty
    return
  fi
  if ask "  install via $PKG_MGR now?" n; then
    if pkg_install "$key" >/dev/tty 2>&1; then
      have "$cmd" && { echo yes; return; }
      warn "install attempted but $cmd still not found" >/dev/tty
    fi
  fi
  # not in play
}
