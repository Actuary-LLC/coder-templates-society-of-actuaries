# CI/CD and CI identity runbook

How automated template publishing works, how to set it up on a new Coder
deployment, and how to rotate credentials. Keep this file in sync with
`.github/workflows/`.

## The pipeline

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `lint.yml` | every PR and push to `main` | `terraform fmt -check`, `init -backend=false`, `validate`, tflint (via `scripts/check.sh`) |
| `build-image.yml` | push to `main` touching `templates/Society/**` image files (incl. `scripts/csv2db`) + manual dispatch | builds `templates/Society/image/Dockerfile` and pushes it to GHCR as `ghcr.io/actuary-llc/coder-templates-society-of-actuaries` (`latest` + `<sha>`) |
| `publish-template.yml` | every push to any branch + manual dispatch | pushes each `templates/*` as an **inactive** template version, boots a throwaway test workspace from it, smoke-tests via `coder ssh`, deletes it — and **only on `main`**, promotes the tested version to active |

So: pushing to a branch deploys a *test* version to the Coder instance;
merging to `main` promotes a version that has already booted successfully.
The active template never changes without a passing test workspace.

### The Society workspace image (`build-image.yml`)

The `Society` template boots a prebuilt image (Python, R, Julia, RStudio
Server, code-server, OpenCode, DuckDB/SQLite) built from
`templates/Society/image/Dockerfile`. The workflow publishes it to GHCR under
this repository's name — image and template live in one location.

- Auth is the built-in `GITHUB_TOKEN` (`packages: write`); no extra secret.
- Tags: `latest` (what the template's `docker_image` parameter defaults to)
  and `sha-<short-sha>`.
- **First-time / image visibility**: after the first push, open the package
  on GitHub (org → Packages) and either make it **public**, or log the
  provisioner's Docker host into GHCR — otherwise workspace creation fails
  pulling the image.
- The first build downloads torch, ~40 R packages, and ~30 Julia packages;
  expect 30–60 minutes. Later builds use the GitHub Actions cache.
- `publish-template.yml` does **not** wait for image builds. If a template
  change lands together with an image change, its test workspace may briefly
  boot the previous `:latest` — pin `docker_image` to the `sha-` tag when that
  matters.

### Template naming

Every directory under `templates/` is pushed as a template with that directory
name. Version names: `<short-sha>` on `main`, `<branch>-<short-sha>` on
feature branches.

### GitHub configuration

| Name | Type | Value | Purpose |
|------|------|-------|---------|
| `CODER_URL` | Actions **variable** | `https://coder.actuary.dev` | Deployment URL. **Also the on/off switch** — publishing is skipped while this variable is unset, so fresh template clones don't fail. |
| `CODER_ORG` | Actions **variable** (optional) | `coder` | Organization for org-scoped CLI commands (newer CLIs require `--org`). Defaults to `coder` when unset. |
| `CODER_SESSION_TOKEN` | Actions **secret** | token from the CI identity below | Auth for `coder` CLI in CI. |

Swap to another deployment by changing these two values — nothing else.

## CI identity setup (OSS deployments)

Create a dedicated machine user so CI is decoupled from any personal account
and the token can be scoped and rotated independently.

> Requires an admin session (`coder login` as an Owner).
> Note: `coder users create --service-account` (a true headless account)
> needs **Premium**. On OSS we use a regular user that only ever
> authenticates via admin-generated tokens.

```sh
# 1. Create the bot user. Login type depends on what your deployment allows:
#    password auth is often disabled, in which case use github or oidc.
coder users create --username ci-template-bot --email ci@actuary.dev --login-type github

# 2. Give it the Template Admin role (push/promote template versions).
coder users edit-roles ci-template-bot --roles template-admin --yes

# 3. Mint a long-lived, least-privilege token on its behalf.
coder tokens create --user ci-template-bot --name github-actions --lifetime 1y \
  --scope coder:apikeys.manage_self \
  --scope user:read \
  --scope coder:templates.author \
  --scope coder:templates.build \
  --scope coder:workspaces.create \
  --scope coder:workspaces.delete \
  --scope coder:workspaces.access
```

What the scopes cover:

| Scope | Allows CI to |
|-------|--------------|
| `coder:apikeys.manage_self` | exchange the token for a session (`coder login --token`, run by `coder/setup-action`) |
| `user:read` | resolve its own user during that exchange — without it the login fails with "Resource not found" |
| `coder:templates.author` | upload template files, create/update template versions (incl. promote) |
| `coder:templates.build` | run validation builds |
| `coder:workspaces.create` | create the throwaway test workspace |
| `coder:workspaces.delete` | delete it afterwards |
| `coder:workspaces.access` | `coder ssh` into it for the smoke test |

The bot's Template Admin role is its permission ceiling; the scopes narrow it
to exactly the CI workflow. It only ever creates and deletes workspaces *it*
owns.

### Add the values to GitHub

```sh
# From a checkout authenticated to GitHub (gh CLI):
gh secret set CODER_SESSION_TOKEN --body '<token>'
gh variable set CODER_URL --body 'https://coder.actuary.dev'
```

Or in the UI: repo → **Settings → Secrets and variables → Actions** →
Secrets: `CODER_SESSION_TOKEN`; Variables: `CODER_URL`.

## Token rotation runbook

Tokens expire (`--lifetime 1y` above; your deployment may enforce a maximum).
Rotate proactively — `coder tokens list --all` shows expiry dates:

```sh
# 1. Mint a replacement (same scopes)
coder tokens create --user ci-template-bot --name github-actions-$(date +%Y%m) --lifetime 1y \
  --scope coder:apikeys.manage_self --scope user:read \
  --scope coder:templates.author --scope coder:templates.build \
  --scope coder:workspaces.create --scope coder:workspaces.delete \
  --scope coder:workspaces.access

# 2. Update the GitHub secret (takes effect on the next workflow run)
gh secret set CODER_SESSION_TOKEN --body '<new-token>'

# 3. Expire the old one (use --delete to hard-delete instead)
coder tokens remove <old-token-name-or-id>
```

No downtime: the secret change applies to new runs immediately.

### Emergency rotation

If a token leaks (e.g. committed or logged): remove it first
(`coder tokens remove <id>`), then mint and install a replacement. CI runs
will fail until the secret is updated — that's the safe failure mode.

## Premium deployments (optional)

If you ever upgrade: replace the bot user with a true service account —

```sh
coder users create --username ci-template-bot --service-account
coder users edit-roles ci-template-bot --roles template-admin --yes
# then the same tokens create / rotation flow
```

## Local equivalents

```sh
make check                          # lint everything (what lint.yml runs)
make push TEMPLATE=docker           # push an inactive dev-<sha> version
make test-workspace TEMPLATE=docker # boot + smoke-test it
make delete-test-workspace TEMPLATE=docker
```

Local pushes use your own `coder login` session; they never promote.

## Troubleshooting

- **Workflow skipped**: `CODER_URL` variable is unset (by design).
- **`Must select an organization with --org`**: newer CLIs require explicit org
  selection for org-scoped commands — set the `CODER_ORG` variable (defaults
  to `coder`).
- **`Unauthorized` from coder CLI in CI**: token expired or secret missing —
  run `coder tokens list --all` and check the `CODER_SESSION_TOKEN` secret.
- **Test workspace fails to boot**: the template itself is broken — read the
  job log (`::group::Template: <name>` section) and the workspace build page
  on the deployment. See `context/common-pitfalls.md`.
- **Push fails with "version already exists"**: version names must be unique;
  don't reuse SHAs across force-pushes — amend the commit instead.
- **Leftover `ci-*` workspaces**: safe to delete; the workflow cleans up on
  failure but not on hard cancellation.
- **Workspace creation fails with "image not found" / pull errors**: the
  Society image is missing or private — check the `build-image` workflow run
  and the package visibility note above.
