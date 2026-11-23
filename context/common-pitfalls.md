# Common pitfalls

Things that routinely go wrong when developing Coder templates — and how to
avoid or fix them.

## Agent / boot issues

**Workspace stuck "Connecting" or "Starting".**
The agent never came up. Checklist:

1. Does the container actually run `coder_agent.main.init_script`? The
   entrypoint must execute it (`["/bin/sh", "-c", coder_agent.main.init_script]`).
2. Is `CODER_AGENT_TOKEN` set from `coder_agent.main.token`?
3. Does the image have a POSIX shell and `curl` or `wget`? The init script
   downloads the agent binary from the Coder deployment.
4. Can the container reach the Coder URL (egress/proxy/firewall)?
5. Read logs: `coder show <workspace>`, `coder logs <workspace>`, or the
   workspace build page (provisioner logs) in the dashboard.

**"Blocking" startup hides errors.**
`startup_script_behavior = "blocking"` keeps the workspace "Starting" until
the script exits. If the script fails, users see a running workspace that
never becomes ready. Make the script `set -euo pipefail`, fail loudly, and
test it. If startup must not block, use `"non-blocking"`.

**Startup script must be idempotent.**
It re-runs on every workspace *start*, but only `/home/coder` (or whatever
you mount) persists. Guard installs with `command -v` checks or install into
the persistent volume.

## Persistence traps

**Everything outside mounted paths is destroyed on stop.**
The standard `count = data.coder_workspace.me.start_count` pattern deletes
the container when the workspace stops. Caches, `/tmp`, installed packages —
gone. Mount volumes or bind mounts for anything that must survive.

**Bind-mounted homes outlive workspaces.**
We bind-mount `/mnt/user/docker/volumes/coder/workspaces/<owner>/<name>` for
`/home/coder`. Deleting a workspace from the UI deletes its Terraform
resources but *not* the NAS folder — clean up manually when the data is no
longer needed.

**Root-squashed NFS blocks Docker's auto-created mount paths.**
Docker `chown`s bind-mount directories it creates, which fails over a
root-squashed NFS export ("operation not permitted"). Pre-create the
directory — Docker skips creation and chown when the path already exists.
`local-exec` cannot do this: Terraform runs on the provisioner host, which
does not see the NAS mount. `templates/docker` creates the dir through the
Docker daemon in a throwaway container instead (mounting the *pre-existing*
parent is always safe — no chown involved).

## Parameters

**Parameter values are strings.**
`data.coder_parameter.x.value` is always a string: use `tonumber()` for math,
`jsondecode()` for lists. Terraform will happily do string concatenation where
you expected arithmetic — validate output.

**Renaming a parameter resets user values.**
`name` is the stable ID. Rename it and every user is re-prompted (and
workspace builds may change). Change `display_name` instead.

**`mutable` has teeth.**
`mutable = false` locks the value at workspace creation. Great for identity
(disk names, regions); annoying if you later want users to resize CPU — set
resources to rebuild accordingly.

## Terraform hygiene

**Run `make check` before pushing.**
CI fails on `terraform fmt` drift and invalid configs. `make fmt` fixes
formatting.

**Commit `.terraform.lock.hcl`.**
`coder templates push` warns without it. Lockfiles make CI builds
reproducible (see `context/terraform-provider.md`).

**Version names must be unique.**
Re-pushing an existing version name errors. Let CI derive names from git SHAs,
or use a fresh name locally.

**Template name = directory name.**
`coder templates push docker --directory templates/docker`. Renaming the
directory creates a *new* template on the next push; the old one is orphaned.

## Docker-specific

**Docker socket is root-equivalent.**
A template that talks to the Docker socket effectively grants root on the
provisioner host. Anything user-supplied in such templates is code execution —
keep parameters trusted, and consider external provisioners for untrusted
users.

**`memory` is in MB, `shm_size` in MB, `cpu_shares` is a weight, not cores.**
To emulate core limits look at `cpu_set`/cgroup options or the container
runtime's quota settings; `cpu_shares` only competes for CPU under contention.

**Image must match the provisioner architecture.**
The agent uses `data "coder_provisioner" "env".arch`. On ARM hosts, x86-only
images fail at pull/run. Consider multi-arch images in the parameter default.

## CI/CD

**Pushing to `main` = deploying.**
Every push to `main` becomes the active template version after its test
workspace passes. Review before merging; use PRs.

**CI workspace cleanup.**
The workflow deletes its throwaway workspaces even on failure (`|| true`
paths). If a run is cancelled mid-flight, a `ci-*` workspace may linger —
delete it manually.

**Secrets live in GitHub, never in the repo.**
`.env` is gitignored for local use. CI reads `CODER_SESSION_TOKEN` from
Actions secrets. If a token ever lands in a commit, rotate it immediately
(rotation runbook: `context/ci-cd.md`).
