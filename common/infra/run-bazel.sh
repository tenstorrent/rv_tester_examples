#!/usr/bin/env bash
# Convenience for local dev: bazel.sh inside the cvm image. Symlinked as
# infra/run-bazel.sh.
#
#   ./infra/run-bazel.sh build --config=bzlmod //cva6/dv/verilator:...
#
# CI already runs inside the image and calls bazel.sh directly.
set -euo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
HERE="$(dirname "$SELF")"

# An explicit output root may live outside the repo, which in-container.sh does
# not mount by default. Resolve it here so it can be mounted, and hand it to
# bazel.sh as a flag — the container gets a fresh environment, so BAZEL_OUTPUT_ROOT
# would not survive the podman boundary. The default root is under the repo root
# and so is already mounted.
OUT="${BAZEL_OUTPUT_ROOT:-}"
if [ "${1:-}" = "--run-path" ]; then
  OUT="$2"; shift 2
elif [ "${1:-}" != "${1#--run-path=}" ]; then
  OUT="${1#--run-path=}"; shift
fi

run_path=()
if [ -n "$OUT" ]; then
  mkdir -p "$OUT"
  OUT="$(cd "$OUT" && pwd)"
  run_path=(--run-path "$OUT")
  export CVM_MOUNTS="${CVM_MOUNTS:-} $OUT"
fi

exec "$HERE/in-container.sh" "$HERE/bazel.sh" "${run_path[@]}" "$@"
