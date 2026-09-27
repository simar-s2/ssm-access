SCRIPTS := bin/ssm-ssh scripts/deploy.sh

.PHONY: help test lint fmt validate tflint cfn-lint checkov shellcheck demo

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

TEST_DIRS := . modules/vpc-endpoints modules/jump-host

test: ## pytest (ssm-ssh, deploy script) and terraform test (mocked provider)
	python3 -m pytest -q tests
	@for d in $(TEST_DIRS); do terraform -chdir=$$d init -backend=false -input=false >/dev/null || exit 1; done
	@for d in $(TEST_DIRS); do echo "terraform test: $$d"; terraform -chdir=$$d test || exit 1; done

lint: validate tflint cfn-lint checkov shellcheck ## Every linter CI runs

fmt: ## Format the Terraform files
	terraform fmt -recursive

validate: ## terraform fmt -check, then validate the module, submodules and examples
	terraform fmt -check -recursive
	@for d in . modules/*/ examples/*/; do \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
	  terraform -chdir=$$d validate -no-color >/dev/null && echo "valid: $$d" || exit 1; \
	done

tflint: ## tflint with the AWS ruleset
	@tflint --init >/dev/null
	tflint --recursive --config "$(CURDIR)/.tflint.hcl"

cfn-lint: ## Lint the CloudFormation template
	cfn-lint cloudformation/*.yaml

checkov: ## Static security scan of Terraform, CloudFormation and CI
	checkov --config-file .checkov.yaml -d . --skip-download

shellcheck: ## Lint the shell scripts
	shellcheck $(SCRIPTS)

demo: ## The recording in the README, in a scratch HOME against the fake AWS CLI
	@scripts/demo.sh
