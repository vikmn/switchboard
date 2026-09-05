# switchboard

Per-directory identity and cloud-context switching for a dev machine, plus AWS/GCP/GitHub auth helpers. Clone this on a new machine and you get the same setup: git identity, gcloud config, and AWS profile all switch automatically based on which directory you're in.

## The model

One idea, applied three ways, all keyed off the directory you're in:

| Layer | Mechanism | Personal (`~/code/`) | Work (`~/code/<org>/`) |
|-------|-----------|----------------------|------------------------|
| Git commit identity | `includeIf "gitdir:..."` in `~/.gitconfig` | personal email + GPG key | work email + GPG key |
| gcloud config | `CLOUDSDK_ACTIVE_CONFIG_NAME` via direnv `.envrc` | `personal` config | `work` config |
| AWS profile | `AWS_PROFILE` via direnv `.envrc` | (personal/none) | work default; repos can override |

The seam is directory-based, so nothing needs manual switching. `cd` into a work repo and your commits, gcloud, and AWS profile are all work; `cd` into a personal project and they're all personal.

## What's in here

```
shell/
  switchboard.zsh          entrypoint (source from ~/.zshrc)
  cloud.zsh                aws-login, gcp-*, gh-*, auth-status, env-status/whereami
  local.zsh.example        machine/org-specific overrides (copy, don't commit)
git/
  gitconfig.example        base + directory includeIf rules
  gitconfig-personal.example
  gitconfig-work.example
  gitignore_global         ignores .envrc, .DS_Store, etc.
direnv/
  envrc.personal.example   ~/code/.envrc
  envrc.work.example       ~/code/<org>/.envrc
  envrc.repo-override.example
ssh/
  ssh-config.example       github.com-work / github.com-personal aliases
install.sh                 idempotent, non-destructive bootstrap
```

## Setup on a new machine

Prerequisites:
```bash
brew install direnv gh awscli jq
# + Google Cloud SDK (gcloud)
```

Then:
```bash
git clone git@github.com-personal:<you>/switchboard.git ~/code/switchboard
~/code/switchboard/install.sh          # wires the shell loader + prints next steps
```

The installer is deliberately conservative: it adds the shell `source` line, installs the global gitignore, creates `~/.config/switchboard/local.zsh`, and then **prints** the git/SSH/direnv steps rather than auto-writing identity files (so it never clobbers real secrets). Follow the printed steps to fill in your name/email/GPG key IDs and drop the `.envrc` files.

Finally:
```bash
source ~/.zshrc
my-commands        # cheatsheet
whereami           # show the active context
```

## Commands

- `aws-login <profile>` — SSO login (reuses cached creds; confirms on prod).
- `aws-status` / `gcp-status` / `gh-status` — per-service session checks.
- `gcp-switch <config>` — manual gcloud config switch (Tab-completes).
- `login-all` / `auth-status` — do/check everything at once.
- `env-status` (alias `whereami`) — active context for this shell: ● active / ○ expired per service, plus the driving `.envrc` and resolved git identity.

## What is NOT committed

Identity values (emails, GPG key IDs), org-specific profiles, and `.envrc` files live outside the repo:
- git identity → `~/.gitconfig*` (from the `.example` templates)
- org profiles/aliases → `~/.config/switchboard/local.zsh` (from `local.zsh.example`)
- per-directory cloud config → `.envrc` files (globally gitignored)

Keep it that way. The repo stays generic and shareable; secrets and machine specifics stay local.

## One GitHub account, two aliases?

If you use a single GitHub account for both work and personal repos, the `-work` and `-personal` SSH aliases can point at the same key today. Keeping them separate means a future split (e.g. losing work access) is a one-line `IdentityFile` change, not a per-repo remote migration.
