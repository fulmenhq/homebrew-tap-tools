#!/usr/bin/env bash

set -euo pipefail

# Script to update a Homebrew formula with new version and checksums
# Usage: ./scripts/update-formula.sh <app-name> <version> [--local]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Update a Homebrew formula with new version and checksums

Usage: $0 <app-name> <version> [options]

Arguments:
    app-name    Name of the application (e.g., goneat)
    version     Version number (e.g., 0.3.3 or v0.3.3)

Options:
    --local     Use local checksums from ../\${app-name}/dist/release/SHA256SUMS
    --github    Fetch checksums from GitHub release (default)
    -h, --help  Show this help message

Examples:
    # Fetch from GitHub release
    $0 goneat 0.3.3

    # Use local checksums
    $0 goneat 0.3.3 --local

    # Version with 'v' prefix works too
    $0 goneat v0.3.3
EOF
}

# Check for help flag first
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

APP_NAME="$1"
VERSION="$2"
SOURCE="github" # default

# Strip 'v' prefix if present
VERSION="${VERSION#v}"
VERSION_TAG="v${VERSION}"

shift 2

# Parse options
while [[ $# -gt 0 ]]; do
  case $1 in
  --local)
    SOURCE="local"
    shift
    ;;
  --github)
    SOURCE="github"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
done

FORMULA_FILE="${TAP_ROOT}/Formula/${APP_NAME}.rb"

if [[ ! -f "${FORMULA_FILE}" ]]; then
  echo "Error: Formula file not found: ${FORMULA_FILE}"
  exit 1
fi

echo "Updating ${APP_NAME} formula to version ${VERSION}..."

# Fetch checksums
TEMP_SUMS=$(mktemp)
trap 'rm -f "${TEMP_SUMS}"' EXIT

if [[ "${SOURCE}" == "local" ]]; then
  LOCAL_SUMS="${TAP_ROOT}/../${APP_NAME}/dist/release/SHA256SUMS"
  echo "Using local checksums from ${LOCAL_SUMS}"

  if [[ ! -f "${LOCAL_SUMS}" ]]; then
    echo "Error: Local SHA256SUMS file not found: ${LOCAL_SUMS}"
    exit 1
  fi

  cp "${LOCAL_SUMS}" "${TEMP_SUMS}"
else
  echo "Fetching checksums from GitHub release ${VERSION_TAG}..."

  if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) is required but not installed"
    echo "Install with: brew install gh"
    exit 1
  fi

  if ! gh release view "${VERSION_TAG}" --repo "fulmenhq/${APP_NAME}" &>/dev/null; then
    echo "Error: Release ${VERSION_TAG} not found for fulmenhq/${APP_NAME}"
    exit 1
  fi

  gh release download "${VERSION_TAG}" \
    --repo "fulmenhq/${APP_NAME}" \
    --pattern "SHA256SUMS" \
    --output "${TEMP_SUMS}" \
    --clobber
fi

# Extract checksums for each platform
echo "Extracting checksums..."

get_sha256() {
  local filename="$1"
  grep "${filename}" "${TEMP_SUMS}" | awk '{print $1}' || echo ""
}

DARWIN_AMD64_SHA=$(get_sha256 "${APP_NAME}_v${VERSION}_darwin_amd64.tar.gz")
DARWIN_ARM64_SHA=$(get_sha256 "${APP_NAME}_v${VERSION}_darwin_arm64.tar.gz")
LINUX_AMD64_SHA=$(get_sha256 "${APP_NAME}_v${VERSION}_linux_amd64.tar.gz")
LINUX_ARM64_SHA=$(get_sha256 "${APP_NAME}_v${VERSION}_linux_arm64.tar.gz")

# Validate that we got all checksums
if [[ -z "${DARWIN_AMD64_SHA}" ]] || [[ -z "${DARWIN_ARM64_SHA}" ]] ||
  [[ -z "${LINUX_AMD64_SHA}" ]] || [[ -z "${LINUX_ARM64_SHA}" ]]; then
  echo "Error: Could not extract all required checksums from SHA256SUMS"
  echo "Found:"
  echo "  darwin_amd64: ${DARWIN_AMD64_SHA:-MISSING}"
  echo "  darwin_arm64: ${DARWIN_ARM64_SHA:-MISSING}"
  echo "  linux_amd64:  ${LINUX_AMD64_SHA:-MISSING}"
  echo "  linux_arm64:  ${LINUX_ARM64_SHA:-MISSING}"
  exit 1
fi

echo "Checksums extracted:"
echo "  darwin_amd64: ${DARWIN_AMD64_SHA}"
echo "  darwin_arm64: ${DARWIN_ARM64_SHA}"
echo "  linux_amd64:  ${LINUX_AMD64_SHA}"
echo "  linux_arm64:  ${LINUX_ARM64_SHA}"

# Update the formula file
echo "Updating formula file..."

# Create a temporary file for the updated formula
TEMP_FORMULA=$(mktemp)
trap 'rm -f "${TEMP_SUMS}" "${TEMP_FORMULA}"' EXIT

# Use sed to update version and checksums
sed -e "s/version \"[^\"]*\"/version \"${VERSION}\"/" \
  -e "s|releases/download/v[^/]*/|releases/download/${VERSION_TAG}/|g" \
  -e "s/${APP_NAME}_v[0-9.]*_darwin_amd64/${APP_NAME}_v${VERSION}_darwin_amd64/g" \
  -e "s/${APP_NAME}_v[0-9.]*_darwin_arm64/${APP_NAME}_v${VERSION}_darwin_arm64/g" \
  -e "s/${APP_NAME}_v[0-9.]*_linux_amd64/${APP_NAME}_v${VERSION}_linux_amd64/g" \
  -e "s/${APP_NAME}_v[0-9.]*_linux_arm64/${APP_NAME}_v${VERSION}_linux_arm64/g" \
  "${FORMULA_FILE}" >"${TEMP_FORMULA}"

# Now update the SHA256 values
# This is a bit tricky - we need to update each sha256 in the correct context
# shellcheck disable=SC1004,SC1009,SC1072,SC1073
awk -v da="${DARWIN_AMD64_SHA}" \
  -v dr="${DARWIN_ARM64_SHA}" \
  -v la="${LINUX_AMD64_SHA}" \
  -v lr="${LINUX_ARM64_SHA}" '
  BEGIN {
    context = ""
  }
  /on_macos do/ {
    context = "macos"
  }
  /on_linux do/ {
    context = "linux"
  }
  /on_intel do/ {
    if (context == "macos") subcontext = "darwin_amd64"
    if (context == "linux") subcontext = "linux_amd64"
  }
  /on_arm do/ {
    if (context == "macos") subcontext = "darwin_arm64"
    if (context == "linux") subcontext = "linux_arm64"
  }
  /sha256/ {
    if (subcontext == "darwin_amd64") {
      print "      sha256 \"" da "\""
      next
    }
    if (subcontext == "darwin_arm64") {
      print "      sha256 \"" dr "\""
      next
    }
    if (subcontext == "linux_amd64") {
      print "      sha256 \"" la "\""
      next
    }
    if (subcontext == "linux_arm64") {
      print "      sha256 \"" lr "\""
      next
    }
  }
  { print }
' "${TEMP_FORMULA}" >"${FORMULA_FILE}"

echo "Formula updated successfully!"
echo ""
echo "Next steps:"
echo "  1. Review the changes: git diff Formula/${APP_NAME}.rb"
echo "  2. Test the formula:   brew audit --strict Formula/${APP_NAME}.rb"
echo "  3. Test installation:  brew install --build-from-source Formula/${APP_NAME}.rb"
echo "  4. Commit changes:     git add Formula/${APP_NAME}.rb && git commit -m \"Update ${APP_NAME} to v${VERSION}\""
