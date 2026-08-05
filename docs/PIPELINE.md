# Pipeline operations (maintainers)

How the mirror and build pipeline work. To contribute patches, see
[INTEGRATION.md](INTEGRATION.md).

## Repository branch layout

```
pkg-linux-qcom-canonical
│
├── main branch                       ← CI orchestrator: workflows, scripts, docs
│   ├── .github/workflows/
│   │   ├── fetch-source-pkg.yml      ← manual incremental mirror sync
│   │   ├── bootstrap-history.yml     ← one-time history seed
│   │   └── build-kernel.yml          ← build .deb packages (+ reusable workflow_call)
│   ├── scripts/                      ← sync-mirror.sh, seed-history.sh (self-documenting)
│   └── README.md
│
├── resolute-qcom branch              ← upstream Ubuntu kernel mirror (SYNC-ONLY)
│   └── immutable tag per upload: Ubuntu-qcom-X.Y.Z-A.B
│
├── resolute-qcom-devel branch        ← developer integration branch (see INTEGRATION.md)
│   └── .github/workflows/premerge-pr.yml  ← pre-merge PR build check (lives here, not on main)
│
└── resolute-qcom-seed branch         ← transient bootstrap staging (only during a seed)
```

`resolute-qcom` shares no history with `main` (the CI orchestrator); it holds the
upstream kernel tree the packages are built from.

## How it works

`resolute-qcom` mirrors the upstream Ubuntu kernel: each upload is fetched and
frozen under an immutable `Ubuntu-qcom-X.Y.Z-A.B` tag. A one-time bootstrap seeds
the branch; thereafter an incremental sync advances it per new upstream upload and
triggers a build. Builds produce `.deb` packages uploaded to a private S3 bucket
(no GitHub artifacts or releases). Qualcomm contributions land on `resolute-qcom-devel`,
never on the mirror.

Upstream source: [https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute](https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute).

## Running it

All three workflows are manual (`Actions → … → Run workflow`, or via `gh`):

```bash
# Sync the mirror to the latest upstream upload (no inputs; idempotent).
gh workflow run fetch-source-pkg.yml --repo qualcomm-linux/pkg-linux-qcom-canonical

# Build .deb packages. Defaults to resolute-qcom-devel HEAD; set the suite input to
# resolute-qcom for the mirror, or kernel_version for an exact tag. The dbgsym
# input (default true) also builds the unstripped -dbgsym.ddeb.
gh workflow run build-kernel.yml --repo qualcomm-linux/pkg-linux-qcom-canonical

# One-time only, before the first sync: seed resolute-qcom with history (into
# resolute-qcom-seed, which a human then promotes to the live branch).
gh workflow run bootstrap-history.yml --repo qualcomm-linux/pkg-linux-qcom-canonical
```

PRs into `resolute-qcom-devel` get a pre-merge build check (`premerge-pr.yml` on
that branch), which calls `build-kernel.yml` with `flavours=qcom`,
`dbgsym=false`, and `s3_prefix=premerge` (binary-indep is always built
regardless of `flavours`). Its packages are uploaded to S3 under
`pkg/premerge/`, separate from the `pkg/temp/` prefix used by nightly and
manual `workflow_dispatch` runs.

