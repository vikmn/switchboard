# AI module

Bootstraps an AI agent ecosystem on a new machine, parallel to how switchboard
sets up cloud auth. The first ecosystem is **kiro**. Switchboard stays
light-touch: it installs and activates, it does not own agent or CLI-format
knowledge. That lives in the source agents repo.

## Vocabulary

- **Ecosystem** — the CLI/runtime that runs agents. `kiro` today (via `kiro-cli`).
  Selected with `--ecosystem`. Other ecosystems can be added later without
  changing the command surface.
- **Source** — the repo that holds the agent definitions. Default is
  `kiro-pit-crew` at `~/code/kiro-pit-crew`. Selected with `--source`
  (locate-or-clone). Switchboard does not parse agent files; it delegates
  install to the source repo's own `agents/setup.sh`.
- **Agents** — the installed agent configs the ecosystem CLI loads.

## Two axes of pluggability

`--ecosystem` picks the runtime, `--source` picks the agents repo. They are
independent: the same source could target different ecosystems, and different
sources could feed the same ecosystem.

```
switchboard install.sh (opt-in AI step)
        |
        |-- detect kiro-cli (guide if missing, never auto-install)
        |-- template KIRO_* login values into local.zsh
        '-- delegate: <source>/agents/setup.sh --source <dir> --ecosystem kiro
                 |
                 '-- installs agent configs for the chosen ecosystem
```

## Commands

Canonical dispatcher: `ai kiro <action>`.

| Command | Does |
|---------|------|
| `ai kiro login` | Authenticate kiro-cli using the org SSO values from local.zsh |
| `ai kiro status` | Show the current login (`kiro-cli whoami`) |
| `ai kiro agents` | List installed agents |
| `ai kiro agent <name>` | Start a chat with the named agent (Tab-completes) |

`whereami` gains a kiro line (active / expired), backed by `kiro-cli whoami`.

### Transitional aliases

`kiro-login` and `kiro-agent` map onto the `ai kiro` commands. They are
**guarded**: defined only if a command of that name does not already exist, so a
hand-written `~/.zshrc` definition keeps precedence. They are deprecated and a
later phase removes them.

## Prerequisite: kiro-cli

Detect-and-guide. The installer and the `ai` commands detect `kiro-cli`; if it
is missing they print the official install guidance and stop. Switchboard never
auto-installs the CLI.

```
brew install --cask kiro-cli
# docs: https://kiro.dev/docs/cli/
```

## Config: generic in repo, identifying local-only

Org/machine-specific login values are never committed. They live in
`~/.config/switchboard/local.zsh` as `KIRO_*` exports (template in
`shell/local.zsh.example`):

```zsh
export KIRO_IDENTITY_PROVIDER="https://d-xxxxxxxxxx.awsapps.com/start"
export KIRO_REGION="eu-west-1"
export KIRO_LICENSE="pro"            # pro (Identity Center) or free (Builder ID)
```

`ai kiro login` runs:

```
kiro-cli login --license $KIRO_LICENSE --identity-provider $KIRO_IDENTITY_PROVIDER \
               --region $KIRO_REGION --use-device-flow
```

If `KIRO_IDENTITY_PROVIDER` is unset it falls back to a device-flow login with
no provider URL.

`KIRO_AGENTS_HOME` (default `~/code/kiro-pit-crew/agents`) tells kiro-cli where
agents live. Override it in local.zsh if your source repo is elsewhere.

## Coexisting with existing wiring

A machine may already have `kiro-login`/`kiro-agent` and the kiro-cli
shell-integration blocks in `~/.zshrc`. The module coexists: the aliases are
guarded, and sourcing the shell-integration pre block twice is harmless. A later
phase adds an opt-in migrate step to fold the old inline wiring into the module.

## Adding another ecosystem

1. Teach `shell/lib/ai.zsh`'s `ai` dispatcher a new ecosystem branch.
2. Teach the source repo's `agents/setup.sh` to install for `--ecosystem <new>`.
3. Add the detect-and-guide and login templating for the new CLI.

The source repo owns the agent-format knowledge; switchboard only selects and
delegates.

## Uninstall

`uninstall.sh` removes the installer-added `KIRO_*` block from local.zsh and
reports the agents installed under `~/.kiro/agents` (left in place, since they
are the source repo's install). The `ai.zsh` helpers stop loading once the
switchboard loader line is removed from `~/.zshrc`.
