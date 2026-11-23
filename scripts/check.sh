#!/usr/bin/env bash
# Validate every template: terraform fmt, init, validate, tflint.
# Local equivalent of .github/workflows/lint.yml - keep them in sync.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

if ! command -v terraform >/dev/null 2>&1; then
  echo "error: terraform not found (https://developer.hashicorp.com/terraform/install)" >&2
  exit 1
fi

if ! command -v tflint >/dev/null 2>&1; then
  echo "note: tflint not found, skipping lint (https://github.com/terraform-linters/tflint)"
fi

for dir in "$root"/templates/*/; do
  [ -e "$dir/main.tf" ] || continue
  name="$(basename "$dir")"

  echo "==> $name: terraform fmt"
  (cd "$dir" && terraform fmt -check -diff) || status=1

  echo "==> $name: terraform init"
  (cd "$dir" && terraform init -backend=false -input=false >/dev/null) || status=1

  echo "==> $name: terraform validate"
  (cd "$dir" && terraform validate) || status=1

  if command -v tflint >/dev/null 2>&1; then
    echo "==> $name: tflint"
    (cd "$dir" && tflint) || status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "All checks passed."
else
  echo "Checks FAILED." >&2
fi
exit "$status"
