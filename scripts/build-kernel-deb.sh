#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
#
# build-kernel-deb.sh - Build Ubuntu kernel .deb packages from a Canonical
#                       source tree (as checked out from a series branch)
#
# Usage:
#   build-kernel-deb.sh [SOURCE_DIR] [ARCH] [FLAVOR] [JOBS] [VERSION_SUFFIX]
#
# Arguments:
#   SOURCE_DIR      Root of the kernel source tree containing debian/ (default: resolute-qcom-devel)
#   ARCH            Target Debian architecture: arm64 (default: arm64)
#   FLAVOR          Kernel flavour: qcom | qcom-rt | all (default: qcom)
#   JOBS            Parallel make jobs (default: nproc)
#   VERSION_SUFFIX  Optional string appended to the package/kernel version,
#                    e.g. "+g1a2b3c4" or "+myuser1" (default: none). Pass
#                    "auto" to generate "+g<short commit>" from SOURCE_DIR's
#                    current HEAD (requires SOURCE_DIR to be a git work tree).
#                    Modifies debian.qcom/changelog, but the script restores it
#                    to HEAD before every run, so this never leaves the tree
#                    dirty.
#
# Output:
#   Built .deb packages are placed in ./output/ relative to the working
#   directory from which this script is invoked.
#
# Notes:
#   • Supports both native builds (arm64 host building arm64) and
#     cross-compilation (e.g. amd64 host building arm64 via dpkg
#     cross-architecture + gcc-aarch64-linux-gnu).
#   • The Ubuntu kernel build needs ~20 GB of free disk space.
#   • A full build (all flavours) can take 2+ hours; 'qcom' is ~1 hour.
#   • Run as a normal user; sudo is used only for apt-get.
#
# Environment:
#   SKIP_BUILD_DEP  Skip the apt-get update + build-dep steps (default: 0).
#                   Pass SKIP_BUILD_DEP=1 to skip build dependencies installation.

set -euo pipefail

SOURCE_DIR="${1:-resolute-qcom-devel}"
ARCH="${2:-arm64}"
FLAVOR="${3:-qcom}"
JOBS="${4:-$(nproc)}"
VERSION_SUFFIX="${5:-}"

SKIP_BUILD_DEP="${SKIP_BUILD_DEP:-0}"

OUTPUT_DIR="$(pwd)/output"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
hr()   { log "$(printf '%0.s─' {1..60})"; }

is_truthy() {
  case "${1:-}" in
    1|[tT][rR][uU][eE]|[yY][eE][sS]|[oO][nN]) return 0 ;;
    *) return 1 ;;
  esac
}

is_git_worktree() {
  local dir="$1" out real
  out="$(git -C "${dir}" rev-parse --is-inside-work-tree 2>&1)" && return 0
  if printf '%s' "${out}" | grep -q 'detected dubious ownership'; then
    real="$(realpath "${dir}" 2>/dev/null)" || return 1
    git config --global --get-all safe.directory 2>/dev/null | grep -qxF "${real}" \
      || git config --global --add safe.directory "${real}" 2>/dev/null || true
    git -C "${dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1 && return 0
  fi
  return 1
}

if [ "${VERSION_SUFFIX}" = "auto" ]; then
  is_git_worktree "${SOURCE_DIR}" \
    || die "VERSION_SUFFIX=auto requires '${SOURCE_DIR}' to be a git work tree"
  AUTO_COMMIT="$(git -C "${SOURCE_DIR}" rev-parse --short HEAD)"
  VERSION_SUFFIX="+g${AUTO_COMMIT}"
fi

BUILD_ARCH="$(dpkg --print-architecture)"
CROSS_BUILD=false
if [ "${ARCH}" != "${BUILD_ARCH}" ]; then
  CROSS_BUILD=true
fi

hr
log "Ubuntu kernel .deb build"
log "  Source dir : ${SOURCE_DIR}"
log "  Build arch : ${BUILD_ARCH}"
log "  Host arch  : ${ARCH}$([ "${CROSS_BUILD}" = true ] && echo ' (cross-compiling)')"
log "  Flavour    : ${FLAVOR}"
log "  Jobs       : ${JOBS}"
log "  Output dir : ${OUTPUT_DIR}"
log "  Version    : ${VERSION_SUFFIX:-(none)}"
log "  Build-dep  : $(is_truthy "${SKIP_BUILD_DEP}" && echo 'skip (preinstalled)' || echo 'install')"
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
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

if [ "${CROSS_BUILD}" = true ]; then
  log "Enabling dpkg foreign architecture ${ARCH} for cross-compilation..."
  ${SUDO} dpkg --add-architecture "${ARCH}"
fi

# For cross-compilation, set DEB_HOST_ARCH and related variables.
CROSS_ENV=""
if [ "${CROSS_BUILD}" = true ]; then
  DEB_HOST_GNU_TYPE="$(dpkg-architecture -a"${ARCH}" -qDEB_HOST_GNU_TYPE)"
  DEB_HOST_MULTIARCH="$(dpkg-architecture -a"${ARCH}" -qDEB_HOST_MULTIARCH)"
  CROSS_ENV="DEB_HOST_ARCH=${ARCH} DEB_HOST_GNU_TYPE=${DEB_HOST_GNU_TYPE} DEB_HOST_MULTIARCH=${DEB_HOST_MULTIARCH}"
fi

# `clean` regenerates debian/control and copies debian.<flavour>/changelog to debian/changelog.
DEBIAN_DIR="$(awk -F= '($1 == "DEBIAN") { print $2 }' "${SOURCE_DIR}/debian/debian.env")"

if is_git_worktree "${SOURCE_DIR}"; then
  git -C "${SOURCE_DIR}" checkout -- "${DEBIAN_DIR}/changelog" 2>/dev/null || true
fi

if [ -n "${VERSION_SUFFIX}" ]; then
  export DEBEMAIL="${DEBEMAIL:-build-kernel-deb@localhost}"
  export DEBFULLNAME="${DEBFULLNAME:-build-kernel-deb.sh}"

  BASE_VERSION="$(dpkg-parsechangelog -l"${SOURCE_DIR}/${DEBIAN_DIR}/changelog" -S Version)" \
    || die "Failed to read current version from ${SOURCE_DIR}/${DEBIAN_DIR}/changelog"
  rm -f "${SOURCE_DIR}/${DEBIAN_DIR}/changelog.dch"
  log "Tagging local version suffix '${VERSION_SUFFIX}' onto ${DEBIAN_DIR}/changelog..."
  ( cd "${SOURCE_DIR}" && dch --changelog "${DEBIAN_DIR}/changelog" \
      --newversion "${BASE_VERSION}${VERSION_SUFFIX}" "Local build" ) \
    || die "Failed to apply version suffix via dch"

  if is_git_worktree "${SOURCE_DIR}"; then
    trap 'git -C "${SOURCE_DIR}" checkout -- "${DEBIAN_DIR}/changelog" 2>/dev/null || true' EXIT
  fi
fi

log "Running debian/rules clean (generates debian/control and debian/changelog)..."
( cd "${SOURCE_DIR}" && env ${CROSS_ENV} fakeroot debian/rules clean ) \
  || die "Failed to run debian/rules clean"

log "Installing build dependencies${SUDO:+ (requires sudo)}..."
if is_truthy "${SKIP_BUILD_DEP}"; then
  missing=""
  command -v bc  >/dev/null 2>&1 || missing="${missing} bc"
  command -v bison >/dev/null 2>&1 || missing="${missing} bison"
  command -v flex  >/dev/null 2>&1 || missing="${missing} flex"
  if [ "${CROSS_BUILD}" = true ]; then
    command -v "${DEB_HOST_GNU_TYPE}-gcc" >/dev/null 2>&1 \
      || missing="${missing} ${DEB_HOST_GNU_TYPE}-gcc"
  fi
  if [ -n "${missing}" ]; then
    die "SKIP_BUILD_DEP is set but required build tools are missing:${missing}. Re-run with SKIP_BUILD_DEP=0 to install build dependencies."
  fi
  log "  SKIP_BUILD_DEP set — build dependencies present; skipping apt-get build-dep."
else
  if [ "${CROSS_BUILD}" = true ]; then
    # For cross-compilation, llvm-21-dev needs :native qualifier.
    log "Patching debian/control: mark llvm-21-dev as a native (build-arch) dependency..."
    sed -i 's/^ llvm-21-dev,$/ llvm-21-dev:native,/' "${SOURCE_DIR}/debian/control"
  fi

  ${SUDO} apt-get update -qq
  BUILD_DEP_PROFILE_OPT=""
  if [ "${CROSS_BUILD}" = true ]; then
    # For cross-compilation, use the "cross" build profile.
    BUILD_DEP_PROFILE_OPT="--build-profiles cross"
  fi
  ( cd "${SOURCE_DIR}" && ${SUDO} apt-get build-dep -y --host-architecture "${ARCH}" ${BUILD_DEP_PROFILE_OPT} . ) \
    || die "apt-get build-dep failed"

  if [ "${CROSS_BUILD}" = true ]; then
    # For cross-compilation, also install native copies of build dependencies.
    log "Installing native (build-arch) copies of build dependencies for host-tool helpers..."
    ( cd "${SOURCE_DIR}" && ${SUDO} apt-get build-dep -y . ) \
      || die "apt-get build-dep (native pass) failed"
  fi
fi

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

export DEB_BUILD_OPTIONS="parallel=${JOBS} nocheck"

# For cross-compilation, CROSS_ENV sets CROSS_COMPILE and pulls in arch-specific rules.
# do_skip_checks=true bypasses the config-policy check to avoid failures when
# optional toolchains (Rust/bindgen) are not available.
(
  cd "${SOURCE_DIR}"
  env ${CROSS_ENV} fakeroot debian/rules "${RULES_TARGET}" do_skip_checks=true \
    || die "debian/rules ${RULES_TARGET} failed"
)

# ---------------------------------------------------------------------------
# 4. Collect output packages
# ---------------------------------------------------------------------------
hr
# Clear only the artifact types we produce, not the whole dir.
mkdir -p "${OUTPUT_DIR}"
rm -f "${OUTPUT_DIR}"/*.deb "${OUTPUT_DIR}"/*.changes "${OUTPUT_DIR}"/*.buildinfo

# Collect .deb files from the parent directory matching this build's version.
PARENT_DIR=$(dirname "$(realpath "${SOURCE_DIR}")")
DEB_VERSION="$(dpkg-parsechangelog -l "${SOURCE_DIR}/debian/changelog" -S Version)" \
  || die "Failed to read package version from debian/changelog"
# .deb filenames drop the epoch ("1:7.0.0" -> "7.0.0..."); no-op otherwise.
DEB_VERSION="${DEB_VERSION##*:}"
[ -n "${DEB_VERSION}" ] \
  || die "Empty package version parsed from ${SOURCE_DIR}/debian/changelog"

# Read into the parent shell so the counter survives to the empty-collection check.
collected=0
while IFS= read -r -d '' f; do
  mv "${f}" "${OUTPUT_DIR}/" || die "Failed to move $(basename "${f}") to ${OUTPUT_DIR}"
  log "  Collected: $(basename "${f}")"
  collected=$((collected + 1))
done < <(find "${PARENT_DIR}" -maxdepth 1 -name "*_${DEB_VERSION}_*" \
           \( -name "*.deb" -o -name "*.changes" -o -name "*.buildinfo" \) -print0)

[ "${collected}" -gt 0 ] \
  || die "Build finished but no artifacts matching version '${DEB_VERSION}' were found in ${PARENT_DIR}"

hr
log "Build complete."
log ""
log "Output packages:"
ls -lh "${OUTPUT_DIR}"/*.deb 2>/dev/null \
  || log "  (no .deb files found — check build log above)"
