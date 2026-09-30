#!/usr/bin/env bash
# Convenience for local dev: bazel.sh inside the cvm image. Symlinked as
# infra/run-bazel.sh.
#
#   ./infra/run-bazel.sh build --config=bzlmod //cva6/dv/verilator:...
#   ./infra/run-bazel.sh test  --config=bzlmod //cva6/dv/testlists:all_smoke --run-args +dbg +save_all_files
#
# Flags:
# --output-root <dir> (output root, must be first);
# --run-path <dir> (where the simulator writes its logs/dumps);
# --run-args <+plusargs...> or `-- <+plusargs...>` (extra simulator args for test/run targets, must be last).
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
if [ "${1:-}" = "--output-root" ]; then
  OUT="$2"; shift 2
elif [ "${1:-}" != "${1#--output-root=}" ]; then
  OUT="${1#--output-root=}"; shift
fi

output_root=()
if [ -n "$OUT" ]; then
  mkdir -p "$OUT"
  OUT="$(cd "$OUT" && pwd)"
  output_root=(--output-root "$OUT")
  export CVM_MOUNTS="${CVM_MOUNTS:-} $OUT"
fi

args=()
while [ $# -gt 0 ]; do
  a="$1"; shift
  d=""
  case "$a" in
    --run-path)
      if [ $# -eq 0 ]; then
        echo "run-bazel.sh: --run-path needs a value" >&2
        exit 1
      fi
      d="$1"; shift ;;
    --run-path=*) d="${a#--run-path=}" ;;
    --|--run-args|--run-arg)
      args+=("$a" "$@"); break ;;
  esac
  if [ -n "$d" ]; then
    mkdir -p "$d"
    d="$(cd "$d" && pwd)"
    export CVM_MOUNTS="${CVM_MOUNTS:-} $d"
    args+=("--run-path=$d")
  else
    args+=("$a")
  fi
done

exec "$HERE/in-container.sh" "$HERE/bazel.sh" "${output_root[@]}" "${args[@]}"
