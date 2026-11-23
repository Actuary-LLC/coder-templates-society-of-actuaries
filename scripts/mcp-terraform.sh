#!/usr/bin/env bash
# Start the Terraform MCP server over stdio for OpenCode.
#
# Prefers the pre-compiled binary (works everywhere, no Docker needed),
# and falls back to the official Docker image when a Docker daemon is
# actually available (having the docker CLI is not enough).
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

if command -v terraform-mcp-server >/dev/null 2>&1; then
  exec terraform-mcp-server stdio
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  exec docker run -i --rm hashicorp/terraform-mcp-server
fi

echo "terraform-mcp-server: no binary on PATH and no Docker daemon available." >&2
echo "Install the binary from https://releases.hashicorp.com/terraform-mcp-server/" >&2
echo "(see context/terraform-provider.md)." >&2
exit 1
