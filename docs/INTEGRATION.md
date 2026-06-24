# Developing on `resolute-qcom-devel`

Qualcomm's downstream kernel patches live on the `resolute-qcom-devel` branch, on
top of the `resolute-qcom` mirror of the Canonical kernel. This guide is for
developers adding those patches.

For how the mirror and build pipeline work, see [PIPELINE.md](PIPELINE.md).

## The branches

| Branch | Role |
|--------|------|
| `resolute-qcom` | The mirror of the upstream Canonical kernel. Only the automated sync writes to it - **do not commit here**. |
| `resolute-qcom-devel` | The integration branch: Qualcomm's downstream patches on top of `resolute-qcom`. **Push your patches here.** |

The `-devel` suffix follows Canonical's own `devel` naming convention.

## Contributing patches

Downstream kernel patches land on `resolute-qcom-devel` through a **pull request** -
work on a feature branch and open a PR into `resolute-qcom-devel`. Never commit to
`resolute-qcom`: the sync is its only writer and force-advances it on every new
upload.

```bash
git clone https://github.com/qualcomm-linux/pkg-linux-qcom-canonical.git
cd pkg-linux-qcom-canonical
git checkout -b my-feature origin/resolute-qcom-devel   # feature branch off the integration branch
# add your patches, commit DCO-signed (git commit -s), then:
git push origin my-feature
```

Then open a pull request from your feature branch **into `resolute-qcom-devel`**.
Commits must carry a DCO `Signed-off-by` line (`git commit -s`); see
[CONTRIBUTING.md](../CONTRIBUTING.md) for the sign-off policy.

## Building

To build `resolute-qcom-devel` (or any mirrored upload) into `.deb` packages, see
[PIPELINE.md](PIPELINE.md#manual-build-triggers).
