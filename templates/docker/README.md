---
display_name: "Docker"
icon: "/icon/docker.svg"
---

# Docker

A workspace running as a Docker container with:

- a persistent home (`/home/coder`) bind-mounted from the NAS
  (`/mnt/user/docker/volumes/coder/workspaces/<owner>/<name>`) that survives
  stops and rebuilds without consuming host OS disk
- [code-server](https://github.com/coder/code-server) in the browser
- the [GitHub CLI](https://cli.github.com/) (`gh`), signed in as your GitHub
  identity via the deployment's GitHub external auth
- live CPU, RAM, and disk usage in the workspace sidebar

## Parameters

| Parameter | Default | Mutable | Description |
|-----------|---------|---------|-------------|
| `docker_image` | `codercom/enterprise-base:ubuntu` | yes | Container image to boot from. Must be Linux with a POSIX shell and `curl` or `wget`. |
| `cpu` | `2` | yes | Relative CPU weight (`cpu_shares`). |
| `memory` | `4` | yes | Memory limit in GB. |

*Mutable* parameters can be changed after workspace creation (triggering a rebuild).

The template also accepts a build-time variable: `github_auth_id`, the ID of
the GitHub external auth provider configured on the Coder deployment (empty
auto-detects `github`, then `coder-github-oauth`).

## How it works

The workspace is a `docker_container` that runs `coder_agent`'s init script as
its entrypoint. The agent token is passed via the `CODER_AGENT_TOKEN`
environment variable. Stopping the workspace destroys the container
(`count = start_count`); a NAS bind mount holds `/home/coder` so files and
installed tools persist without consuming host OS disk.

## Customizing

- **More persistence**: add `docker_volume` resources and `volumes` blocks
  (e.g. for `/var/lib/docker`, caches, or a second disk).
- **Preinstalled tools**: bake them into a custom image and make it the
  parameter default, or add installation steps to `scripts/startup.sh`.
- **More apps**: add `coder_app` resources (URL-based or command-based).

See [`../../context/coder-template-guide.md`](../../context/coder-template-guide.md)
for the full template anatomy and
[`../../context/common-pitfalls.md`](../../context/common-pitfalls.md) before
restructuring.

## Troubleshooting

- **`gh` is not authenticated**: run `gh auth status` — it should list your
  GitHub account (the sign-in writes `~/.config/gh/hosts.yml` at every
  workspace start from the deployment's GitHub external auth provider). If
  yours uses a custom provider ID, set the `github_auth_id` build-time
  variable; check the startup script output for the sign-in line. The `Missing
  required token scopes: 'read:org'` warning in `gh auth status` is cosmetic
  for repository work (PRs, issues, `gh api`).
- **Workspace stuck "Connecting"**: check the startup script — readiness is
  blocking (`startup_script_behavior = "blocking"`) until it exits. Inspect
  logs with `coder show <workspace>` or the build page in the dashboard.
- **code-server won't open**: `/tmp/code-server.log` inside the workspace has
  its logs.
