#!/usr/bin/env bash
# Run bazel-7 (bzlmod) for openc910_with_rvtester inside the cvm podman image.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE="${CVM_IMAGE:-ghcr.io/tenstorrent/cvm:0.1.3}"
OUTPUT_ROOT="${OPENC910_OUTPUT_ROOT:-$REPO/../build/openc910_bazel_root}"

# Optional --run-path <dir> (or --run-path=<dir>) flag overrides env var.
if [ "${1:-}" = "--run-path" ]; then
  OUTPUT_ROOT="$2"; shift 2
elif [ "${1:-}" != "${1#--run-path=}" ]; then
  OUTPUT_ROOT="${1#--run-path=}"; shift
fi
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"

REPO_ROOT="$(cd "$REPO/.." && pwd)"

exec podman run --rm \
  -v "$REPO_ROOT:$REPO_ROOT" \
  -v "$OUTPUT_ROOT:$OUTPUT_ROOT" \
  -w "$REPO" \
  "$IMAGE" \
  bazel-7 --output_user_root="$OUTPUT_ROOT" "$@"
