#!/usr/bin/env bash
# Run bazel-7 (bzlmod) for openc910_with_rvtester inside the cvm podman image.
# Usage: infra/run-bazel.sh build --config=bzlmod //dv/openc910/verilator:openc910_tb_verilator
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Public cvm image (bazel-7, clang, Python 3.9, verilator deps). Override with
# CVM_IMAGE=... if you have a local mirror.
IMAGE="${CVM_IMAGE:-ghcr.io/tenstorrent/cvm:0.1.3}"

# Bazel outputs + fetches. Defaults to an in-repo build/ dir (git-ignored);
# point it somewhere roomier via the OPENC910_OUTPUT_ROOT env var or the
# --run-path <dir> flag (flag wins). The transient exec sandbox lives on
# container-local /tmp (.bazelrc --sandbox_base).
OUTPUT_ROOT="${OPENC910_OUTPUT_ROOT:-$REPO/../build/openc910_bazel_root}"

# Optional leading flag: --run-path <dir> (or --run-path=<dir>).
if [ "${1:-}" = "--run-path" ]; then
  OUTPUT_ROOT="$2"; shift 2
elif [ "${1:-}" != "${1#--run-path=}" ]; then
  OUTPUT_ROOT="${1#--run-path=}"; shift
fi
mkdir -p "$OUTPUT_ROOT"
# podman -v requires an absolute path; resolve a relative --run-path/env value.
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"

# Mount the repo root (parent of this example) so the shared ../common module
# (local_path_override in MODULE.bazel) is visible inside the container.
REPO_ROOT="$(cd "$REPO/.." && pwd)"

exec podman run --rm \
  -v "$REPO_ROOT:$REPO_ROOT" \
  -v "$OUTPUT_ROOT:$OUTPUT_ROOT" \
  -w "$REPO" \
  "$IMAGE" \
  bazel-7 --output_user_root="$OUTPUT_ROOT" "$@"
