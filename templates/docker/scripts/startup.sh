#!/usr/bin/env bash
# Workspace startup script (runs on every workspace start).
# Keep it idempotent: the home directory persists across starts, but
# everything else may be rebuilt from scratch.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

# --- code-server (VS Code in the browser) -----------------------------------
# Use the image's code-server if present, otherwise install a standalone copy
# into the persistent home directory.
if ! command -v code-server >/dev/null 2>&1; then
  echo "code-server not found in image, installing standalone..."
  curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix="$HOME/.local"
fi

nohup code-server \
  --auth none \
  --bind-addr 0.0.0.0:13377 \
  --disable-telemetry \
  "$HOME" >/tmp/code-server.log 2>&1 &

# --- GitHub CLI (gh) -------------------------------------------------------
# Make sure the GitHub CLI is available. Checked on every start so an
# earlier failed install heals itself: the distro package is preferred,
# with the official GitHub CLI apt repository as a fallback.
if ! command -v gh >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq || true
  if ! sudo apt-get install -y --no-install-recommends gh; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null \
      && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
      && sudo apt-get update -qq \
      && sudo apt-get install -y --no-install-recommends gh \
      || echo "Warning: could not install the GitHub CLI."
  fi
fi

# Authenticate the GitHub CLI as the workspace owner, using the GitHub
# external auth token Coder injects for the logged-in user. The token is
# written to gh's own hosts.yml config (mode 0600), so every consumer —
# shells, agents, VS Code extensions — is signed in without a manual
# `gh auth login`. Note that `gh auth login --with-token` cannot be used
# here: it validates OAuth scopes and rejects repo-scoped tokens. Git itself
# keeps using Coder's GIT_ASKPASS; gh's config only feeds gh.
if ! command -v gh >/dev/null 2>&1 || ! command -v coder >/dev/null 2>&1; then
  echo "Warning: GitHub CLI or Coder CLI missing; skipping GitHub CLI authentication."
else
  GH_TOKEN=""
  GH_PROVIDER=""
  for candidate in "${GITHUB_AUTH_ID:-}" github coder-github-oauth; do
    [ -n "$candidate" ] || continue
    if GH_TOKEN=$(coder external-auth access-token "$candidate" 2>/dev/null) && [ -n "$GH_TOKEN" ]; then
      GH_PROVIDER="$candidate"
      break
    fi
  done
  if [ -z "$GH_PROVIDER" ]; then
    echo "Warning: no GitHub external auth token for this user; 'gh' is unauthenticated. Link GitHub under Account -> External Authentication (or run 'gh auth login')."
  else
    GH_LOGIN=$(GH_TOKEN="$GH_TOKEN" gh api user --jq .login 2>/dev/null) || GH_LOGIN=""
    mkdir -p "${HOME}/.config/gh"
    printf 'github.com:\n  user: %s\n  oauth_token: %s\n  git_protocol: https\n' "$GH_LOGIN" "$GH_TOKEN" >"${HOME}/.config/gh/hosts.yml"
    chmod 600 "${HOME}/.config/gh/hosts.yml"
    echo "GitHub CLI authenticated as ${GH_LOGIN:-unknown} (external auth provider: $GH_PROVIDER)."
    unset GH_TOKEN
  fi
fi

echo "Startup complete."
