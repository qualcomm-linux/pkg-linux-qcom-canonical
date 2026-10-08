# Developing on `resolute-qcom-devel`

Qualcomm contributions live on the `resolute-qcom-devel` branch, on
top of the `resolute-qcom` mirror of the Canonical kernel. This guide is for
developers working on those contributions.

For how the mirror and build pipeline work, see [PIPELINE.md](PIPELINE.md).

## The branches

| Branch | Role |
|--------|------|
| `resolute-qcom` | The mirror of the upstream Canonical kernel. Only the automated sync writes to it - **do not commit here**. |
| `resolute-qcom-devel` | The integration branch: Qualcomm contributions on top of `resolute-qcom`. **Use pull requests for changes here.** |

The `-devel` suffix follows Canonical's own `devel` naming convention.

## Working on Qualcomm contributions

Qualcomm contributions land on `resolute-qcom-devel` through a **pull request** -
work on a feature branch and open a PR into `resolute-qcom-devel`. Never commit to
`resolute-qcom`: the sync is its only writer and force-advances it on every new
upload.

```bash
git clone https://github.com/qualcomm-linux/ubuntu-qcom-kernel.git
cd ubuntu-qcom-kernel
git checkout -b my-feature origin/resolute-qcom-devel   # feature branch off the integration branch
# add your patches, commit DCO-signed (git commit -s), then:
git push origin my-feature
```

Then open a pull request from your feature branch **into `resolute-qcom-devel`**.
Commits must carry a DCO `Signed-off-by` line (`git commit -s`) as required for Qualcomm contribution review.

## Building

To build `resolute-qcom-devel` (or any mirrored upload) locally, see
[LOCAL-BUILD.md](LOCAL-BUILD.md).

To run the build in CI instead, see
[PIPELINE.md](PIPELINE.md#running-it).
