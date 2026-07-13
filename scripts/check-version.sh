#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#
# check-version.sh - Query the latest published kernel version from Launchpad
#
# Usage:
#   check-version.sh [SUITE] [SOURCE_NAME]
#
# Arguments:
#   SUITE        Ubuntu suite (default: noble)
#   SOURCE_NAME  Source package name (default: linux)
#
# Output:
#   Prints the latest version string to stdout (e.g. "6.8.0-51.52")
#
# Exit codes:
#   0  Version found
#   1  Version not found or API error

set -euo pipefail

SUITE="${1:-noble}"
SOURCE_NAME="${2:-linux}"

LAUNCHPAD_API="https://api.launchpad.net/1.0"

die() { echo "ERROR: $*" >&2; exit 1; }

RESPONSE=$(curl -fsSL \
  "${LAUNCHPAD_API}/ubuntu/+archive/primary?ws.op=getPublishedSources\
&source_name=${SOURCE_NAME}\
&distro_series=/ubuntu/${SUITE}\
&status=Published\
&order_by_date=true") \
  || die "Failed to query Launchpad API"

# Filter by exact source_package_name (source_name= is a prefix match on Launchpad)
VERSION=$(echo "$RESPONSE" | jq -r \
  --arg name "${SOURCE_NAME}" \
  '[.entries[] | select(.source_package_name == $name)] | .[0].source_package_version // empty')

[ -n "$VERSION" ] || die "No exact match for '${SOURCE_NAME}' in '${SUITE}'"

echo "${VERSION}"
