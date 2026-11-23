# Society of Actuaries template
#
# Boots a workspace for SOA coding exams (ATPA, PA, SRM) from a prebuilt
# image with Python, R, Julia, RStudio Server, code-server, OpenCode (wired
# to LiteLLM), and DuckDB/SQLite/SQL tooling. Optionally clones a GitHub
# repository into the persistent NAS-backed home.
#
# The directory name ("Society") is the template name pushed to Coder.
# See ../../context/coder-template-guide.md for the anatomy of a template
# and ../../context/common-pitfalls.md before making structural changes.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

locals {
  home_dir = "/home/coder"

  # OpenCode's background service serves the web UI on this port; the same
  # service backs the CLI, so web and terminal sessions are shared.
  opencode_port = 4096

  # Strip query parameters and fragments, an optional /tree/<branch> (GitHub)
  # or /-/tree/<branch> (GitLab) suffix, and the .git extension to derive the
  # folder the repository is cloned into.
  repo_url_clean   = replace(replace(data.coder_parameter.git_repo_url.value, "/\\?.*/", ""), "/#.*/", "")
  repo_url_no_tree = replace(local.repo_url_clean, "/(/-)?/tree/.*/", "")
  repo_folder      = data.coder_parameter.git_repo_url.value == "" ? "" : trimsuffix(basename(local.repo_url_no_tree), ".git")
  # The repository is cloned into ~/<name>. Without a repository URL the
  # workspace simply opens in the home directory.
  repo_dir = local.repo_folder == "" ? local.home_dir : "${local.home_dir}/${local.repo_folder}"
}

###############################################################################
# Workspace context
###############################################################################

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

data "coder_provisioner" "env" {}

###############################################################################
# Build-time variables (set at `coder templates push` time)
###############################################################################

variable "github_auth_id" {
  description = "ID of the GitHub external auth provider configured on the Coder deployment. Leave empty to auto-detect (tries `github`, then `coder-github-oauth`)."
  type        = string
  default     = ""
}

variable "litellm_api_key" {
  description = "Fallback LiteLLM API key when Coder user secrets are not used. Prefer the LITELLM_API_KEY user secret."
  type        = string
  default     = ""
  sensitive   = true
}

###############################################################################
# Parameters (rendered in the "Create workspace" form)
###############################################################################

data "coder_parameter" "docker_image" {
  name         = "docker_image"
  display_name = "Container image"
  description  = "Workspace image with Python, R, Julia, RStudio Server, code-server, OpenCode, and database tooling."
  icon         = "${data.coder_workspace.me.access_url}/icon/docker.svg"
  default      = "ghcr.io/actuary-llc/coder-templates-society-of-actuaries:latest"
  mutable      = true
  order        = 1
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU cores"
  description  = "Relative CPU weight for the workspace container."
  type         = "number"
  icon         = "${data.coder_workspace.me.access_url}/icon/cpu.svg"
  default      = 2
  mutable      = true
  order        = 2

  validation {
    min = 1
    max = 32
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Memory limit for the workspace container. 8 GB is a comfortable floor for R/Julia/PyTorch work."
  type         = "number"
  default      = 8
  mutable      = true
  order        = 3

  validation {
    min = 1
    max = 64
  }
}

data "coder_parameter" "git_repo_url" {
  name         = "git_repo_url"
  display_name = "Repository"
  description  = "(Optional) The Git repository to clone into ~/<name> on every workspace start. Leave empty for a plain workspace with no clone. Use an HTTPS GitHub URL (with Coder GitHub external auth configured), optionally with /tree/<branch> to clone a specific branch. When set, code-server, RStudio, and OpenCode all open here."
  default      = ""
  icon         = "${data.coder_workspace.me.access_url}/icon/github.svg"
  mutable      = true
  order        = 4
}

data "coder_parameter" "litellm_base_url" {
  name         = "litellm_base_url"
  display_name = "LiteLLM base URL"
  description  = "Base URL of your LiteLLM proxy without the /v1 suffix. OpenCode, code-server (Continue), and R (ellmer) route model requests to this gateway. The default uses the shared 'litellm' overlay network (the service publishes no ports)."
  default      = "http://litellm_main:4000"
  icon         = "/emojis/1f916.png"
  mutable      = true
  order        = 5
}

###############################################################################
# Agent and apps
###############################################################################

resource "coder_agent" "main" {
  arch = data.coder_provisioner.env.arch
  os   = data.coder_provisioner.env.os
  dir  = local.repo_dir

  startup_script = file("${path.module}/scripts/startup.sh")

  env = merge(
    {
      # Consumed by scripts/startup.sh to sign the GitHub CLI in as the
      # workspace owner; empty means auto-detect.
      GITHUB_AUTH_ID = var.github_auth_id
      # LiteLLM gateway shared by OpenCode, code-server, and R (ellmer).
      LITELLM_BASE_URL = data.coder_parameter.litellm_base_url.value
      # Prefer the LITELLM_API_KEY Coder user secret (injected at runtime);
      # this is only the build-time fallback.
      # Persistent user depot first so user-added Julia packages survive
      # container rebuilds; the image's baked depot stays available after it.
      JULIA_DEPOT_PATH = "/home/coder/.julia:/opt/julia-depot"
      # csv2db helper source, for images that do not bake it in.
      CSV2DB_B64 = base64encode(file("${path.module}/scripts/csv2db"))
      # Git identity for commits made in the workspace.
      GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
      GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
      GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
      GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
    },
    var.litellm_api_key != "" ? { LITELLM_API_KEY = var.litellm_api_key } : {},
  )

  # Block readiness until the startup script exits, so users never land in a
  # half-provisioned workspace.
  startup_script_behavior = "blocking"

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
    order        = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
    order        = 2
  }

  metadata {
    display_name = "Home Disk"
    key          = "home_disk"
    script       = "coder stat disk /home/coder"
    interval     = 600
    timeout      = 10
    order        = 3
  }
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  icon         = "${data.coder_workspace.me.access_url}/icon/code.svg"
  url          = "http://localhost:13377"
  share        = "owner"
  subdomain    = false
  order        = 2

  healthcheck {
    url       = "http://localhost:13377/healthz"
    interval  = 5
    threshold = 6
  }
}

# Open-source RStudio Server in single-user mode (auth disabled; the process
# runs as the workspace user).
resource "coder_app" "rstudio" {
  agent_id     = coder_agent.main.id
  slug         = "rstudio"
  display_name = "RStudio"
  icon         = "${data.coder_workspace.me.access_url}/icon/rstudio.svg"
  url          = "http://localhost:8787"
  share        = "owner"
  subdomain    = false
  order        = 1

  healthcheck {
    # /favicon.ico answers 200 for any client; / redirects non-browser
    # user agents, which would read as unhealthy.
    url       = "http://localhost:8787/favicon.ico"
    interval  = 5
    threshold = 12
  }
}

# OpenCode 2.x serves its own web UI from its shared background service; the
# same service backs the CLI app, so web and terminal sessions are shared.
# See https://opencode.ai/v2/docs/cli/web
resource "coder_app" "opencode" {
  agent_id     = coder_agent.main.id
  slug         = "opencode"
  display_name = "OpenCode"
  icon         = "${data.coder_workspace.me.access_url}/icon/opencode.svg"
  url          = "http://localhost:${local.opencode_port}"
  open_in      = "tab"
  order        = 3
}

resource "coder_app" "opencode_cli" {
  agent_id     = coder_agent.main.id
  slug         = "opencode-cli"
  display_name = "OpenCode CLI"
  icon         = "${data.coder_workspace.me.access_url}/icon/opencode.svg"
  open_in      = "slim-window"
  order        = 4
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    export PATH="$${HOME}/.opencode/bin:$${PATH}"
    cd "${local.repo_dir}" 2> /dev/null || cd "$${HOME}"
    # Resume the workspace's single session (created on first launch).
    exec opencode --continue
  EOT
}

###############################################################################
# Repository clone (optional; no-op when git_repo_url is empty)
###############################################################################

# See https://registry.coder.com/modules/coder/git-clone
module "git-clone" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/coder/git-clone/coder"
  version     = "~> 2.0"
  agent_id    = coder_agent.main.id
  url         = data.coder_parameter.git_repo_url.value
  base_dir    = local.home_dir
  folder_name = local.repo_folder
}

###############################################################################
# Docker resources
###############################################################################

# The workspace home is bind-mounted from the NAS so files survive workspace
# stops and rebuilds without consuming host OS disk. Everything outside
# /home/coder is lost when the container is destroyed on stop.
#
# The NAS export is root-squashed: Docker cannot chown the mount source it
# auto-creates ("operation not permitted"), so the directory must exist
# before the container starts. It is created through the Docker daemon in a
# throwaway container — local-exec cannot do this because Terraform runs on
# the provisioner host, which does not see the NAS mount. The workspaces
# parent is owned by the daemon's squashed root (99), so a root-running
# container can create subdirectories; mode 0777 keeps the dir usable for
# any workspace UID over sec=sys NFS.
locals {
  home_dir_root = "/mnt/user/docker/volumes/coder/workspaces"
  home_name     = "${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}"
  home_path     = "${local.home_dir_root}/${local.home_name}"
}

resource "docker_image" "home_dir" {
  name         = "busybox:1.37"
  keep_locally = true
}

resource "docker_container" "home_dir" {
  count = data.coder_workspace.me.start_count

  name       = "coder-home-dir-${data.coder_workspace.me.id}"
  image      = docker_image.home_dir.image_id
  entrypoint = ["/bin/sh", "-c", "mkdir -p '/ws/${local.home_name}' && chmod 0777 '/ws/${local.home_name}'"]
  must_run   = false

  volumes {
    host_path      = local.home_dir_root
    container_path = "/ws"
  }
}

resource "docker_image" "main" {
  name         = data.coder_parameter.docker_image.value
  keep_locally = true
}

resource "docker_container" "workspace" {
  # Destroy the container when the workspace stops; recreate on start.
  count = data.coder_workspace.me.start_count

  depends_on = [docker_container.home_dir]

  image    = docker_image.main.image_id
  name     = "coder-${data.coder_workspace.me.id}"
  hostname = data.coder_workspace.me.name

  # Bootstrap the Coder agent inside the container.
  entrypoint = ["/bin/sh", "-c", coder_agent.main.init_script]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]

  cpu_shares = tonumber(data.coder_parameter.cpu.value) * 1024
  memory     = tonumber(data.coder_parameter.memory.value) * 1024
  shm_size   = 1024

  volumes {
    host_path      = local.home_path
    container_path = "/home/coder"
  }

  # Reach LiteLLM over the shared overlay network: the litellm service has no
  # published ports (admin UI is lan-only via traefik), and container-to-
  # container traffic over the overlay (http://litellm_main:4000) avoids DNS
  # hairpin NAT and its TLS/streaming instability entirely. The network is
  # external and attachable: `docker network create -d overlay --attachable litellm`.
  networks_advanced {
    name = "litellm"
  }

  labels {
    label = "coder_workspace_id"
    value = data.coder_workspace.me.id
  }

  labels {
    label = "coder_workspace_name"
    value = data.coder_workspace.me.name
  }

  labels {
    label = "coder_workspace_owner"
    value = data.coder_workspace_owner.me.name
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id

  item {
    key   = "Repository"
    value = data.coder_parameter.git_repo_url.value != "" ? data.coder_parameter.git_repo_url.value : "(none)"
  }

  item {
    key   = "Workdir"
    value = local.repo_dir
  }

  item {
    key   = "OpenCode web login"
    value = "user: opencode, password: OPENCODE_PASSWORD secret or ~/.config/opencode/web-password"
  }
}
