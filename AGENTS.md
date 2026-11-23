# AGENTS.md

Guidance for AI coding agents (OpenCode et al.) working in this repository.

## What this repository is

A GitHub template repository for developing **Coder templates** with AI
assistance. Repos created from it come with this agent context, MCP servers,
a working Docker starter template, and CI that tests and publishes templates
to a Coder deployment.

## Layout

| Path | Purpose |
|------|---------|
| `templates/<name>/` | One Coder template per directory. **Directory name = template name** pushed to Coder. |
| `context/` | Deep reference docs. Read the relevant one before starting work (table below). |
| `opencode.jsonc` | OpenCode config: MCP servers (`coder`, `terraform`). |
| `.github/workflows/` | `lint.yml` (PRs) and `publish-template.yml` (every push tests against the Coder instance; `main` promotes). |
| `scripts/check.sh`, `Makefile` | Local validation and dev shortcuts. |

## Workflow rules

1. **Read before you write.** Before editing Terraform, read
   `context/coder-template-guide.md`. Provider schemas change —
   `coder_parameter` is a *data source*, `metadata` is a *block*. When unsure
   about a resource or attribute, check `context/terraform-provider.md` or ask
   the Terraform MCP server instead of guessing.
2. **Validate before you finish.** After any change under `templates/`, run
   `make check` (or `./scripts/check.sh`) and fix every finding. Never leave
   unformatted HCL (`make fmt` fixes formatting).
3. **Never commit secrets** or Terraform state/override files. `.env` is
   gitignored; `.env.example` is the reference. If a credential ever lands in
   a commit, say so loudly and point at the rotation runbook in
   `context/ci-cd.md`.
4. **Renaming `templates/<x>` renames the template.** Call it out explicitly —
   CI pushes by directory name and a rename orphans the old template.
5. **Parameter changes ripple.** When you add/change/remove a
   `coder_parameter`, update the parameter table in that template's
   `README.md`.
6. **Keep the runbook truthful.** When touching workflows, secrets, or setup
   steps, update `context/ci-cd.md` in the same change.
7. **Testing against the deployment** (optional; needs auth): `make push
   TEMPLATE=<name>` then `make test-workspace TEMPLATE=<name>`. Never promote
   versions manually — CI promotes after its test workspace passes.
8. **Use the MCP servers when available**: `coder` (inspect templates,
   workspaces, and versions on the deployment) and `terraform` (live provider
   docs). Note MCP tools are not available in every session — fall back to
   the `context/` docs and the CLI (`coder --help`).

## Where to look

| Task | Read first |
|------|------------|
| Create or edit a template | `context/coder-template-guide.md` |
| Provider resources and schema gotchas | `context/terraform-provider.md` |
| Coder CLI commands | `context/ci-cd.md`, `context/coder-cli.md` |
| Debug boot/agent issues | `context/common-pitfalls.md` |
| Git/GitHub auth in workspaces | `context/git-auth.md` |
| CI, secrets, token setup/rotation | `context/ci-cd.md` |
