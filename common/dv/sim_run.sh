#!/usr/bin/env bash
# `bazel run` companion (see rv_tester_sim_run in sim_test.bzl). Declared
# args: <sim.sh> <tb> <memmap.json> <whisper.json> [+plusarg...]; bazel run
# appends the user's ELF path and extra +plusargs. Resolves paths, moves to
# the invocation directory, and delegates to sim.sh (error check, +dbg, ...).
set -uo pipefail

sim_sh="$PWD/$1"; tb="$PWD/$2"; memmap="$PWD/$3"; whisper="$PWD/$4"; shift 4

elf=""
args=()
for a in "$@"; do
  case "$a" in
    +*) args+=("$a") ;;
    *)
      if [ -n "$elf" ]; then
        echo "sim_run.sh: more than one ELF given: $elf, $a" >&2
        exit 2
      fi
      elf="$a"
      ;;
  esac
done
if [ -z "$elf" ]; then
  echo "usage: bazel run <target> -- <elf> [+plusarg...]" >&2
  exit 2
fi

cd "${BUILD_WORKING_DIRECTORY:-$PWD}"
if [ ! -f "$elf" ]; then
  echo "sim_run.sh: ELF not found: $elf" >&2
  exit 2
fi

exec "$sim_sh" "$tb" "+load=$elf" \
    "+memmap_json_path=$memmap" "+whisper_json_path=$whisper" "${args[@]}"
