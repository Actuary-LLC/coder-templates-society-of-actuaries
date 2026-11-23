# Terraform providers used by Coder templates

Quick reference for the two providers every template here uses. For anything
not covered, consult live provider docs via the **Terraform MCP server**
(`terraform_getProviderDocs` tools) or the registry — do not guess schemas.

- `coder/coder` — <https://registry.terraform.io/coder/coder>
- `kreuzwerker/docker` — <https://registry.terraform.io/kreuzwerker/docker>

The Terraform MCP server is launched through `scripts/mcp-terraform.sh`, which
uses the pre-compiled `terraform-mcp-server` binary when it is on `PATH`
(install from <https://releases.hashicorp.com/terraform-mcp-server/>) and
falls back to the `hashicorp/terraform-mcp-server` Docker image when a Docker
daemon is available. A workspace without either will show the `terraform` MCP
server as failed in `opencode mcp list`.

## coder/coder (current: 2.x)

Pin with `~> 2.0`. Source: <https://github.com/coder/terraform-provider-coder>.

### Resources

| Resource | Purpose |
|----------|---------|
| `coder_agent` | Workspace agent: connection back to Coder, startup script, stats |
| `coder_agent_instance` | Bind agents to instance identity (AWS/GCP/Azure) auth |
| `coder_app` | Browser app (URL proxy or terminal command) |
| `coder_script` | Standalone script with its own run-on-start/stop semantics |
| `coder_metadata` | Static metadata rows in the UI |
| `coder_devcontainer` | Devcontainer-based workspace source |
| `coder_env` | Environment variable definitions |
| `coder_external_agent` | Agent for machines Coder doesn't provision |

### Data sources

| Data source | Purpose |
|-------------|---------|
| `coder_workspace` | Current workspace: `id`, `name`, `start_count`, `access_url`, `transition` |
| `coder_workspace_owner` | Owner: `name`, `full_name`, `email`, `id` |
| `coder_provisioner` | Provisioner host: `arch`, `os` |
| `coder_parameter` | **User-defined parameter** — `value` (string) |
| `coder_workspace_preset` | Parameter presets for one-click workspace creation |
| `coder_external_auth` | OAuth token for a configured external auth provider |
| `coder_workspace_tags` | Provisioner tags for job routing |
| `coder_script_order` | Ordering between scripts |

### Schema gotchas (2.x)

- `coder_parameter` is a **data source**. Older examples use
  `resource "coder_parameter"` — that still works but is legacy; use
  `data "coder_parameter"` and `data.coder_parameter.<name>.value`.
- Parameter `value` is always a **string**: `tonumber()`, `jsondecode()` as needed.
- `coder_agent.metadata` is a **block list** (`metadata { ... }`), not a map.
- `coder_agent` requires `os` and `arch`; take them from
  `data "coder_provisioner" "env"` so the agent matches the provisioner host.
- `coder_app`: `url` and `command` are mutually exclusive; `subdomain = true`
  needs wildcard DNS on the deployment.
- `startup_script` is an alias for a `coder_script` with `run_on_start = true`;
  prefer `startup_script` for simple cases.

## kreuzwerker/docker (current: 3.x)

Pin with `~> 3.0`. Used by `templates/docker`.

| Resource | Notes |
|----------|-------|
| `docker_image` | `keep_locally = true` avoids re-pulls on restart |
| `docker_volume` | Mount with a nested `volumes { volume_name, container_path }` block |
| `docker_container` | `entrypoint`/`command` are lists; `cpu_shares` (weight), `memory` (MB), `shm_size` (MB) |

- With no `provider "docker"` block, the provider uses the local socket
  (`/var/run/docker.sock`). The provisioner host must have Docker access.
- In 3.x, `labels` is a repeated **block** (`labels { label = ... value = ... }`),
  not a map like in 2.x.
- The provider destroys containers on `count = 0` — the standard
  `count = data.coder_workspace.me.start_count` pattern intentionally deletes
  the container on workspace stop.

## Lockfiles

Commit `.terraform.lock.hcl` for each template. `coder templates push` warns
when it is missing (`--ignore-lockfile` suppresses it, but we don't).
Regenerate with `terraform providers lock -platform=linux_amd64 -platform=linux_arm64`
inside the template directory if provider versions change.

## Version pinning policy

- `coder/coder`: `~> 2.0` (provider follows the deployment's capabilities).
- `kreuzwerker/docker`: `~> 3.0`.
- `required_version` for Terraform: `>= 1.5.0`.
- Bump pins deliberately via PR; CI runs `terraform init` fresh each run.
