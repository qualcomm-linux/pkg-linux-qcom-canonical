#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#
# sync-mirror.sh - Incrementally mirror new Canonical kernel upload tags into a
#                  branch of this repository while PRESERVING full upstream
#                  history.
#
# This is the steady-state "mirror-repoint" sync. It replaces the legacy
# shallow-clone + rsync + squash approach, which discarded all upstream history
# (one flattened snapshot commit per upload). Here, the branch becomes a faithful
# mirror of the upstream kernel tree: each upload is fetched with its real
# ancestry and frozen under an immutable per-upload tag.
#
# Mental model
# ────────────
#   * BRANCH  (e.g. resolute-qcom)            -- a MOVABLE "latest Canonical"
#                                                pointer; disposable by design.
#   * TAG     (e.g. Ubuntu-qcom-7.0.0-1006.8) -- the upstream Canonical tag,
#                                                mirrored VERBATIM. IMMUTABLE
#                                                per-upload record; the sole
#                                                anchor that preserves history.
#
# A sync is PURE FETCH + REPOINT -- it never merges or rebases, so it can never
# conflict and can never be blocked by developer patches layered on the branch.
# Developer patches are deliberately out of scope: the branch is force-advanced
# past them (they live on developers' own branches and are re-applied manually).
#
# Operational guardrails (each empirically validated by the history-preservation
# stress test; numbers refer to that test's findings):
#   G1  Pin the lease: --force-with-lease=<ref>:<old-sha>, never bare
#       --force-with-lease (a pre-push fetch silently defeats the bare form) and
#       never blind --force.
#   G2  Push the tag and the branch ATOMICALLY (--atomic) so they land together
#       or not at all -- prevents tag-lands/branch-rejected split-brain.
#   G3  Fail fast: abort the whole run on any rejected push. Never let the next
#       idempotent run mask an incomplete one.
#   G4  Tag every missing upload, ascending, and create the tag BEFORE moving the
#       branch. Latest-only silently drops unique commits from rebased uploads.
#   G5  Never use --depth on the incremental fetch -- the closure must be complete
#       and non-shallow.
#   G8  Operate on a BARE clone (no worktree) so the branch ref can be updated
#       without the "branch used by worktree" failure.
#   G10 Do not assume `git fetch` always exits 0 (a re-pointed upstream tag yields
#       a non-zero "would clobber existing tag" -- handled explicitly).
#
# Usage:
#   sync-mirror.sh
#
# Required environment:
#   MIRROR_URL       Authenticated push URL of THIS repo
#                    (e.g. https://x-access-token:TOKEN@github.com/org/repo.git)
#   UPSTREAM_URL     Canonical/Launchpad git URL to mirror from
#   BRANCH           Branch to advance (e.g. resolute-qcom)
#   UPSTREAM_PREFIX  Upstream tag prefix, mirrored verbatim (e.g. Ubuntu-qcom)
#
# Optional environment:
#   WORKDIR              Scratch directory for the bare mirror (default: mktemp)
#   MIN_HISTORY_COMMITS  Bootstrap sentinel: refuse to sync if BRANCH has fewer
#                        than this many commits, i.e. it has not been seeded with
#                        real history yet (default: 1000). Run bootstrap first.
#   GITHUB_OUTPUT        If set, the latest synced version is written as
#                        `synced_version=` and `synced_count=` for the caller.
#
# Exit codes:
#   0  Up to date or one-or-more uploads synced successfully
#   1  Hard error (bootstrap required, push rejected, etc.)

set -euo pipefail

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
hr()   { log "────────────────────────────────────────────────────────────"; }

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------
: "${MIRROR_URL:?MIRROR_URL is required}"
: "${UPSTREAM_URL:?UPSTREAM_URL is required}"
: "${BRANCH:?BRANCH is required}"
: "${UPSTREAM_PREFIX:?UPSTREAM_PREFIX is required}"

MIN_HISTORY_COMMITS="${MIN_HISTORY_COMMITS:-1000}"
WORKDIR="${WORKDIR:-$(mktemp -d)}"
MIRROR="${WORKDIR}/mirror.git"

# Redact credentials from any URL before printing it.
redact() { sed -E 's#(https?://)[^@/]*@#\1***@#g' <<<"$1"; }

hr
log "Canonical kernel mirror sync (history-preserving)"
log "  Branch         : ${BRANCH}"
log "  Upstream       : $(redact "${UPSTREAM_URL}")"
log "  Tags (verbatim) : ${UPSTREAM_PREFIX}-*"
hr

# ---------------------------------------------------------------------------
# 1. Clone OUR mirror as a BARE repo (G8: no worktree -> clean ref updates).
#    --filter=blob:none keeps the clone small: we need the commit/tree graph for
#    fetch negotiation and ref moves, not the file blobs (the upstream fetch
#    brings the new blobs, and the push only sends objects the mirror lacks).
#    --single-branch limits it to BRANCH so unrelated suite branches are not
#    pulled.
# ---------------------------------------------------------------------------
log "Cloning mirror (bare, blobless, single-branch ${BRANCH})..."
rm -rf "${MIRROR}"   # self-heal if an operator reuses a fixed WORKDIR
git clone --bare --filter=blob:none --single-branch --branch "${BRANCH}" \
  "${MIRROR_URL}" "${MIRROR}" \
  || die "Mirror does not yet contain branch '${BRANCH}'. Run bootstrap-history first."
cd "${MIRROR}"

# ---------------------------------------------------------------------------
# 2. Bootstrap sentinel: the incremental model only works if BRANCH already
#    carries real upstream history (so the upstream fetch transfers a small
#    delta, not the whole tree). A freshly created or legacy-squashed branch has
#    a handful of commits -- refuse, and point the operator at the bootstrap.
# ---------------------------------------------------------------------------
HISTORY_COUNT="$(git rev-list --count "${BRANCH}")"
log "Branch '${BRANCH}' currently has ${HISTORY_COUNT} commits."
if [ "${HISTORY_COUNT}" -lt "${MIN_HISTORY_COMMITS}" ]; then
  die "Branch '${BRANCH}' has only ${HISTORY_COUNT} commits (< ${MIN_HISTORY_COMMITS}); \
it has not been seeded with full Canonical history. Run the 'Bootstrap' workflow first."
fi

# A bare mirror must never be shallow (G5): a shallow base breaks negotiation and
# GitHub rejects shallow pushes outright.
if [ -f shallow ]; then
  die "Mirror clone is shallow -- refusing to sync. The seed must be fully \
unshallowed before incremental syncs can run."
fi

# ---------------------------------------------------------------------------
# 3. Discover which upstream uploads we have not mirrored yet.
#    Missing = upstream ${UPSTREAM_PREFIX}-<ver> tags not yet present in our
#    mirror (we mirror Canonical's tag names verbatim). Sorted ascending so a
#    rebased middle upload is preserved before the branch advances past it (G4).
# ---------------------------------------------------------------------------
git remote add upstream "${UPSTREAM_URL}"

# Capture ls-remote first so a transport failure (network/auth/5xx) is not
# silently flattened to an empty list and misreported as "no tags upstream".
upstream_raw="$(git ls-remote --tags upstream "refs/tags/${UPSTREAM_PREFIX}-*")" \
  || die "git ls-remote failed for upstream (network/auth?)."
mapfile -t UPSTREAM_VERSIONS < <(
  printf '%s\n' "${upstream_raw}" \
    | grep -v '\^{}' \
    | sed -E "s#.*refs/tags/${UPSTREAM_PREFIX}-##" \
    | sort -V
)
[ "${#UPSTREAM_VERSIONS[@]}" -gt 0 ] \
  || die "No ${UPSTREAM_PREFIX}-* tags found upstream."

MISSING=()
for ver in "${UPSTREAM_VERSIONS[@]}"; do
  if ! git rev-parse -q --verify "refs/tags/${UPSTREAM_PREFIX}-${ver}" >/dev/null; then
    MISSING+=("${ver}")
  fi
done

if [ "${#MISSING[@]}" -eq 0 ]; then
  log "Already up to date -- no new uploads to mirror."
  [ -n "${GITHUB_OUTPUT:-}" ] && {
    echo "synced_version=" >> "${GITHUB_OUTPUT}"
    echo "synced_count=0"   >> "${GITHUB_OUTPUT}"
  }
  exit 0
fi

log "Uploads to mirror (ascending): ${MISSING[*]}"

# ---------------------------------------------------------------------------
# 4. Mirror each missing upload in order: fetch the upstream tag (delta) ->
#    advance branch -> atomic, lease-pinned push of branch + the upstream tag.
#    Halt on the first failure (G3).
# ---------------------------------------------------------------------------
SYNCED=0
LAST_VERSION=""
for ver in "${MISSING[@]}"; do
  hr
  log "Mirroring upload ${ver}"

  upstream_tag="${UPSTREAM_PREFIX}-${ver}"

  # Lease baseline (G1): the branch value we are advancing FROM. Empty if the
  # branch somehow vanished between clone and now (treated as a create).
  old_sha="$(git rev-parse -q --verify "refs/heads/${BRANCH}" || true)"

  # Fetch ONLY this upload's tag, full depth (G5), into the SAME ref name so the
  # upstream annotated tag object becomes our preservation tag verbatim -- we
  # mirror Canonical's tag names exactly. Because the mirror already holds the
  # shared base, negotiation transfers just the new objects. A re-pointed
  # upstream tag returns non-zero "would clobber" (G10) -- surface it clearly
  # rather than letting `set -e` report a generic failure.
  if ! git fetch --no-tags upstream \
        "refs/tags/${upstream_tag}:refs/tags/${upstream_tag}" 2>fetch.err; then
    if grep -q 'would clobber existing tag' fetch.err; then
      die "Upstream tag '${upstream_tag}' was re-pointed (immutability violation \
upstream). Refusing to move our preservation tag. Manual review required."
    fi
    cat fetch.err >&2
    die "Failed to fetch upstream tag '${upstream_tag}'."
  fi

  new_sha="$(git rev-parse "${upstream_tag}^{commit}")"

  # Advance the movable "latest" pointer (bare repo: update-ref == branch -f,
  # with no worktree guard, G8). The upstream tag fetched above is already the
  # immutable per-upload record (G4); no re-tagging needed.
  git update-ref "refs/heads/${BRANCH}" "${new_sha}"

  # Push the branch and the tag ATOMICALLY (G2) with a PINNED lease (G1).
  # An empty old_sha means "create" -- assert the remote ref is absent.
  # Array (not a bare string) so a BRANCH with unexpected characters cannot
  # word-split or glob the push arguments.
  if [ -n "${old_sha}" ]; then
    lease=("--force-with-lease=refs/heads/${BRANCH}:${old_sha}")
  else
    lease=("--force-with-lease=refs/heads/${BRANCH}:")
  fi

  log "Pushing branch + tag atomically (lease pinned to ${old_sha:-<create>})..."
  if ! git push --atomic "${lease[@]}" origin \
        "refs/heads/${BRANCH}" \
        "refs/tags/${upstream_tag}"; then
    die "Atomic push rejected for ${ver} (stale lease or protected ref). \
Halting so the next run does not mask a partial sync (G3)."
  fi

  log "Mirrored ${ver}: branch ${BRANCH} -> ${new_sha:0:12}, tag ${upstream_tag}"
  SYNCED=$((SYNCED + 1))
  LAST_VERSION="${ver}"
done

hr
log "Sync complete: ${SYNCED} upload(s) mirrored; branch now at ${LAST_VERSION}."

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "synced_version=${LAST_VERSION}" >> "${GITHUB_OUTPUT}"
  echo "synced_count=${SYNCED}"          >> "${GITHUB_OUTPUT}"
fi
