# Coder template guide

The anatomy of a Coder template, the patterns used in this repository, and how
to add a new one. Read this before editing anything under `templates/`.

## What a template is

A template is a Terraform configuration that provisions a workspace:
compute, storage, and a **Coder agent** that connects back to the Coder
deployment. Coder runs the Terraform via its **provisioner**; users never run
Terraform themselves.

```
templates/<name>/            one template per directory
├── main.tf                  all Terraform (split further if it grows)
├── README.md                shown in the Coder UI (front matter sets name/icon)
└── scripts/                 startup/smoke scripts referenced via file()
```

**The directory name is the template name** pushed to Coder
(`coder templates push <name> --directory templates/<name>`).

## Lifecycle

1. `coder templates push` uploads the directory as a new **template version**.
2. One version per template is **active** — that's what new workspaces use.
3. Workspaces pin the version they were created from; users update by
   rebuilding onto the active version.
4. CI pushes every commit as a version, boots a test workspace from it, and
   only promotes it to active on `main` after the test passes (see
   `context/ci-cd.md`).

## Building blocks

### Data sources

| Source | Key attributes |
|--------|----------------|
| `data "coder_workspace" "me"` | `id`, `name`, `owner_id`, `start_count`, `access_url`, `transition` |
| `data "coder_workspace_owner" "me"` | `name`, `full_name`, `email`, `id` |
| `data "coder_provisioner" "env"` | `arch`, `os` of the provisioner host |
| `data "coder_parameter" "<p>"` | `value` (**always a string**), `id` |

### `coder_agent` (required)

The agent is the workspace's connection to Coder (SSH, apps, terminal, stats).

```hcl
resource "coder_agent" "main" {
  arch           = data.coder_provisioner.env.arch   # match the provisioner host
  os             = data.coder_provisioner.env.os
  dir            = "/home/coder"
  startup_script = file("${path.module}/scripts/startup.sh")
  startup_script_behavior = "blocking"   # recommended: wait for startup

  metadata {                            # sidebar stats, repeatable block
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
    order        = 1
  }
}
```

- The consuming resource must run `coder_agent.main.init_script` at boot and
  set `CODER_AGENT_TOKEN` from `coder_agent.main.token`.
- `startup_script_behavior`: `"blocking"` (default in our templates) keeps the
  workspace "Starting" until the script exits; `"non-blocking"` marks ready
  immediately.

### `coder_app` (browser apps)

```hcl
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"           # URL-safe, unique per agent
  display_name = "code-server"
  icon         = "${data.coder_workspace.me.access_url}/icon/code-server.svg"
  url          = "http://localhost:13377" # proxied through the agent
  share        = "owner"
  subdomain    = false
}
```

- Use `url` (proxy to a port) **or** `command` (open a terminal command) — not both.
- Built-in icons live at `${data.coder_workspace.me.access_url}/icon/<name>.svg`.
- Optional `healthcheck` blocks readiness on an HTTP endpoint.

### `coder_parameter` (workspace form inputs)

⚠️ Parameters are a **data source**, not a resource (provider 2.x).

```hcl
data "coder_parameter" "cpu" {
  name         = "cpu"          # stable ID — renaming re-prompts users
  display_name = "CPU cores"
  type         = "number"       # string | number | bool | list(string)
  default      = 2
  mutable      = true           # changeable after creation (triggers rebuild)
  order        = 2

  validation { min = 1 max = 32 }

  option {                      # optional: fixed choices
    name  = "Small"
    value = 2
  }
}
```

- `data.coder_parameter.cpu.value` is a **string** — wrap numbers with
  `tonumber()` and lists with `jsondecode()`.
- `mutable = false` values are locked after workspace creation (use for
  anything destructive, like region or disk identity).
- `ephemeral = true` values reset on every build.

## Standard resource patterns

**Start/stop**: gate expensive resources on `start_count` so they are
destroyed when the workspace stops and recreated on start:

```hcl
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  ...
}
```

**Persistence**: anything not in a volume or bind mount is lost on stop. Mount named volumes
or NAS bind mounts for home directories, caches, and state. The volume itself must *not* be gated
on `start_count`.

**Naming**: prefix resources with `coder-${data.coder_workspace.me.id}` and
label them with workspace/owner names (see `templates/docker/main.tf`).

**Secrets**: never hardcode credentials. Reference `coder_external_auth`,
Coder user secrets (injected into the agent environment at runtime),
workspace parameters the user supplies, or runtime metadata.

**Registry modules**: `registry.coder.com/coder/<name>/coder` modules (e.g.
`git-clone`, `code-server`, `git-config`) package common agent behaviors. Pin
with `version = "~> N.0"` and gate them with
`count = data.coder_workspace.me.start_count` so nothing runs at build time.

## Adding a new template

1. `cp -r templates/docker templates/<name>` and rework the resources.
2. Rename in `README.md` front matter (`display_name`, `icon`).
3. Update the parameters table in the template README.
4. Run `make check` — fmt, init, validate, tflint must all pass.
5. `make push TEMPLATE=<name>` then `make test-workspace TEMPLATE=<name>`
   to smoke-test against the deployment (optional; CI does this on push).
6. Open a PR. CI boots a real workspace from your version on the Coder
   instance; merging to `main` promotes it to active.

## Validate early, validate often

```sh
make check          # terraform fmt/init/validate + tflint for every template
make fmt           # auto-format
```

CI runs the same script (`.github/workflows/lint.yml`). A PR cannot be green
with unformatted or invalid HCL.
