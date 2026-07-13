#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#
# seed-history.sh - One-time automated bootstrap: seed a branch of this repo with
#                   the FULL Canonical kernel history from Launchpad, pushing the
#                   upstream upload tags (e.g. Ubuntu-qcom-X.Y.Z-A.B) verbatim.
#
# Why a bootstrap is needed
# ─────────────────────────
# The steady-state sync (sync-mirror.sh) is incremental: it only works once the
# branch already holds real upstream history, so each new upload is a small
# delta. The branch starts empty, so the FULL history must be transferred from
# Launchpad exactly once. This script does that.
#
# How the history is transferred (both points proven empirically)
# ───────────────────────────────────────────────────────────────
#   * A FULL `git clone` is used, NOT shallow + `git fetch --deepen`: Launchpad's
#     shallow-deepen path is broken (it stalls and throws "error processing
#     shallow info"). Launchpad CAN serve a full clone, but spends many minutes
#     server-side computing the pack (the client sees ~0 bytes meanwhile), so the
#     git low-speed abort is relaxed to tolerate that quiet phase.
#   * GitHub caps a single push at 2 GB, so the seed is pushed in <2 GB slices.
#
# Single shot (no resume loop): the full clone either completes within the job's
# time budget or fails. On failure, re-dispatch -- the caller caches the cloned
# repo, so a retry skips re-downloading it and just re-attempts the publish.
#
# Usage:
#   seed-history.sh
#
# Required environment:
#   MIRROR_URL       Authenticated push URL of THIS repo
#   UPSTREAM_URL     Canonical/Launchpad git URL to seed from
#   BRANCH           Seed branch to create (e.g. resolute-qcom-seed)
#   UPSTREAM_PREFIX  Upstream tag prefix, mirrored verbatim (e.g. Ubuntu-qcom)
#   WORKDIR          Scratch dir (cached across runs by the caller)
#
# Optional environment:
#   PUSH_SLICE_COMMITS   Commits per push slice, to stay under GitHub's 2 GB
#                        per-push limit (default: 20000)
#
# Exit codes:
#   0  Seed complete and published
#   1  Hard error

set -euo pipefail

log()  { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
hr()   { log "────────────────────────────────────────────────────────────"; }
redact() { sed -E 's#(https?://)[^@/]*@#\1***@#g' <<<"$1"; }

: "${MIRROR_URL:?MIRROR_URL is required}"
: "${UPSTREAM_URL:?UPSTREAM_URL is required}"
: "${BRANCH:?BRANCH is required}"
: "${UPSTREAM_PREFIX:?UPSTREAM_PREFIX is required}"
: "${WORKDIR:?WORKDIR is required (cached across runs by the caller)}"

PUSH_SLICE_COMMITS="${PUSH_SLICE_COMMITS:-20000}"
SEED="${WORKDIR}/seed.git"

# Abort only a TRULY dead transfer. Launchpad spends many minutes server-side
# computing the pack for a full kernel history (the client sees ~0 bytes during
# "Counting/Compressing objects"); too short a low-speed window kills that
# legitimate compute phase. Tolerate a long quiet period, abort only if nothing
# moves for the full window.
export GIT_HTTP_LOW_SPEED_LIMIT="${GIT_HTTP_LOW_SPEED_LIMIT:-1000}"
export GIT_HTTP_LOW_SPEED_TIME="${GIT_HTTP_LOW_SPEED_TIME:-2400}"   # 40 min

hr
log "Canonical kernel history bootstrap"
log "  Seed branch   : ${BRANCH}"
log "  Upstream      : $(redact "${UPSTREAM_URL}")"
log "  Tags          : ${UPSTREAM_PREFIX}-* (verbatim)"
log "  Workdir       : ${WORKDIR}"
hr

mkdir -p "${WORKDIR}"

# ---------------------------------------------------------------------------
# 1. Full-clone the upstream history (fresh), or reuse a cached clone (retry).
#    A full clone is used rather than shallow + `git fetch --deepen`: Launchpad's
#    shallow-deepen path is broken, but it can serve a full clone. Retried a few
#    times to ride out transient stalls.
# ---------------------------------------------------------------------------
if [ ! -d "${SEED}" ]; then
  log "No cached clone found -- full-cloning upstream history (this is slow)..."
  for attempt in 1 2 3; do
    if git clone --bare "${UPSTREAM_URL}" "${SEED}"; then break; fi
    log "Full clone attempt ${attempt} failed; cleaning up and backing off..."
    rm -rf "${SEED}"
    sleep "$((attempt * 30))"
  done
  [ -d "${SEED}" ] || die "Full clone of ${UPSTREAM_URL} failed after retries."
else
  log "Reusing cached clone at ${SEED}."
fi

cd "${SEED}"
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "${UPSTREAM_URL}"

# A full clone is never shallow; assert it defensively, since GitHub rejects a
# shallow push outright.
[ ! -f "${SEED}/shallow" ] \
  || die "Clone is unexpectedly shallow -- cannot publish a shallow history."
log "Full history cloned: $(git rev-list --all --count) commits."

# ---------------------------------------------------------------------------
# 3. Fetch EVERY upload tag (full; the shared base is already local, so these
#    are cheap deltas) so each upload -- including any that upstream rebased onto
#    a divergent line -- is preserved under its own immutable tag.
# ---------------------------------------------------------------------------
log "Fetching all ${UPSTREAM_PREFIX}-* upload tags for full preservation..."
# On a resume, these tags may already be local; a re-pointed upstream tag then
# yields a non-zero "would clobber" instead of a silent overwrite (G10). Surface
# it clearly rather than letting `set -e` report an opaque failure.
if ! git fetch --no-tags upstream \
      "refs/tags/${UPSTREAM_PREFIX}-*:refs/tags/${UPSTREAM_PREFIX}-*" 2>fetch.err; then
  if grep -q 'would clobber existing tag' fetch.err; then
    die "An upstream ${UPSTREAM_PREFIX}-* tag was re-pointed since a previous \
attempt (immutability violation upstream). Refusing to clobber a preserved tag."
  fi
  cat fetch.err >&2
  die "Failed to fetch upstream upload tags."
fi

mapfile -t VERSIONS < <(
  git tag --list "${UPSTREAM_PREFIX}-*" \
    | sed -E "s#^${UPSTREAM_PREFIX}-##" | sort -V
)
[ "${#VERSIONS[@]}" -gt 0 ] || die "No upload tags present after fetch."
LATEST_VERSION="${VERSIONS[-1]}"
log "Uploads to preserve: ${VERSIONS[*]}"

# The upstream ${UPSTREAM_PREFIX}-* tags fetched above ARE the preservation tags,
# mirrored verbatim (Canonical's tag names) -- no re-tagging. Point the seed
# branch at the latest upload.
git update-ref "refs/heads/${BRANCH}" \
  "$(git rev-parse "${UPSTREAM_PREFIX}-${LATEST_VERSION}^{commit}")"

# ---------------------------------------------------------------------------
# 4. Sliced push: GitHub caps a single push at 2 GB, so push the latest branch's
#    history in commit-count checkpoints (each slice carries only the objects
#    between checkpoints), then the branch ref and every preservation tag.
# ---------------------------------------------------------------------------
# `git clone` set origin to the UPSTREAM (Launchpad) URL; repoint it at our
# mirror so the seed is pushed to GitHub, not back to Launchpad.
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "${MIRROR_URL}"
else
  git remote add origin "${MIRROR_URL}"
fi

# The scratch ref is a DISPOSABLE chunking aid, never history. It is force-pushed
# and cleared on every exit so a leftover from a failed prior attempt can never
# wedge a resume into a non-fast-forward (which would otherwise make the bootstrap
# non-convergent without manual intervention).
SCRATCH="refs/heads/_seed-progress"
cleanup_scratch() { git push origin ":${SCRATCH}" >/dev/null 2>&1 || true; }
trap cleanup_scratch EXIT
cleanup_scratch   # clear any leftover before we start

log "Slicing history into <2 GB pushes (every ${PUSH_SLICE_COMMITS} commits)..."
mapfile -t CHECKPOINTS < <(
  git rev-list --first-parent --reverse "refs/heads/${BRANCH}" \
    | awk -v n="${PUSH_SLICE_COMMITS}" 'NR % n == 0'
)
for cp in "${CHECKPOINTS[@]}"; do
  log "  push checkpoint ${cp:0:12} -> ${SCRATCH}"
  git push --force origin "${cp}:${SCRATCH}"
done

log "Pushing branch ${BRANCH} and ${#VERSIONS[@]} preservation tag(s)..."
git push origin "refs/heads/${BRANCH}"
git push origin "refs/tags/${UPSTREAM_PREFIX}-*"
# scratch ref is removed by the EXIT trap

hr
log "Bootstrap complete."
log "  Branch ${BRANCH} seeded with $(git rev-list --count "${BRANCH}") commits."
log "  Preserved uploads: ${VERSIONS[*]}"
log "  Latest: ${LATEST_VERSION}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "latest_version=${LATEST_VERSION}"        >> "${GITHUB_OUTPUT}"
  echo "preserved_count=${#VERSIONS[@]}"          >> "${GITHUB_OUTPUT}"
fi
