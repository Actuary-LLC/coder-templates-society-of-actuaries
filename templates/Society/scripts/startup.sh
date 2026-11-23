#!/usr/bin/env bash
# Workspace startup script (runs on every workspace start).
# Keep it idempotent: the home directory persists across starts, but the
# container filesystem may be rebuilt from scratch. Heavy tooling (Python,
# R, Julia, RStudio Server, code-server, OpenCode) is baked into the image
# (image/Dockerfile); this script only starts services and wires up LiteLLM.
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

# Install the extensions that make code-server match the exam toolchain.
# Idempotent: code-server skips extensions that are already present.
if command -v code-server >/dev/null 2>&1; then
  for ext in ms-python.python REditorSupport.r julialang.language-julia Continue.continue; do
    code-server --install-extension "$ext" >/dev/null 2>&1 \
      || echo "Warning: could not install code-server extension $ext."
  done
fi

# --- RStudio Server ---------------------------------------------------------
# Single-user mode: rserver runs with authentication disabled (--auth-none)
# and drops privileges to the workspace user (--server-user). Started via
# sudo -E so RStudio sessions inherit the agent environment (LiteLLM vars,
# JULIA_DEPOT_PATH, ...). The image's /etc/rstudio/rserver.conf sets the
# default port, auth-none, and the R path.
if ! pgrep -f '[r]server --www-port' >/dev/null 2>&1 && [ -x /usr/lib/rstudio-server/bin/rserver ]; then
  sudo mkdir -p /tmp/rstudio-server
  sudo -E /usr/lib/rstudio-server/bin/rserver \
    --www-port=8787 \
    --auth-none=1 \
    --server-data-dir=/tmp/rstudio-server \
    --server-user=coder \
    --rsession-which-r=/usr/bin/R \
    || echo "Warning: RStudio Server failed to start (see /var/log/rstudio/rstudio-server/rserver.log)."
fi

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

# --- OpenCode (AI assistant wired to LiteLLM) -------------------------------
# Install OpenCode if the image does not provide it. https://opencode.ai/install
# only serves OpenCode 1.x; the 2.x line installs from /v2/install.
if ! command -v opencode >/dev/null 2>&1; then
  echo "OpenCode not found in image, installing..."
  curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path \
    || echo "Warning: OpenCode installation failed."
fi

# Make OpenCode available in every shell.
for rc in "${HOME}/.bashrc" "${HOME}/.profile"; do
  touch "$rc" 2>/dev/null || true
  grep -qF '.opencode/bin' "$rc" 2>/dev/null || echo 'export PATH="$HOME/.opencode/bin:$PATH"' >>"$rc" || true
done
export PATH="${HOME}/.opencode/bin:${PATH}"

OPENCODE_PORT=4096

# Write the OpenCode configuration (LiteLLM provider + default model).
CONFIG="${HOME}/.config/opencode/opencode.json"
mkdir -p "${HOME}/.config/opencode"
cat >"$CONFIG" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "update": "disable",
  "model": "litellm/mimo-v2.6-pro",
  "providers": {
    "litellm": {
      "name": "LiteLLM",
      "env": ["LITELLM_API_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "${LITELLM_BASE_URL:-http://litellm_main:4000}/v1",
        "apiKey": "{env:LITELLM_API_KEY}"
      },
      "models": {
        "mimo-v2.6-pro": { "name": "mimo-v2.6-pro" }
      }
    }
  }
}
EOF

# Register every model the LiteLLM proxy exposes so the full catalog is
# available in OpenCode's model picker.
if [ -z "${LITELLM_API_KEY:-}" ] || [ -z "${LITELLM_BASE_URL:-}" ] || ! command -v jq >/dev/null 2>&1; then
  echo "Skipping LiteLLM model discovery (jq, LITELLM_API_KEY, or LITELLM_BASE_URL missing)."
else
  DISCOVERED=$(curl -fsS -H "Authorization: Bearer ${LITELLM_API_KEY}" "${LITELLM_BASE_URL}/v1/models" 2>/dev/null | jq '[.data[]?.id | select(. != null) | {key: ., value: {name: .}}] | from_entries' 2>/dev/null || echo "{}")
  if [ -z "${DISCOVERED}" ] || [ "${DISCOVERED}" = "{}" ]; then
    echo "Warning: could not discover LiteLLM models at ${LITELLM_BASE_URL}/v1/models; keeping only the configured default model."
  else
    jq --argjson extra "${DISCOVERED}" '.providers.litellm.models = ((.providers.litellm.models // {}) + $extra)' "$CONFIG" >"$CONFIG.tmp" \
      && mv "$CONFIG.tmp" "$CONFIG" \
      && echo "Registered $(jq '.providers.litellm.models | length' "$CONFIG") LiteLLM models in OpenCode." \
      || echo "Warning: could not merge the discovered LiteLLM models."
  fi
fi

# Protect the web UI with the OPENCODE_PASSWORD user secret when set,
# otherwise generate a password once and keep it next to the config.
PW_FILE="${HOME}/.config/opencode/web-password"
if [ -n "${OPENCODE_PASSWORD:-}" ]; then
  echo "Using the OPENCODE_PASSWORD user secret to protect the web UI."
elif [ -s "$PW_FILE" ]; then
  echo "Using the web password in $PW_FILE (user: opencode)."
else
  head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24 >"$PW_FILE" || true
  chmod 600 "$PW_FILE" || true
  echo "Generated a web password in $PW_FILE (user: opencode)."
fi
WEB_PASSWORD="${OPENCODE_PASSWORD:-$(cat "$PW_FILE" 2>/dev/null || true)}"

# Start OpenCode's shared background service. It serves the web UI and
# owns sessions for every OpenCode client.
if command -v opencode >/dev/null 2>&1; then
  opencode service set hostname 127.0.0.1 || echo "Warning: could not set the OpenCode service hostname."
  opencode service set port "$OPENCODE_PORT" || echo "Warning: could not set the OpenCode service port."
  opencode service set password "$WEB_PASSWORD" || echo "Warning: could not set the OpenCode web password."
  # `service start` can race a server still shutting down from the `set`
  # commands above, so retry until the web UI answers its health check.
  READY=""
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    opencode service start 2>/dev/null || true
    if curl -fsS --max-time 5 -u "opencode:${WEB_PASSWORD}" "http://127.0.0.1:${OPENCODE_PORT}/api/info" >/dev/null 2>&1; then
      READY="yes"
      break
    fi
    sleep 2
  done
  opencode service status || true
  if [ -n "$READY" ]; then
    echo "OpenCode web UI is ready on port ${OPENCODE_PORT}."
  else
    echo "Warning: the OpenCode web UI did not answer its health check."
  fi
else
  echo "Warning: OpenCode is not installed; the OpenCode apps will not work."
fi

# --- LiteLLM config for code-server (Continue extension) --------------------
# Written even if Continue is missing so it picks up on first launch. The
# file holds the API key, so it stays mode 0600 in the user's home.
CONTINUE_CONFIG="${HOME}/.continue/config.yaml"
if [ -n "${LITELLM_API_KEY:-}" ] && [ -n "${LITELLM_BASE_URL:-}" ]; then
  mkdir -p "${HOME}/.continue"
  FIRST_MODEL=$(curl -fsS -H "Authorization: Bearer ${LITELLM_API_KEY}" "${LITELLM_BASE_URL}/v1/models" 2>/dev/null \
    | jq -r '.data[0]?.id // empty' 2>/dev/null || true)
  cat >"$CONTINUE_CONFIG" <<EOF
name: LiteLLM Assistant
version: 1.0.0
schema: v1
models:
  - name: LiteLLM
    provider: openai
    model: ${FIRST_MODEL:-mimo-v2.6-pro}
    apiBase: ${LITELLM_BASE_URL}/v1
    apiKey: ${LITELLM_API_KEY}
    roles:
      - chat
      - edit
      - apply
context:
  - provider: code
  - provider: docs
  - provider: diff
  - provider: terminal
  - provider: problems
  - provider: folder
  - provider: codebase
EOF
  chmod 600 "$CONTINUE_CONFIG"
  echo "Configured the Continue extension (code-server) for LiteLLM."
fi

# --- csv2db helper ----------------------------------------------------------
# Baked into the image; when using a custom image without it, install the
# copy shipped with the template (passed base64-encoded in the agent env).
if ! command -v csv2db >/dev/null 2>&1 && [ -n "${CSV2DB_B64:-}" ]; then
  mkdir -p "${HOME}/.local/bin"
  echo "${CSV2DB_B64}" | base64 -d >"${HOME}/.local/bin/csv2db" \
    && chmod +x "${HOME}/.local/bin/csv2db" \
    && echo "Installed the csv2db helper into ~/.local/bin." \
    || echo "Warning: could not install the csv2db helper."
fi

echo "Startup complete."
