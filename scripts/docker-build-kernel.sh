#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
#
# docker-build-kernel.sh - Build Ubuntu kernel .deb packages inside a Docker container
#
# This script wraps build-kernel-deb.sh and runs it inside the pkg-builder container.
# It automatically detects the current architecture and pulls the appropriate Docker image
# if it's not already available locally.
#
# See build-kernel-deb.sh for full argument/env docs.
#
# Usage:
#   docker-build-kernel.sh [SOURCE_DIR] [ARCH] [FLAVOR] [JOBS] [VERSION_SUFFIX]
#
# Arguments:
#   SOURCE_DIR      Root of the kernel source tree (default: resolute-qcom-devel)
#   ARCH            Target Debian architecture: arm64 (default: arm64)
#   FLAVOR          Kernel flavour: qcom | qcom-rt | all (default: qcom)
#   JOBS            Parallel make jobs (default: nproc)
#   VERSION_SUFFIX  Optional version suffix (default: none)
#
# Environment:
#   IMAGE           Docker image to use (auto-detected by default)
#   SKIP_BUILD_DEP  Skip build-dep installation (default: 1, since Docker image has deps preinstalled)
#   DEBEMAIL        Email for changelog entries (default: build-kernel-deb@localhost)
#   DEBFULLNAME     Full name for changelog entries (default: build-kernel-deb.sh)
#   DOCKER_REGISTRY Docker registry URL (default: docker-registry.qualcomm.com)
#
# Output:
#   Built .deb packages are placed in ./output/ relative to the workspace root.

set -euo pipefail

# Logging helpers
log()  { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
hr()   { log "$(printf '%0.s─' {1..60})"; }

# Normalizes common truthy spellings (1, true, yes, on — case-insensitive) to
# return 0 (success); everything else (including unset/empty) returns 1 (failure).
is_truthy() {
  case "${1:-}" in
    1|[tT][rR][uU][eE]|[yY][eE][sS]|[oO][nN]) return 0 ;;
    *) return 1 ;;
  esac
}

# Get the workspace root (two levels up from scripts/)
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Parse arguments
SOURCE_DIR="${1:-resolute-qcom-devel}"
ARCH="${2:-arm64}"
FLAVOR="${3:-qcom}"
JOBS="${4:-$(nproc)}"
VERSION_SUFFIX="${5:-}"

# Environment variables
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker-registry.qualcomm.com}"
SKIP_BUILD_DEP="${SKIP_BUILD_DEP:-1}"

# Detect current system architecture
CURRENT_ARCH="$(uname -m)"
case "$CURRENT_ARCH" in
  aarch64) CURRENT_ARCH="arm64" ;;
  x86_64)  CURRENT_ARCH="amd64" ;;
esac

# Determine the Docker image based on current architecture
if [ -z "${IMAGE:-}" ]; then
  case "$CURRENT_ARCH" in
    arm64)
      IMAGE="${DOCKER_REGISTRY}/guanquan/kernel-build-docker:resolute-arm64-deps"
      ;;
    amd64)
      IMAGE="${DOCKER_REGISTRY}/guanquan/kernel-build-docker:resolute-amd64-crossdeps"
      ;;
    *)
      die "Unsupported architecture: $CURRENT_ARCH (expected arm64 or amd64)"
      ;;
  esac
fi

hr
log "Docker kernel build"
log "  Source dir      : ${SOURCE_DIR}"
log "  Target arch     : ${ARCH}"
log "  Current arch    : ${CURRENT_ARCH}"
log "  Flavour         : ${FLAVOR}"
log "  Jobs            : ${JOBS}"
log "  Docker image    : ${IMAGE}"
log "  Skip build-dep  : ${SKIP_BUILD_DEP}"
hr

# Check if Docker image exists locally
log "Checking if Docker image exists locally..."
if docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  log "✓ Docker image found locally: ${IMAGE}"
else
  log "✗ Docker image not found locally: ${IMAGE}"
  log "Pulling Docker image from registry..."
  if docker pull "${IMAGE}"; then
    log "✓ Successfully pulled Docker image: ${IMAGE}"
  else
    die "Failed to pull Docker image: ${IMAGE}"
  fi
fi

hr

# Detect TTY for interactive mode
docker_flags=(--rm)
[ -t 0 ] && [ -t 1 ] && docker_flags+=(-it)

# Run build inside Docker container
exec docker run "${docker_flags[@]}" \
  -v "${WORKSPACE_DIR}:/workspace" \
  -w /workspace \
  -e SKIP_BUILD_DEP="${SKIP_BUILD_DEP}" \
  -e DEBEMAIL="${DEBEMAIL:-}" \
  -e DEBFULLNAME="${DEBFULLNAME:-}" \
  "${IMAGE}" \
  bash -c 'sed -i "s/^Types: deb$/Types: deb deb-src/" /etc/apt/sources.list.d/ubuntu.sources \
&& (command -v dch >/dev/null || (apt-get update -qq && apt-get install -y devscripts)) \
&& bash /workspace/pkg-linux-qcom-canonical/scripts/build-kernel-deb.sh "$1" "$2" "$3" "$4" "$5"' \
  bash "${SOURCE_DIR}" "${ARCH}" "${FLAVOR}" "${JOBS}" "${VERSION_SUFFIX}"
