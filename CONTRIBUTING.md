# Contributing to switchboard

switchboard is a personal setup published so others can read, fork, and adapt
it. **The best way to contribute is by opening an issue** — report a bug, or
suggest an idea. The maintainer makes the changes; code is not accepted via pull
request.

## Found a bug or have an idea?

[Open an issue](https://github.com/vikmn/switchboard/issues/new) with:

- what you expected vs. what happened;
- your macOS and zsh versions;
- the relevant `install.sh` / command output (**redact any secrets** — emails,
  keys, account IDs).

## Want your own version?

Fork it and make it yours — that's encouraged. The repo is generic on purpose:
identity values, org profiles, and `.envrc` data all live in your local layer
(`~/.config/switchboard/local.zsh`, `~/.gitconfig*`), never in the repo. So a
fork is yours to tweak without carrying anyone else's specifics.

If you're hacking on your fork, enable the pre-commit hook to catch mistakes:

```bash
git config core.hooksPath hooks     # install.sh also offers to do this
brew install shellcheck             # optional; the hook skips lint if absent
```

It leak-scans staged changes (AWS keys, private-key blocks, tokens,
`api_key`/`token`/`password` assignments) and shellchecks `install.sh` /
`uninstall.sh`. Bypass a false positive with `git commit --no-verify`.

## Conventions (useful if you fork and modify)

- **Keep it generic**: no personal emails, GPG key IDs, org names, account
  numbers, or org-specific profiles in committed files — those belong in
  `~/.config/switchboard/local.zsh` (see `local.zsh.example`).
- **Shell**: helpers are zsh (`shell/*.zsh`); installers are bash and are
  shellchecked. Prefer `printf` over `echo` for anything with escapes.
- **Safety**: anything that writes to a user's dotfiles must back up first and
  confirm before overwriting — follow the pattern in `install.sh`.
- **Platform**: macOS + zsh + Homebrew; avoid hard dependencies outside that.
