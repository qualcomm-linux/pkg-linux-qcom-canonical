# Building the kernel locally

Builds `resolute-qcom-devel`, or any mirrored upload, into `.deb` packages
with the same container and steps as
[build-kernel.yml](../.github/workflows/build-kernel.yml).

For triggering a build in CI, see [PIPELINE.md](PIPELINE.md#running-it). For
working on contributions, see [INTEGRATION.md](INTEGRATION.md).

## Prerequisites

Native `arm64` with Docker. The builder image is `arm64`, and this path builds
the kernel natively; there is no cross build.

The source clone is ~2 GB and the builder image ~2 GB, before the build tree.

## Build

Work in an empty directory. Every command below runs from it.

```bash
mkdir kbuild && cd kbuild
```

Clone the branch to build:

```bash
git clone --depth 1 -b resolute-qcom-devel \
  https://github.com/qualcomm-linux/ubuntu-qcom-kernel.git kernel-src
```

Build the builder image. It is tagged by base suite, so both `resolute-qcom`
and `resolute-qcom-devel` use `resolute`:

```bash
git clone https://github.com/qualcomm-linux/docker-pkg-build.git
./docker-pkg-build/docker_deb_build.py --rebuild -d resolute
```

Build the packages:

```bash
docker run -i --rm \
  -v "$PWD:$PWD" --workdir="$PWD" -e JOBS="$(nproc)" \
  ghcr.io/qualcomm-linux/pkg-builder:resolute \
  bash -c '
    set -euo pipefail
    install -D -m644 /tmp/keyrings/qsc-deb-releases.asc \
      /etc/apt/keyrings/qsc-deb-releases.asc
    cp /tmp/qsc-deb-releases.sources /etc/apt/sources.list.d/
    apt-get update -qq
    cd kernel-src
    fakeroot make -f debian/rules clean
    apt-get build-dep -y ./
    export DEB_BUILD_OPTIONS="parallel=${JOBS} nocheck"
    fakeroot debian/rules binary-indep binary-qcom do_skip_checks=true
  '
```

Collect the output. It lands beside `kernel-src`, not inside it:

```bash
ls -lh *.deb
```

These packages carry the plain `debian.qcom/changelog` version. CI appends
`+qcom<N>.<sha>` when the branch has commits past a Canonical tag; a local
build does not, so its version matches the Canonical upload it is based on.

## Targets

Flavours are `qcom` and `qcom-rt`. There is no `generic`.

| Goal | Target |
|---|---|
| One flavour | `binary-indep binary-qcom` |
| Both | `binary-indep binary-qcom binary-qcom-rt` |
| Everything | `binary` |

Add `do_dbgsym_package=true` for the unstripped `-dbgsym.ddeb` packages.

## If it fails

| Symptom | Cause |
|---|---|
| `unauthorized` pulling the image | Expected, it is private. Build it locally instead. |
| `repo is NOT UP TO DATE` | `docker-pkg-build` checkout is behind its remote. |
| `Unable to locate package *-dkms` | The Qualcomm sources file was not installed, or qartifactory is unreachable. |
| `Unmet build dependencies` | `debian/rules clean` did not run first, so `debian/control` was absent. |
| `No rule to make target 'binary-generic'` | Wrong flavour. Use `qcom` or `qcom-rt`. |
| No `.deb` found | They are beside `kernel-src`, not inside it. |
