# Coder template development shortcuts.
# Defaults target the deployment configured in CODER_URL.

CODER_URL ?= https://coder.actuary.dev
CODER_ORG ?= coder
TEMPLATE  ?= docker
VERSION   ?= dev-$(shell git rev-parse --short HEAD)

export CODER_URL

.PHONY: check fmt push test-workspace delete-test-workspace

check: ## Validate every template (fmt, init, validate, tflint)
	./scripts/check.sh

fmt: ## Auto-format template HCL
	terraform fmt -recursive templates/

push: ## Push TEMPLATE as an inactive version named dev-<sha>
	coder templates push $(TEMPLATE) \
		--org $(CODER_ORG) \
		--directory templates/$(TEMPLATE) \
		--name $(VERSION) \
		--message "local dev push" \
		--activate=false \
		--yes

test-workspace: ## Create a throwaway workspace from the pushed version and smoke-test it
	coder create --template $(TEMPLATE) --template-version $(VERSION) --org $(CODER_ORG) --use-parameter-defaults test-$(TEMPLATE) --yes
	coder ssh test-$(TEMPLATE) -- sh -c 'echo "smoke test ok: $$(uname -a)"'

delete-test-workspace: ## Delete the throwaway workspace
	coder delete test-$(TEMPLATE) --yes
