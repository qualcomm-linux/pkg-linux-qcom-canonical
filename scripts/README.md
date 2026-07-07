# Kernel Build Scripts

This directory contains scripts for building Ubuntu kernel .deb packages for Qualcomm platforms.

## Setup & Build Steps

### 1. Docker Access

Ensure your user can run Docker without sudo. If not already configured:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Verify Docker access:

```bash
docker ps
```

### 2. Prepare Workspace

Create a workspace directory (you can rename `canonical-pkg` as needed):

```bash
mkdir canonical-pkg && cd canonical-pkg
```

### 3. Pull Required Repositories

#### a) Pull the CI orchestrator (main branch)

```bash
git clone --depth 1 https://github.com/qualcomm-linux/pkg-linux-qcom-canonical.git
```

#### b) Pull the kernel source (resolute-qcom-devel branch)

```bash
git clone -b resolute-qcom-devel --depth 1 https://github.com/qualcomm-linux/pkg-linux-qcom-canonical.git resolute-qcom-devel
```

#### c) Pull the Qualcomm DTB metadata

```bash
git clone https://github.com/qualcomm-linux/qcom-dtb-metadata.git
```

Make the build scripts executable:

```bash
chmod +x pkg-linux-qcom-canonical/scripts/docker-build-kernel.sh
chmod +x qcom-dtb-metadata/build-dtb-image.sh
```

After completing the above, your workspace structure should look like:

```
canonical-pkg/
├── pkg-linux-qcom-canonical/          # CI orchestrator (main branch)
│   ├── scripts/
│   │   ├── docker-build-kernel.sh     # Docker wrapper for builds
│   │   ├── build-kernel-deb.sh        # Core build script
│   │   ├── README.md
│   │   └── ...
│   └── ...
├── resolute-qcom-devel/               # Kernel source (resolute-qcom-devel branch)
│   ├── debian.qcom/                   # Qualcomm-specific build config
│   ├── arch/
│   ├── drivers/
│   └── ...
├── qcom-dtb-metadata/                 # DTB metadata
│   ├── build-dtb-image.sh
│   └── ...
└── output/                            # Build artifacts (created after first build)
    ├── linux-image-*.deb
    ├── linux-modules-*.deb
    ├── linux-headers-*.deb
    └── ...
```

### 4. (Optional) Prepare Docker Image for External Users

If you don't have access to the Qualcomm internal Docker registry, prepare a Docker image with Ubuntu base.

#### For arm64 Hosts

Prepare a Docker image named `resolute:arm64` with Ubuntu 26.04 as the base, then run:

```bash
IMAGE=resolute:arm64 SKIP_BUILD_DEP=0 ./pkg-linux-qcom-canonical/scripts/docker-build-kernel.sh
```

#### For amd64 Hosts

Prepare a Docker image named `resolute:amd64` with Ubuntu 26.04 as the base, then run:

```bash
IMAGE=resolute:amd64 SKIP_BUILD_DEP=0 ./pkg-linux-qcom-canonical/scripts/docker-build-kernel.sh
```

**Image requirements:**
- **Docker image base**: Ubuntu 26.04
- **Packages**: Only needs basic packages (`apt`, `curl`, etc.) — build dependencies are installed inside the container at runtime

---

## Quick Decision Guide

| Your Situation | Use This | Why |
|---|---|---|
| Internal Qualcomm dev | `docker-build-kernel.sh` | Pre-installed deps, fastest |
| External user | `docker-build-kernel.sh` with `SKIP_BUILD_DEP=0` | Install deps inside container |

## Quick Start

After completing the setup steps above:

```bash
# Internal user
./pkg-linux-qcom-canonical/scripts/docker-build-kernel.sh

# External user
IMAGE=resolute:arm64 SKIP_BUILD_DEP=0 ./pkg-linux-qcom-canonical/scripts/docker-build-kernel.sh
```

Output packages: `./output/`

---

## Common Arguments & Environment Variables

### Arguments

```bash
./scripts/docker-build-kernel.sh [SOURCE_DIR] [ARCH] [FLAVOR] [JOBS] [VERSION_SUFFIX]
```

| Argument | Default | Description |
|----------|---------|-------------|
| `SOURCE_DIR` | `resolute-qcom-devel` | Root of kernel source tree |
| `ARCH` | `arm64` | Target architecture: `arm64` |
| `FLAVOR` | `qcom` | Kernel flavor: `qcom`, `qcom-rt`, or `all` (builds both `qcom` and `qcom-rt`) |
| `JOBS` | `$(nproc)` | Parallel make jobs |
| `VERSION_SUFFIX` | (none) | Version suffix (e.g., `+g1a2b3c4` or `+myuser1`). Pass `auto` to generate from git HEAD |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE` | (auto-detected) | Docker image to use |
| `SKIP_BUILD_DEP` | `1` | Set to `0` to install deps inside container (for bare Ubuntu images) |
| `DEBEMAIL` | `build-kernel-deb@localhost` | Email for changelog entries |
| `DEBFULLNAME` | `build-kernel-deb.sh` | Full name for changelog entries |
| `DOCKER_REGISTRY` | `docker-registry.qualcomm.com` | Docker registry URL (for internal users) |

---

## docker-build-kernel.sh

Docker wrapper script for containerized kernel builds.

### Usage

```bash
./scripts/docker-build-kernel.sh [SOURCE_DIR] [ARCH] [FLAVOR] [JOBS] [VERSION_SUFFIX]
```

### Examples

```bash
# Basic build (internal user)
./scripts/docker-build-kernel.sh

# With custom version
./scripts/docker-build-kernel.sh resolute-qcom-devel arm64 qcom $(nproc) +v1.0

# Auto-generate version from git
./scripts/docker-build-kernel.sh resolute-qcom-devel arm64 qcom $(nproc) auto

# External user with bare Ubuntu image (install deps inside container)
IMAGE=resolute:arm64 SKIP_BUILD_DEP=0 ./scripts/docker-build-kernel.sh
```

---

## Create FIT dtb.bin

After kernel build completes, create the FIT dtb.bin image:

```bash
cd qcom-dtb-metadata

# Build dtb.bin from kernel modules deb
sudo ./build-dtb-image.sh --kernel-deb {kernel-deb-path}/linux-modules-7.0.0-1006-qcom_7.0.0-1006.8_arm64.deb --out dtb.bin --prune
```

Output: `dtb.bin`

---

## Update Kernel and DTB

### 1. Install Kernel on Target Machine

Example for kernel 7.0.0-1006-qcom:

```bash
# Required
sudo dpkg -i linux-modules-7.0.0-1006-qcom_7.0.0-1006.8_arm64.deb
sudo dpkg -i linux-image-7.0.0-1006-qcom_7.0.0-1006.8_arm64.deb

# Optional: kernel headers (for out-of-tree module development)
sudo dpkg -i linux-headers-7.0.0-1006-qcom_7.0.0-1006.8_arm64.deb
```

### 2. Flash dtb.bin

First, ensure the `qdl` tool is installed:

```bash
# Install qdl (Qualcomm Download tool)
sudo apt-get install -y qdl
```

Then flash the dtb.bin:

```bash
qdl --storage spinor xbl_s_devprg_ns.melf write dtb_a dtb.bin
```

---

## License

SPDX-License-Identifier: BSD-3-Clause

See individual script headers for details.
