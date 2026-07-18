#!/usr/bin/env bash
# Run bazel-7 (bzlmod) for openc910_with_rvtester inside the cvm podman image.
# Usage: infra/run-bazel.sh build --config=bzlmod //dv/openc910/verilator:openc910_tb_verilator
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Public cvm image (bazel-7, clang, Python 3.9, verilator deps). Override with
# CVM_IMAGE=... if you have a local mirror.
IMAGE="${CVM_IMAGE:-ghcr.io/tenstorrent/cvm:0.1.3}"

# Bazel outputs + fetches. Defaults to a local dir; override with
# CVA6_OUTPUT_ROOT=... to point somewhere roomier. The transient exec sandbox
# lives on container-local /tmp (see .bazelrc --sandbox_base).
OUTPUT_ROOT="${OPENC910_OUTPUT_ROOT:-$HOME/.cache/openc910_bazel_root}"
mkdir -p "$OUTPUT_ROOT"

exec podman run --rm \
  -v "$REPO:$REPO" \
  -v "$OUTPUT_ROOT:$OUTPUT_ROOT" \
  -w "$REPO" \
  "$IMAGE" \
  bazel-7 --output_user_root="$OUTPUT_ROOT" "$@"
