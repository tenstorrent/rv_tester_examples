#!/usr/bin/env bash
# Run any command inside the cvm podman image. Knows nothing about bazel.
#
#   common/infra/in-container.sh <cmd> [args...]
#
# The repo root is mounted at its host path and $PWD is preserved, so paths on
# the command line mean the same thing inside and outside. CVM_IMAGE overrides
# the image; CVM_MOUNTS is a space-separated list of extra paths to bind-mount
# (needed only for paths outside the repo, e.g. an output root elsewhere).
set -euo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "$(dirname "$SELF")/../.." && pwd)"

IMAGE="${CVM_IMAGE:-ghcr.io/tenstorrent/cvm:0.1.3}"

mounts=(-v "$REPO_ROOT:$REPO_ROOT")
for m in ${CVM_MOUNTS:-}; do
  mounts+=(-v "$m:$m")
done

exec podman run --rm "${mounts[@]}" -w "$PWD" "$IMAGE" "$@"
