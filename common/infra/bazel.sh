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
# BAZEL_OUTPUT_ROOT or --output-root <dir>. BAZEL overrides the bazel binary.
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

if [ "${1:-}" = "--output-root" ]; then
  OUTPUT_ROOT="$2"; shift 2
elif [ "${1:-}" != "${1#--output-root=}" ]; then
  OUTPUT_ROOT="${1#--output-root=}"; shift
fi
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"

# Process the --run-args, --run-path and -- (double-dash or end of options)
#   ... --run-args +dbg +save_all_files      everything after --run-args
#   ... -- +dbg +save_all_files              everything after -- that starts with '+'
#   ... --run-path <dir>                     directory for the simulator's logs and dumps
cmd=""
run_path=""
run_args=()
pre=()
post=()
seen_dd=0
mode=pre
while [ $# -gt 0 ]; do
  a="$1"; shift
  case "$mode" in
    pre)
      case "$a" in
        --run-args|--run-arg) mode=run_args ;;
        --run-path)
          if [ $# -eq 0 ]; then
            echo "bazel.sh: --run-path needs a value" >&2
            exit 1
          fi
          run_path="$1"; shift ;;
        --run-path=*) run_path="${a#--run-path=}" ;;
        --) mode=post ;;
        -*) pre+=("$a") ;;
        *) [ -n "$cmd" ] || cmd="$a"; pre+=("$a") ;;
      esac ;;
    run_args)
      case "$a" in
        --) mode=post ;;
        *) run_args+=("$a") ;;
      esac ;;
    post)
      post+=("$a") ;;
  esac
done
[ "$mode" = post ] && seen_dd=1

if [ -n "$run_path" ]; then
  case "$cmd" in
    test|coverage|run) ;;
    *)
      echo "bazel.sh: --run-path only applies to 'test' or 'run' (command: '${cmd:-none}')" >&2
      exit 1 ;;
  esac
  mkdir -p "$run_path"
  run_path="$(cd "$run_path" && pwd)"
  run_args+=("+run_path=$run_path")
  [ "$cmd" = run ] || pre+=("--sandbox_writable_path=$run_path")
fi

if [ ${#run_args[@]} -gt 0 ] || [ "$seen_dd" -eq 1 ]; then
  case "$cmd" in
    test|coverage)
      for x in "${run_args[@]}"; do pre+=("--test_arg=$x"); done
      rest=()
      for x in "${post[@]}"; do
        case "$x" in
          +*) pre+=("--test_arg=$x") ;;
          *) rest+=("$x") ;;
        esac
      done
      post=("${rest[@]}")
      [ ${#post[@]} -gt 0 ] || seen_dd=0
      ;;
    run)
      post+=("${run_args[@]}")
      seen_dd=1
      ntargets=0
      prev=""
      for x in "${pre[@]}"; do
        case "$x" in
          -*) ;;
          //*|@*|:*) ntargets=$((ntargets + 1)) ;;
          *)
            case "$prev" in
              -*=*|"") ntargets=$((ntargets + 1)) ;;
              -*) ;;
              *) ntargets=$((ntargets + 1)) ;;
            esac ;;
        esac
        prev="$x"
      done
      if [ "$ntargets" -le 1 ] && [ ${#post[@]} -gt 0 ]; then
        infer=0
        case "${post[0]}" in
          +*) infer=1 ;;
          //*|@*|:*) ;;
          *) [ -e "${post[0]}" ] && infer=1 ;;
        esac
        if [ "$infer" -eq 1 ]; then
          runners=$(grep -o 'name = "run_[A-Za-z0-9_]*"' "$REPO_ROOT/BUILD.bazel" | sed 's/name = "\(.*\)"/\1/')
          core=""
          if [ "$PWD" != "$REPO_ROOT" ]; then
            rel="${PWD#"$REPO_ROOT"/}"
            core="${rel%%/*}"
          fi
          target=""
          for r in $runners; do
            [ "$r" = "run_$core" ] && target="//:$r"
          done
          if [ -z "$target" ]; then
            echo "bazel.sh: no target given and none can be inferred from $PWD." >&2
            echo "  Run from a core directory (one of: $(echo $runners | sed 's/run_//g; s/ /, /g')) or name the runner:" >&2
            echo "  bazel.sh run --config=bzlmod //:run_openc910 [--run-path <dir>] -- <elf>|+load=<elf> [+plusarg...]" >&2
            exit 1
          fi
          echo "bazel.sh: no target given, using $target (from $PWD)" >&2
          pre+=("$target")
        fi
      fi
      ;;
    *)
      if [ ${#run_args[@]} -gt 0 ]; then
        echo "bazel.sh: --run-args only applies to 'test' or 'run' (command: '${cmd:-none}')" >&2
        exit 1
      fi ;;
  esac
fi
set -- "${pre[@]}"
if [ "$seen_dd" -eq 1 ]; then
  set -- "$@" -- "${post[@]}"
fi

exec "${BAZEL:-bazel-7}" --output_user_root="$OUTPUT_ROOT" "$@"
