#!/usr/bin/env bash
# Run bazel-7 (bzlmod) for cva6_with_rvtester inside the cvm podman image.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE="${CVM_IMAGE:-ghcr.io/tenstorrent/cvm:0.1.3}"
REPO_ROOT="$(cd "$REPO/.." && pwd)"
OUTPUT_ROOT="${CVA6_OUTPUT_ROOT:-$REPO_ROOT/build/cva6_bazel_root}"
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"

exec podman run --rm \
  -v "$REPO_ROOT:$REPO_ROOT" \
  -v "$OUTPUT_ROOT:$OUTPUT_ROOT" \
  -w "$REPO" \
  "$IMAGE" \
  bazel-7 --output_user_root="$OUTPUT_ROOT" "$@"
