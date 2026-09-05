# Contributing to switchboard

Thanks for your interest. Contributions are welcome via pull request.

## Workflow

1. **Fork** the repo and clone your fork.
2. Create a branch: `git checkout -b my-change`.
3. Make your change. Keep it focused; one concern per PR.
4. **Enable the pre-commit hook** (see below) so your commits are checked.
5. Push to your fork and **open a pull request** against `main`.

`main` is protected: direct pushes are blocked, and every PR needs a review
approval before it can merge. The maintainer reviews and merges — so opening a
PR is the only path in, for everyone.

## Pre-commit hook

If you're editing switchboard, enable the hook so commits are checked
automatically:

```bash
git config core.hooksPath hooks     # install.sh also offers to do this
brew install shellcheck             # optional; the hook skips lint if absent
```

On each commit it:
- **leak-scans** the staged diff for high-confidence secrets (AWS keys,
  private-key blocks, GitHub tokens, `api_key`/`token`/`password` assignments)
  and refuses the commit if any match;
- **shellchecks** staged `install.sh` / `uninstall.sh`.

Bypass a genuine false positive with `git commit --no-verify`. The hook is
contributor tooling only — it plays no part in what switchboard sets up on a
user's machine.

## Style & scope

- Keep the repo **generic**: no personal emails, GPG key IDs, org names,
  account numbers, or org-specific profiles in committed files. Machine/org
  specifics live in `~/.config/switchboard/local.zsh` (see `local.zsh.example`).
- **Shell**: helpers are zsh (`shell/*.zsh`); the installers are bash and are
  shellchecked. Match the existing style; prefer `printf` over `echo` for
  anything with escapes.
- **Safety**: anything that writes to a user's dotfiles must back up first and
  confirm before overwriting — follow the pattern in `install.sh`.
- Platform is **macOS + zsh + Homebrew**; don't add hard dependencies on tools
  outside that without discussion.

## Reporting issues

Open an issue describing what you expected vs. what happened, your macOS/zsh
versions, and the relevant `install.sh` / command output (redact any secrets).
