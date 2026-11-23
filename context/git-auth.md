# GitHub auth in workspaces

How git/GitHub authentication works inside workspaces on a Coder
deployment — and how templates interact with it. Short version: **git
works out of the box in every workspace**; there are no PATs to configure.

## How it works

An admin configures a git auth provider (GitHub App or OAuth) on the Coder
deployment ([external auth](https://coder.com/docs/admin/external-auth)).
Each user links their GitHub identity once (at login or on first git use).
No long-lived credential is stored in the workspace — the Coder agent
injects short-lived, per-session ones.

## In a running workspace

The agent sets two environment variables:

| Variable | Value | Covers |
|----------|-------|--------|
| `GIT_ASKPASS` | the `coder` CLI | HTTPS git — the CLI answers credential prompts with a token from the deployment |
| `GIT_SSH_COMMAND` | `coder gitssh --` | SSH git — routes through the CLI, authenticated as the workspace owner |

So this works in workspace shells, startup scripts, and agent tools with
zero setup:

```sh
git clone https://github.com/org/private-repo
git push        # authenticated as the workspace owner, not a bot
```

Related commands:

```sh
coder publickey                        # SSH public key (deploy keys, host allowlists)
coder external-auth access-token <id>  # raw token for non-git tooling (see below)
```

### Tokens for non-git tooling

`coder external-auth access-token <provider-id>` prints a validated access
token for scripts that talk to the GitHub API (or any other configured
provider). The provider ID is whatever the deployment admin configured —
commonly `github`. If it reports "No matching external auth provider",
either the deployment uses a custom ID or has git auth only (e.g. a GitHub
App scoped to git operations) with no general external auth provider —
ask the admin rather than inventing IDs.

Treat the output like a password: never commit it, log it, or paste it
into a template. Prefer letting tools consume it via a pipe or
environment variable.

## In template Terraform

If **provisioning** needs GitHub access (e.g. envbuilder cloning a private
devcontainer repo, or a build step cloning private code), gate workspace
creation on the user having linked GitHub with the `coder_external_auth`
data source:

```hcl
data "coder_external_auth" "github" {
  id       = "github"  # provider ID as configured in the deployment
  optional = true       # users may skip; drop this line to require it
}
```

- Without `optional = true`, workspace creation is blocked until the user
  authenticates with the provider.
- `access_token` (sensitive) is readable at plan/apply time, but prefer
  runtime access (askpass / `coder external-auth`) over passing tokens
  through Terraform state or container env vars.
- If your template only uses git at **runtime** (startup scripts, agent
  shells), you don't need this data source at all — git auth already
  works everywhere.

## Not the same as CI auth

CI pushes with a **bot identity** (`CODER_SESSION_TOKEN` — see
[`ci-cd.md`](ci-cd.md)), while workspace git runs as **the workspace
owner**. Don't reuse one for the other: workspace tokens are the user's,
CI tokens are the deployment-level bot's, and rotation/cleanup differ.
