# Coder Templates

A template repository for developing [Coder](https://coder.com) templates
with AI assistance. Create a new repo from it and you get:

- **Agent context** — `AGENTS.md` plus `context/` reference docs so AI coding
  agents (OpenCode) write correct Coder/Terraform without guessing
- **MCP servers preconfigured** — Coder (workspace/template tools for your
  deployment) and Terraform (live provider docs)
- **A working starter template** — `templates/docker/` boots a Docker
  workspace with a persistent NAS-backed home and code-server
- **CI that tests then deploys** — every push boots a real test workspace on
  your Coder instance; `main` promotes the tested version to active

## Repository layout

```
├── AGENTS.md                     # AI agent instructions (read this first)
├── opencode.jsonc                # OpenCode config: coder + terraform MCP servers
├── context/                      # deep reference docs
│   ├── coder-template-guide.md   #   template anatomy & patterns
│   ├── terraform-provider.md     #   provider schemas & gotchas
│   ├── coder-cli.md              #   CLI cheat sheet
│   ├── common-pitfalls.md        #   debugging & traps
│   ├── git-auth.md               #   GitHub auth in workspaces
│   └── ci-cd.md                  #   CI setup, secrets, token rotation
├── templates/
│   ├── docker/                   # starter template (dir name = template name)
│   └── Society/                  # Society of Actuaries exam workspace
│       ├── image/                #   Dockerfile + package manifests (built by CI)
│       └── scripts/              #   startup.sh + csv2db helper
├── icon/                         # template logos (referenced by README front matter)
├── .github/workflows/
│   ├── lint.yml                  # fmt/validate/tflint on PRs
│   ├── build-image.yml           # Society workspace image -> GHCR
│   └── publish-template.yml      # test against Coder, deploy on main
├── Makefile                      # make check / push / test-workspace
└── scripts/check.sh              # local validation
```

## Creating a repo from this template

1. Click **Use this template → Create a new repository**.
2. Configure publishing (repo → **Settings → Secrets and variables →
   Actions**):
   - **Variable** `CODER_URL` = `https://coder.actuary.dev` (your deployment).
     This is also the on/off switch — publishing stays skipped while unset.
   - **Secret** `CODER_SESSION_TOKEN` = a token for your CI identity. Follow
     the runbook in [`context/ci-cd.md`](context/ci-cd.md) to create a scoped
     bot user + token (5-minute setup, rotation documented).
3. For AI assistance in OpenCode (two one-time machine setup steps):
   - `coder login <your-url>` — the Coder MCP server uses the CLI session.
   - Install `terraform-mcp-server` into `~/.local/bin` (or have a Docker
     daemon running) — see [`context/terraform-provider.md`](context/terraform-provider.md).
   Then read `AGENTS.md`.
4. Rename/replace the starter template: edit `templates/docker/` or copy it.
   The directory name is the template name in Coder.

## Developing templates

```sh
make check                            # validate everything (same as CI lint)
make fmt                              # auto-format HCL

make push TEMPLATE=docker             # push inactive dev-<sha> version
make test-workspace TEMPLATE=docker   # boot + smoke-test it
make delete-test-workspace TEMPLATE=docker
```

Workflow: branch push → CI uploads a test version and boots a workspace from
it on your deployment; merge to `main` → the tested version is promoted to
active. The live template never changes without a passing test workspace.

## Where to look

| Task | Doc |
|------|-----|
| Create or edit a template | [`context/coder-template-guide.md`](context/coder-template-guide.md) |
| Provider schemas & gotchas | [`context/terraform-provider.md`](context/terraform-provider.md) |
| CLI commands | [`context/coder-cli.md`](context/coder-cli.md) |
| Debug boot/agent issues | [`context/common-pitfalls.md`](context/common-pitfalls.md) |
| GitHub auth in workspaces | [`context/git-auth.md`](context/git-auth.md) |
| CI, secrets, token rotation | [`context/ci-cd.md`](context/ci-cd.md) |
