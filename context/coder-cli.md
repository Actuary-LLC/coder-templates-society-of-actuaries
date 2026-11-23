# Coder CLI cheat sheet

CLI reference for working against a Coder deployment from this repo.
Full reference: <https://coder.com/docs/reference/cli>.

## Authentication

```sh
coder login https://coder.actuary.dev     # interactive (browser)
coder whoami                              # verify
```

For non-interactive use (scripts, CI):

```sh
export CODER_URL=https://coder.actuary.dev
export CODER_SESSION_TOKEN=<token>        # from coder tokens create
```

Both the CLI and the Coder MCP server (`coder exp mcp server`) use this auth.

## Templates

```sh
# Validate + upload a new version (inactive until promoted)
coder templates push <name> \
  --directory templates/<name> \
  --name <version-name> \
  --message "<change summary>" \
  --activate=false --yes

coder templates list
coder templates versions list --template <name>
coder templates versions promote --template <name> --template-version <version-name>
```

Version names must be unique per template. CI uses `<short-sha>` on `main`
and `<branch>-<short-sha>` elsewhere.

## Workspaces

```sh
coder create --template <name> --template-version <ver> --use-parameter-defaults <workspace> --yes
coder list
coder show <workspace>            # details incl. agent status and metadata
coder start | stop | delete <workspace> --yes
coder ssh <workspace> -- <cmd>    # blocks until the agent is ready
coder logs <workspace>            # agent + startup script logs? (agent logs)
```

Build/startup logs for a failed boot: `coder show <workspace>` and the
workspace build page in the dashboard.

## Tokens and users (admin)

```sh
coder tokens create --user <user> --name <label> --lifetime 1y --scope <s> ...
coder tokens list --all           # admins: all users' tokens + expiries
coder tokens remove <name|id>     # expires it (--delete = hard delete)

coder users create --username <u> --email <e> --login-type github
coder users edit-roles <u> --roles template-admin --yes
```

Scopes reference: <https://coder.com/docs/reference/api-key-scopes>.
CI identity setup and rotation: `context/ci-cd.md`.

## MCP server

```sh
coder exp mcp server              # stdio MCP server (used by opencode.jsonc)
coder exp mcp configure           # auto-configure common AI tools
```

Tools cover workspaces (create/run commands/read files), templates and
versions, apps, logs, and user/org info.

## Handy flags

- `--yes` / `-y` — skip confirmations (always use in scripts).
- `--output json` — available on most list/read commands.
- `-O, --org` — select organization when the deployment has several.
- `--template-version` — pin a workspace build to a specific version.
