.PHONY: help check lint format test precommit install-hooks

help:
	@echo "Homebrew Tap Tools - Development Commands"
	@echo ""
	@echo "Usage:"
	@echo "  make check         Run all checks (lint + format)"
	@echo "  make lint          Run shellcheck on scripts"
	@echo "  make format        Check shell script formatting with shfmt"
	@echo "  make test          Test script functionality"
	@echo "  make precommit     Run all pre-commit checks"
	@echo "  make install-hooks Install git pre-commit hook"
	@echo ""
	@echo "Examples:"
	@echo "  make check"
	@echo "  make test"
	@echo "  make install-hooks"

# Run all checks
check: lint format
	@echo "✓ All checks passed"

# Lint shell scripts with shellcheck
lint:
	@echo "Running shellcheck..."
	@shellcheck -x update-formula.sh
	@echo "✓ shellcheck passed"

# Check shell script formatting (2 spaces)
format:
	@echo "Checking shell script formatting..."
	@if ! shfmt -i 2 -d update-formula.sh > /dev/null 2>&1; then \
		echo "✗ Formatting issues found. Run: shfmt -i 2 -w update-formula.sh"; \
		exit 1; \
	fi
	@echo "✓ Formatting check passed"

# Test script functionality
test:
	@echo "Testing update-formula.sh..."
	@./update-formula.sh --help > /dev/null
	@echo "✓ Script --help works"
	@./update-formula.sh 2>&1 | grep -q "Usage:" && echo "✓ Script usage message works"
	@echo ""
	@echo "Note: Full functional test requires a formula file and GitHub release"
	@echo "  Example: ./update-formula.sh goneat 0.3.5 --github"

# Run all pre-commit checks
precommit: check test
	@echo ""
	@echo "✓ All pre-commit checks passed!"

# Install git pre-commit hook
install-hooks:
	@echo "Installing git pre-commit hook..."
	@mkdir -p .git/hooks
	@echo '#!/bin/sh' > .git/hooks/pre-commit
	@echo 'make precommit' >> .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "✓ Pre-commit hook installed"
	@echo ""
	@echo "The hook will run 'make precommit' before each commit."
	@echo "To bypass the hook temporarily, use: git commit --no-verify"
