#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#
# build-kernel-deb.sh - Build Ubuntu kernel .deb packages from a Canonical
#                       source tree (as checked out from a series branch)
#
# Usage:
#   build-kernel-deb.sh [SOURCE_DIR] [ARCH] [FLAVOR] [JOBS]
#
# Arguments:
#   SOURCE_DIR   Root of the kernel source tree containing debian/ (default: .)
#   ARCH         Target Debian architecture: arm64 | amd64 (default: arm64)
#   FLAVOR       Kernel flavour: generic | lowlatency | all (default: generic)
#   JOBS         Parallel make jobs (default: nproc)
#
# Output:
#   Built .deb packages are placed in ./output/ relative to the working
#   directory from which this script is invoked.
#
# Notes:
#   • Designed for native arm64 builds (Ubuntu 24.04 arm64 host).
#   • The Ubuntu kernel build needs ~20 GB of free disk space.
#   • A full build (all flavours) can take 2+ hours; 'generic' is ~1 hour.
#   • Run as a normal user; sudo is used only for apt-get.

set -euo pipefail

SOURCE_DIR="${1:-.}"
ARCH="${2:-arm64}"
FLAVOR="${3:-generic}"
JOBS="${4:-$(nproc)}"

OUTPUT_DIR="$(pwd)/output"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
hr()   { log "$(printf '%0.s─' {1..60})"; }

hr
log "Ubuntu kernel .deb build"
log "  Source dir : ${SOURCE_DIR}"
log "  Arch       : ${ARCH}"
log "  Flavour    : ${FLAVOR}"
log "  Jobs       : ${JOBS}"
log "  Output dir : ${OUTPUT_DIR}"
hr

# ---------------------------------------------------------------------------
# 1. Validate source tree
# ---------------------------------------------------------------------------
[ -f "${SOURCE_DIR}/debian/rules" ] \
  || die "No debian/rules found in '${SOURCE_DIR}' – is this a kernel source tree?"

# ---------------------------------------------------------------------------
# 2. Install build dependencies
# ---------------------------------------------------------------------------
hr
log "Installing build dependencies (requires sudo)..."
sudo apt-get update -qq
sudo apt-get build-dep -y "${SOURCE_DIR}" \
  || die "apt-get build-dep failed"

# ---------------------------------------------------------------------------
# 3. Build
# ---------------------------------------------------------------------------
hr
log "Starting kernel build (flavour=${FLAVOR}, arch=${ARCH}, jobs=${JOBS})..."

# Determine the debian/rules target
if [ "${FLAVOR}" = "all" ]; then
  RULES_TARGET="binary"
else
  RULES_TARGET="binary-${FLAVOR}"
fi

# The Ubuntu kernel build system reads DEB_BUILD_OPTIONS for parallelism
export DEB_BUILD_OPTIONS="parallel=${JOBS} nocheck"

# Run the build (native arm64 – no cross-compilation flags needed)
(
  cd "${SOURCE_DIR}"
  fakeroot debian/rules "${RULES_TARGET}" \
    || die "debian/rules ${RULES_TARGET} failed"
)

# ---------------------------------------------------------------------------
# 4. Collect output packages
# ---------------------------------------------------------------------------
hr
mkdir -p "${OUTPUT_DIR}"

# The Ubuntu kernel build drops .deb files one level above the source tree
PARENT_DIR=$(dirname "$(realpath "${SOURCE_DIR}")")
find "${PARENT_DIR}" -maxdepth 1 \
  \( -name "*.deb" -o -name "*.changes" -o -name "*.buildinfo" \) \
  | while read -r f; do
      cp "${f}" "${OUTPUT_DIR}/"
      log "  Collected: $(basename "${f}")"
    done

hr
log "Build complete."
log ""
log "Output packages:"
ls -lh "${OUTPUT_DIR}"/*.deb 2>/dev/null \
  || log "  (no .deb files found — check build log above)"
