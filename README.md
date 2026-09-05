# switchboard

Your terminal, wired so **identity and cloud context follow the directory you're in.** `cd` into a work repo and your git author, GPG signing key, gcloud config, and AWS profile are all work; `cd` into a personal project and they're all personal. No manual switching, no wrong-identity commits.

Clone it on a new machine, run one guided installer, and you get the same setup everywhere.

> **Requirements: macOS · zsh · Homebrew.** The helpers use zsh (`compdef`, `autoload`) and macOS-specific tools (`date -j`, `pbcopy`), and the installer uses Homebrew for optional tools. Linux and bash are not currently supported.

## Why

Juggling personal and work accounts on one machine is error-prone: commits signed with the wrong key, `terraform apply` against the wrong AWS account, `gcloud` pointed at the wrong project. switchboard removes the manual step. It keys everything off the directory:

| Layer | Mechanism | `~/code/` (personal) | `~/code/<org>/` (work) |
|-------|-----------|----------------------|------------------------|
| Git commit identity | `includeIf` in `~/.gitconfig` | personal email + GPG key | work email + GPG key |
| gcloud config | `CLOUDSDK_ACTIVE_CONFIG_NAME` via direnv | `personal` | `work` |
| AWS profile | `AWS_PROFILE` via direnv | (personal/none) | work default; per-repo overrides |

Plus auth helpers (`aws-login`, `gcp-switch`, `whereami`, ...) and a `my-commands` cheatsheet that lists only the tools you actually use.

## Quick start

**Platform: macOS + zsh + Homebrew** (see Requirements above). **Only tool prerequisite: `git`.** Everything else (direnv, gh, aws, gcloud, gpg, jq) is optional and the installer offers to install each one via Homebrew if you want it.

```bash
git clone https://github.com/<you>/switchboard.git ~/code/switchboard
~/code/switchboard/install.sh
```

(Clone over HTTPS so you don't need SSH keys set up first — the installer configures the `github.com-work`/`-personal` SSH aliases later. If you already have SSH working, `git@github.com:<you>/switchboard.git` is fine too.)

The installer is interactive and idempotent. It walks you through:

1. **Prerequisites** — for each tool, shows whether it's installed and asks if switchboard should use it. Missing ones can be installed via Homebrew on the spot. Your answers become the "toolset" that gates the rest.
2. **Scan** — reads your existing config (git identity, GPG keys, gcloud configs, AWS profiles, SSH aliases) and uses it as prefilled defaults, so re-running on a set-up machine is mostly pressing Enter.
3. **Shell loader + migration** — sources the repo from `~/.zshrc`, and if you already have these functions defined inline, comments them out so the repo is the single source (backs up first).
4. **Git identity** — writes `~/.gitconfig-personal` / `-work` and the directory `includeIf` rules (won't clobber an existing `~/.gitconfig` without asking). If GPG is in your toolset and a signing key is missing, it offers to generate one and upload the public key to GitHub via `gh`.
5. **direnv `.envrc`s** — drops per-directory gcloud/AWS config at your personal and work roots.
6. **SSH aliases** — optional `github.com-work` / `github.com-personal` host entries.

Then:

```bash
source ~/.zshrc
my-commands     # cheatsheet (only your toolset's commands)
whereami        # active context for this shell
```

Nothing is overwritten without a timestamped backup.

## Commands

- `aws-login <profile>` — SSO login (reuses cached creds; confirms on prod).
- `aws-status` / `gcp-status` / `gh-status` — per-service session checks.
- `gcp-switch <config>` — manual gcloud config switch (Tab-completes).
- `login-all` / `auth-status` — do / check everything at once.
- `env-status` (alias `whereami`) — active context for this shell: **● active / ○ expired** per service, plus the driving `.envrc` and resolved git identity. Makes live checks by default; use `whereami --fast` for an instant offline view (configured names only, status shown as `?`).
- `my-commands` — the cheatsheet; extend it with a `my-commands-local` function in your local config.

## What's committed vs local

The repo is generic and shareable. Anything identifying or machine-specific stays out of git:

| Lives in the repo | Stays local (gitignored / outside repo) |
|-------------------|------------------------------------------|
| helper functions, installer, templates | `~/.gitconfig*` (your emails, GPG key IDs) |
| `.envrc` / gitconfig / ssh **examples** | `~/.config/switchboard/local.zsh` (org profiles, `my-commands-local`) |
| the model + docs | `~/.config/switchboard/toolset.zsh` (your chosen toolset) |
| | `.envrc` files (globally gitignored) |

## Layout

```
shell/
  switchboard.zsh          entrypoint (sourced from ~/.zshrc)
  cloud.zsh                aws-login, gcp-*, gh-*, auth-status, env-status/whereami
  local.zsh.example        machine/org overrides + my-commands-local hook
git/
  gitconfig[.example], gitconfig-{personal,work}.example, gitignore_global
direnv/
  envrc.{personal,work,repo-override}.example
ssh/
  ssh-config.example       github.com-work / github.com-personal aliases
install.sh                 interactive, idempotent, non-destructive bootstrap
uninstall.sh               removes the loader + restores migrated inline funcs
hooks/pre-commit           contributor hook: leak scan + shellcheck (see Contributing)
```

## Optional prod safety guard

By default `aws-login` makes no assumption about your profile naming. Set `SWITCHBOARD_PROD_PATTERN` (and optionally `SWITCHBOARD_STAGE_PATTERN`) in `~/.config/switchboard/local.zsh` to enable a red confirm-guard before logging into matching profiles, and tier-based colouring:

```zsh
export SWITCHBOARD_PROD_PATTERN='prod|Production|live'
```

## Contributing

If you're editing switchboard itself, enable the pre-commit hook so commits are checked automatically:

```bash
git config core.hooksPath hooks     # (install.sh also offers to do this)
brew install shellcheck             # optional; the hook skips lint if absent
```

On each commit the hook:
- **leak-scans** the staged diff for high-confidence secrets (AWS keys, private-key blocks, GitHub tokens, `api_key`/`token`/`password` assignments) and refuses the commit if any match;
- **shellchecks** staged `install.sh` / `uninstall.sh`.

Bypass in a genuine false-positive with `git commit --no-verify`. This is contributor tooling only — it plays no part in what switchboard sets up on a user's machine.

## One GitHub account, two aliases?

If you use a single GitHub account for both work and personal repos, the `-work` and `-personal` SSH aliases can point at the same key today. Keeping them separate means a future split (e.g. losing work access) is a one-line `IdentityFile` change, not a per-repo remote migration.
