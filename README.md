# pkg-linux-qcom-canonical

Mirrors the Qualcomm-Ubuntu (Canonical) kernel on `resolute-qcom` and builds it
into `.deb` packages. Qualcomm developers add downstream patches on the
`resolute-qcom-devel` integration branch.

> [!TIP]
> Latest upload: see the **[tags page](https://github.com/qualcomm-linux/pkg-linux-qcom-canonical/tags)**.

## At a glance

| | |
|---|---|
| **Upstream** | [carmel-team Qualcomm-Ubuntu kernel](https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute) |
| **`resolute-qcom`** | Mirror of that kernel - sync-only, do not commit here |
| **`resolute-qcom-devel`** | Integration branch - Qualcomm's downstream patches (via PR) |
| **Output** | Kernel `.deb` packages, uploaded to S3 |

> [!NOTE]
> `main` is the **CI orchestrator** - the workflows, scripts, and docs that drive the sync and build.

## Add a downstream patch

> [!IMPORTANT]
> Patches reach `resolute-qcom-devel` through a **feature branch + pull request**. Branch off the integration branch, push your branch, then open a PR back into it.

```bash
git clone https://github.com/qualcomm-linux/pkg-linux-qcom-canonical.git
cd pkg-linux-qcom-canonical
git checkout -b my-feature origin/resolute-qcom-devel   # branch off the integration branch
# add your patches, then commit DCO-signed:
git commit -s
git push origin my-feature
```

Then open a PR from `my-feature` **into `resolute-qcom-devel`**. See
**[docs/INTEGRATION.md](docs/INTEGRATION.md)** for the full workflow.

## Golden rules

> [!WARNING]
> - :no_entry: **Never commit to `resolute-qcom`.** The sync is its only writer and force-advances it on every upload.
> - :no_entry: **Never push directly to `resolute-qcom-devel`.** Patches land through a feature branch + pull request.
> - :white_check_mark: DCO `Signed-off-by` is required on every commit (`git commit -s`).

## Documentation

| Doc | For |
|-----|-----|
| **[scripts/README.md](scripts/README.md)** | Users - building kernel .deb packages locally |
| **[docs/INTEGRATION.md](docs/INTEGRATION.md)** | Qualcomm developers - working on `resolute-qcom-devel` |
| **[docs/PIPELINE.md](docs/PIPELINE.md)** | Maintainers - sync, build, and mirror operations |
| **[CONTRIBUTING.md](CONTRIBUTING.md)** | Contributing to the CI orchestrator on `main` |
| **[SECURITY.md](SECURITY.md)** | Reporting security issues |

## License

| Scope | License |
|-------|---------|
| CI scripts and workflows | BSD 3-Clause - see **[LICENSE.txt](LICENSE.txt)** |
| Mirrored kernel source | GPL-2.0 and the individual licences of its components |
