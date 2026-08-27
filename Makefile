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
	@echo "Running offline formula rewrite smoke (strips version, rewrites URL/sha256)..."
	@bash -euo pipefail -c '\
	  tmp=$$(mktemp -d); \
	  trap "rm -rf \"$$tmp\"" EXIT; \
	  mkdir -p "$$tmp/tap/Formula" "$$tmp/demoapp/dist/release"; \
	  printf "%s\n" \
	    "class Demoapp < Formula" \
	    "  desc \"demo\"" \
	    "  homepage \"https://github.com/fulmenhq/demoapp\"" \
	    "  version \"0.1.0\"" \
	    "  license \"MIT\"" \
	    "  on_macos do" \
	    "    on_arm do" \
	    "      url \"https://github.com/fulmenhq/demoapp/releases/download/v0.1.0/demoapp_v0.1.0_darwin_arm64.tar.gz\"" \
	    "      sha256 \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"" \
	    "    end" \
	    "  end" \
	    "end" > "$$tmp/tap/Formula/demoapp.rb"; \
	  printf "%s\n" \
	    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  demoapp_v0.2.0_darwin_arm64.tar.gz" \
	    > "$$tmp/demoapp/dist/release/SHA256SUMS"; \
	  (cd "$$tmp/tap" && "$(CURDIR)/update-formula.sh" demoapp 0.2.0 --local); \
	  ! grep -q "version \"" "$$tmp/tap/Formula/demoapp.rb"; \
	  grep -q "releases/download/v0.2.0/demoapp_v0.2.0_darwin_arm64.tar.gz" "$$tmp/tap/Formula/demoapp.rb"; \
	  grep -q "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" "$$tmp/tap/Formula/demoapp.rb"; \
	  echo "✓ Offline rewrite smoke passed (no version stanza; URL + sha256 updated)"'
	@echo ""
	@echo "Optional live test (needs network + gh):"
	@echo "  Example: ./update-formula.sh goneat 0.5.15 --github"

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
