#!/usr/bin/env bash
# Run bazel-7 (bzlmod) for the repo module containing $PWD.
#
# No container: this is the plain bazel invocation, usable both on a host that
# already has bazel-7 and inside CI, which runs in the cvm image. To get the
# container too, use run-bazel.sh (this script under in-container.sh).
#
#   common/infra/bazel.sh build --config=bzlmod //cva6/dv/verilator:...
#
# Output root defaults to <repo>/build/bazel_root; override with
# BAZEL_OUTPUT_ROOT or --run-path <dir>. BAZEL overrides the bazel binary.
set -euo pipefail

# Repo root = nearest ancestor of $PWD holding a MODULE.bazel (the whole
# repo is one module).
REPO_ROOT="$PWD"
while [ ! -f "$REPO_ROOT/MODULE.bazel" ]; do
  if [ "$REPO_ROOT" = "/" ]; then
    echo "bazel.sh: no MODULE.bazel in $PWD or any parent" >&2
    exit 1
  fi
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done

OUTPUT_ROOT="${BAZEL_OUTPUT_ROOT:-$REPO_ROOT/build/bazel_root}"

# Optional --run-path <dir> (or --run-path=<dir>) overrides the env var.
if [ "${1:-}" = "--run-path" ]; then
  OUTPUT_ROOT="$2"; shift 2
elif [ "${1:-}" != "${1#--run-path=}" ]; then
  OUTPUT_ROOT="${1#--run-path=}"; shift
fi
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"

exec "${BAZEL:-bazel-7}" --output_user_root="$OUTPUT_ROOT" "$@"
