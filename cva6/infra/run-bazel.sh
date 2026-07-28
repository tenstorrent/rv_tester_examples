#!/usr/bin/env bash
# Run bazel-7 (bzlmod) for cva6_with_rvtester inside the cvm podman image.
# Usage: infra/run-bazel.sh build --config=bzlmod //dv/cva6/verilator:cva6_tb_verilator
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Public cvm image (bazel-7, clang, Python 3.9, verilator deps). Override with
# CVM_IMAGE=... if you have a local mirror.
IMAGE="${CVM_IMAGE:-ghcr.io/tenstorrent/cvm:0.1.3}"

# Mount the repo root (parent of this example) so the shared ../common module
# (local_path_override in MODULE.bazel) is visible inside the container.
REPO_ROOT="$(cd "$REPO/.." && pwd)"

# Bazel outputs + fetches. Defaults to an in-repo build/ dir (git-ignored);
# override with CVA6_OUTPUT_ROOT=... to point somewhere roomier. The transient
# exec sandbox lives on container-local /tmp (see .bazelrc --sandbox_base).
OUTPUT_ROOT="${CVA6_OUTPUT_ROOT:-$REPO_ROOT/build/cva6_bazel_root}"
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"

exec podman run --rm \
  -v "$REPO_ROOT:$REPO_ROOT" \
  -v "$OUTPUT_ROOT:$OUTPUT_ROOT" \
  -w "$REPO" \
  "$IMAGE" \
  bazel-7 --output_user_root="$OUTPUT_ROOT" "$@"
