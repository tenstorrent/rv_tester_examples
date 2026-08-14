#!/usr/bin/env bash
# Run bazel-7 (bzlmod) for the example workspace containing $PWD.
#
# No container: this is the plain bazel invocation, usable both on a host that
# already has bazel-7 and inside CI, which runs in the cvm image. To get the
# container too, use run-bazel.sh (this script under in-container.sh).
#
#   ../common/infra/bazel.sh build --config=bzlmod //dv/cva6/verilator:...
#
# Output root defaults to <repo>/build/<example>_bazel_root; override with
# BAZEL_OUTPUT_ROOT or --run-path <dir>. BAZEL overrides the bazel binary.
set -euo pipefail

# Example workspace = nearest ancestor of $PWD holding a MODULE.bazel.
EXAMPLE="$PWD"
while [ ! -f "$EXAMPLE/MODULE.bazel" ]; do
  if [ "$EXAMPLE" = "/" ]; then
    echo "bazel.sh: no MODULE.bazel in $PWD or any parent" >&2
    exit 1
  fi
  EXAMPLE="$(dirname "$EXAMPLE")"
done
REPO_ROOT="$(cd "$EXAMPLE/.." && pwd)"

OUTPUT_ROOT="${BAZEL_OUTPUT_ROOT:-$REPO_ROOT/build/$(basename "$EXAMPLE")_bazel_root}"

# Optional --run-path <dir> (or --run-path=<dir>) overrides the env var.
if [ "${1:-}" = "--run-path" ]; then
  OUTPUT_ROOT="$2"; shift 2
elif [ "${1:-}" != "${1#--run-path=}" ]; then
  OUTPUT_ROOT="${1#--run-path=}"; shift
fi
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"

exec "${BAZEL:-bazel-7}" --output_user_root="$OUTPUT_ROOT" "$@"
