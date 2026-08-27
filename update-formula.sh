#!/usr/bin/env bash

set -euo pipefail

# Script to update a Homebrew formula with new version and checksums
# Usage: ./scripts/update-formula.sh <app-name> <version> [--local]

# Handle both direct execution, Makefile invocation, and curl piping
if [ -f "Formula/goneat.rb" ] || [ -d "Formula" ]; then
  # Already in homebrew-tap directory (called from Makefile or cd'd here)
  TAP_ROOT="$(pwd)"
elif [ -n "${BASH_SOURCE[0]:-}" ]; then
  # Direct execution from homebrew-tap-tools directory
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TAP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  # Piped via curl - use current working directory (should be homebrew-tap)
  TAP_ROOT="$(pwd)"
fi

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
  local filename
  for filename in "$@"; do
    if [[ -z "${filename}" ]]; then
      continue
    fi
    local sha
    sha=$(grep "${filename}" "${TEMP_SUMS}" | awk '{print $1}' || true)
    if [[ -n "${sha}" ]]; then
      echo "${sha}"
      return 0
    fi
  done
  echo ""
}

DARWIN_AMD64_SHA=$(get_sha256 "${APP_NAME}_v${VERSION}_darwin_amd64.tar.gz" "${APP_NAME}-darwin-amd64")
DARWIN_ARM64_SHA=$(get_sha256 "${APP_NAME}_v${VERSION}_darwin_arm64.tar.gz" "${APP_NAME}-darwin-arm64")
LINUX_AMD64_SHA=$(get_sha256 "${APP_NAME}_v${VERSION}_linux_amd64.tar.gz" "${APP_NAME}-linux-amd64")
LINUX_ARM64_SHA=$(get_sha256 "${APP_NAME}_v${VERSION}_linux_arm64.tar.gz" "${APP_NAME}-linux-arm64")

# Validate checksums — but only require a platform whose binary the formula
# actually references. Products may ship a subset of platforms (e.g. sumpter
# retired darwin-amd64 in v0.1.10, so its formula is macOS arm-only). A platform
# absent from the formula is skipped, not treated as an error.
platform_referenced() {
  # $1 = platform token like "darwin_amd64"; match archive (_darwin_amd64) or
  # raw-binary (-darwin-amd64) naming in the formula.
  local us="$1"
  local hy="${us//_/-}"
  grep -Eq "${APP_NAME}_v[0-9][0-9.]*_${us}|${APP_NAME}-${hy}([^0-9a-zA-Z]|$)" "${FORMULA_FILE}"
}

missing=0
echo "Checksums:"
check_platform() {
  # $1 = platform token, $2 = its extracted sha (may be empty)
  if platform_referenced "$1"; then
    if [[ -z "$2" ]]; then
      echo "  $1: MISSING (referenced in ${APP_NAME}.rb but absent from SHA256SUMS)"
      missing=1
    else
      echo "  $1: $2"
    fi
  else
    echo "  $1: skipped (not referenced in ${APP_NAME}.rb)"
  fi
}
check_platform darwin_amd64 "${DARWIN_AMD64_SHA}"
check_platform darwin_arm64 "${DARWIN_ARM64_SHA}"
check_platform linux_amd64 "${LINUX_AMD64_SHA}"
check_platform linux_arm64 "${LINUX_ARM64_SHA}"

if [[ "${missing}" -ne 0 ]]; then
  echo "Error: a platform referenced in ${APP_NAME}.rb is missing from SHA256SUMS"
  exit 1
fi

# Update the formula file
echo "Updating formula file..."

# Create a temporary file for the updated formula
TEMP_FORMULA=$(mktemp)
trap 'rm -f "${TEMP_SUMS}" "${TEMP_FORMULA}"' EXIT

# Update URLs/artifact names from VERSION. Do not emit an explicit `version "..."`
# stanza — brew audit rejects it when the version is already scanned from the URL
# (`Stable: version X is redundant with version scanned from URL`).
# Also strip any legacy version line so re-runs stay audit-clean.
sed -e '/^  version "/d' \
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
