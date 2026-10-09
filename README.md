# ubuntu-qcom-kernel

Mirrors the Canonical kernel optimized for Qualcomm on `resolute-qcom`, from
[Launchpad](https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute/log/?h=master-next),
with Qualcomm contributions.

> [!TIP]
> Latest upload: see the **[tags page](https://github.com/qualcomm-linux/ubuntu-qcom-kernel/tags)**.

## At a glance

| | |
|---|---|
| **Upstream** | [https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute](https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute) |
| **`resolute-qcom`** | Mirror of that kernel - sync-only, do not commit here |
| **`resolute-qcom-devel`** | Integration branch - Qualcomm contributions (via PR) |
| **Output** | Kernel `.deb` packages, uploaded to S3 |

> [!NOTE]
> `main` is the **CI orchestrator** - the workflows, scripts, and docs that drive the sync and build.

## Documentation

| Doc | For |
|-----|-----|
| **[docs/INTEGRATION.md](docs/INTEGRATION.md)** | Qualcomm developers - working on `resolute-qcom-devel` |
| **[docs/LOCAL-BUILD.md](docs/LOCAL-BUILD.md)** | Developers - building the kernel locally |
| **[docs/PIPELINE.md](docs/PIPELINE.md)** | Maintainers - sync, build, and mirror operations |
| **[CONTRIBUTING.md](CONTRIBUTING.md)** | This project is not accepting contributions |
| **[SECURITY.md](SECURITY.md)** | This project is not actively maintained. It is a mirror. |

## License

| Scope | License |
|-------|---------|
| Workflows, scripts, and documentation on `main` | BSD 3-Clause - see **[LICENSE.txt](LICENSE.txt)** |
