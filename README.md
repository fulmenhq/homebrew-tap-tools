# Homebrew Tap Tools

[![checks](https://github.com/fulmenhq/homebrew-tap-tools/actions/workflows/ci.yml/badge.svg)](https://github.com/fulmenhq/homebrew-tap-tools/actions/workflows/ci.yml)

Developer tools for maintaining FulmenHQ Homebrew taps and formulas. This repository contains scripts and utilities used by maintainers to automate formula updates, releases, and validation.

**Scope:** Scripts in this repository are specific to the `fulmenhq` GitHub organization and assume FulmenHQ release conventions (artifact naming, platform support, etc.). Other organizations within 3 Leaps should create their own `homebrew-tap-tools` repositories tailored to their needs.

**Organization:** FulmenHQ
**License:** MIT

## Tools

### `update-formula.sh`

Automates formula updates by fetching release artifacts from GitHub and updating formula files with new versions and SHA256 checksums.

**Features:**
- Fetches SHA256SUMS from GitHub releases or local builds
- Extracts checksums for multiple platforms (darwin/linux × amd64/arm64)
- Updates formula files with new versions, URLs, and checksums
- Context-aware SHA256 replacement using AWK

**Usage:**

```bash
# Update from GitHub release
./update-formula.sh <app-name> <version> --github

# Update from local build
./update-formula.sh <app-name> <version> --local

# Examples
./update-formula.sh goneat 0.3.5 --github
./update-formula.sh myapp 1.0.0 --local
```

**Requirements:**
- `gh` (GitHub CLI) - for fetching releases from GitHub
- `awk` - for context-aware checksums replacement
- `sed` - for version/URL updates

**Integration with Makefile:**

```makefile
TOOLS_URL := https://raw.githubusercontent.com/fulmenhq/homebrew-tap-tools/main
UPDATE_SCRIPT := $(TOOLS_URL)/update-formula.sh

update-formula:
	@curl -sSL $(UPDATE_SCRIPT) | bash -s -- $(APP) $(VERSION) --github
```

## Directory Structure

```
.
├── README.md               # This file
├── update-formula.sh       # Formula update automation
├── Makefile                # check / format / test / precommit targets
├── .github/workflows/      # CI (shellcheck + shfmt + smoke test)
└── LICENSE                 # MIT License
```

## Contributing

This tooling repository supports FulmenHQ Homebrew taps:
- `fulmenhq/homebrew-tap`

**Guidelines:**
- Scripts are specific to FulmenHQ release conventions
- Document all scripts thoroughly
- Test changes against real formula files
- Follow shell scripting best practices
- Run `make check` (lint + format) and `make precommit` before committing changes

## Development

**Checks:**

```bash
make check      # shellcheck + shfmt -i 2
make test       # smoke test (--help / usage)
make precommit  # check + test
```

These run in CI (`.github/workflows/ci.yml`) on every push and pull request.

**Testing Locally:**

```bash
# Dry run (requires formula file to exist)
./update-formula.sh myapp 1.0.0 --local

# Run with actual GitHub release
./update-formula.sh goneat 0.3.5 --github
```

**Style:** Scripts use 2-space indentation (`shfmt -i 2`), enforced by `make check` and CI.

## Why This Repository?

Homebrew's CI runs style checkers (`shfmt`) on all shell scripts in tap repositories. Complex scripts with embedded AWK/sed logic can cause parsing issues. By separating maintainer tools from distribution formulas, we:

1. Keep taps clean and focused on formulas
2. Avoid CI conflicts with code formatters
3. Enable reuse across multiple FulmenHQ taps
4. Version tools independently of formulas

**Note:** This repository is specific to FulmenHQ. Other organizations within 3 Leaps (lanyte, specomate, etc.) should create their own `homebrew-tap-tools` repositories customized to their release conventions. Shared patterns and best practices will be documented in the 3 Leaps DevSecOps documentation repository.

## License

MIT License - See LICENSE file for details

Copyright (c) 2025 3 Leaps, LLC

---

**Questions?** See individual tool documentation or open an issue.
