# Canonical Premerge Distro Validation Smoke Test

This temporary documentation-only change validates the complete Canonical
premerge pipeline for pull requests targeting `resolute-qcom-devel`.

The expected flow is:

1. Build and upload the Canonical kernel Debian packages.
2. Build the pinned Resolute IoT server and desktop images.
3. Publish both image tarballs and validation receipts beside the kernel packages.
4. Validate the completion marker and report the result on this pull request.

This change is for pipeline validation only and must not be merged.
