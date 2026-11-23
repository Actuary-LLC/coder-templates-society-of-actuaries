# Docker starter template
#
# Boots a workspace as a Docker container with a persistent NAS-backed home,
# code-server in the browser, and live CPU/RAM/disk metadata.
#
# The directory name ("docker") is the template name pushed to Coder.
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

###############################################################################
# Parameters (rendered in the "Create workspace" form)
###############################################################################

data "coder_parameter" "docker_image" {
  name         = "docker_image"
  display_name = "Container image"
  description  = "Image to boot the workspace from. Must be a Linux image with a POSIX shell."
  icon         = "${data.coder_workspace.me.access_url}/icon/docker.svg"
  default      = "codercom/enterprise-base:ubuntu"
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
  description  = "Memory limit for the workspace container."
  type         = "number"
  default      = 4
  mutable      = true
  order        = 3

  validation {
    min = 1
    max = 64
  }
}

###############################################################################
# Agent and apps
###############################################################################

resource "coder_agent" "main" {
  arch = data.coder_provisioner.env.arch
  os   = data.coder_provisioner.env.os
  dir  = "/home/coder"

  startup_script = file("${path.module}/scripts/startup.sh")

  # Provider ID consumed by scripts/startup.sh to sign the GitHub CLI in as
  # the workspace owner; empty means auto-detect.
  env = {
    GITHUB_AUTH_ID = var.github_auth_id
  }

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
  icon         = "${data.coder_workspace.me.access_url}/icon/code-server.svg"
  url          = "http://localhost:13377"
  share        = "owner"
  subdomain    = false

  healthcheck {
    url       = "http://localhost:13377/healthz"
    interval  = 5
    threshold = 6
  }
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
  shm_size   = 512

  volumes {
    host_path      = local.home_path
    container_path = "/home/coder"
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
