#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#
# fetch-source-pkg.sh - Clone the Canonical Ubuntu kernel source from the
#                       Launchpad git repository at the version tag matching
#                       the latest published source package.
#
# Usage:
#   fetch-source-pkg.sh [SUITE] [SOURCE_NAME] [OUTPUT_DIR]
#
# Arguments:
#   SUITE        Ubuntu suite (default: noble)
#   SOURCE_NAME  Source package name (default: linux)
#   OUTPUT_DIR   Directory to clone into (default: .)
#
# Why git instead of the source package (.dsc/.orig.tar.gz/.diff.gz)?
#   The Ubuntu kernel source package (format 1.0) ships only debian.master/
#   with rules.d/ fragments — debian/rules is NOT included. The complete
#   debian/ directory (with rules, scripts/, templates/, etc.) lives only in
#   the Launchpad git repository. Cloning from git gives a buildable tree.
#
# Output:
#   A shallow clone of the kernel source at tag Ubuntu-<version> is placed
#   in OUTPUT_DIR/. A version.env metadata file is also written.

set -euo pipefail

SUITE="${1:-noble}"
SOURCE_NAME="${2:-linux}"
OUTPUT_DIR="${3:-.}"

LAUNCHPAD_API="${LAUNCHPAD_API:-https://api.launchpad.net/1.0}"
LAUNCHPAD_GIT="https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
hr()   { log "$(printf '%0.s─' {1..60})"; }

# ---------------------------------------------------------------------------
# 1. Query Launchpad for the latest published version
# ---------------------------------------------------------------------------
hr
log "Querying Launchpad for latest '${SOURCE_NAME}' in Ubuntu ${SUITE}..."

API_URL="${LAUNCHPAD_API}/ubuntu/+archive/primary"
API_URL+="?ws.op=getPublishedSources"
API_URL+="&source_name=${SOURCE_NAME}"
API_URL+="&distro_series=/ubuntu/${SUITE}"
API_URL+="&status=Published"
API_URL+="&order_by_date=true"

RESPONSE=$(curl -fsSL "${API_URL}") \
  || die "Launchpad API request failed"

# Filter by exact source_package_name (source_name= is a prefix match)
VERSION=$(echo "$RESPONSE" | jq -r \
  --arg name "${SOURCE_NAME}" \
  '[.entries[] | select(.source_package_name == $name)] | .[0].source_package_version // empty')

[ -n "$VERSION" ] || die "No published source found for '${SOURCE_NAME}' (exact) in '${SUITE}'"

UPSTREAM_VERSION=$(echo "${VERSION}" | cut -d'-' -f1)
GIT_TAG="Ubuntu-${VERSION}"

log "Found:    ${SOURCE_NAME} ${VERSION}  (upstream: ${UPSTREAM_VERSION})"
log "Git tag:  ${GIT_TAG}"

# ---------------------------------------------------------------------------
# 2. Clone from Launchpad git at the version tag (shallow)
# ---------------------------------------------------------------------------
hr
CLONE_URL="${LAUNCHPAD_GIT}/${SUITE}"
log "Cloning ${CLONE_URL} at tag ${GIT_TAG} (shallow)..."

mkdir -p "${OUTPUT_DIR}"

git clone --depth=1 --branch "${GIT_TAG}" "${CLONE_URL}" "${OUTPUT_DIR}" \
  || die "git clone failed"

FILE_COUNT=$(find "${OUTPUT_DIR}" -type f | wc -l)
log "Cloned ${FILE_COUNT} files"

[ "${FILE_COUNT}" -gt 5000 ] || \
  die "Too few files cloned (${FILE_COUNT}) — expected >5000"

# ---------------------------------------------------------------------------
# 3. Write version metadata
# ---------------------------------------------------------------------------
hr
cat > "${OUTPUT_DIR}/version.env" <<EOF
SOURCE_NAME=${SOURCE_NAME}
SUITE=${SUITE}
VERSION=${VERSION}
UPSTREAM_VERSION=${UPSTREAM_VERSION}
GIT_TAG=${GIT_TAG}
GIT_URL=${CLONE_URL}
FETCH_DATE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

log "Metadata written to ${OUTPUT_DIR}/version.env"
hr
log "Clone complete.  Output directory: ${OUTPUT_DIR}"
log ""
log "debian/ contents:"
ls "${OUTPUT_DIR}/debian/" | head -10
