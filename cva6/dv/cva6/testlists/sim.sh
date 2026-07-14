#!/usr/bin/env bash
# Wrapper that runs a Verilator-based sw testbench binary and applies the
# stdout error-pattern check that bzsim's runtime/simtest.py (SimTest.sim(),
# lines 488-511) used to apply.
#
# Run artifacts (h0_dut_rvfi.log, whisper traces, disasm, ...) are archived
# into the bazel test.outputs/ dir ONLY when the run fails, or when the caller
# passes +save_all_files (e.g. `bazel test --test_arg=+save_all_files`). On a
# clean pass with no flag, test.outputs/ is left empty.
#
# First arg is the sim binary; rest are plusargs forwarded to it.
set -u
set -o pipefail

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

# Pull out the +save_all_files control flag; it's consumed here and NOT
# forwarded to the sim (which would reject an unknown plusarg).
save_all=0
args=()
for a in "$@"; do
    if [ "$a" = "+save_all_files" ]; then
        save_all=1
    else
        args+=("$a")
    fi
done

# rv_tester writes per-run logs relative to CWD; snapshot it so we can pick up
# whatever the sim produced if we end up archiving.
OUT="${TEST_UNDECLARED_OUTPUTS_DIR:-}"
before=$(ls -1A 2>/dev/null | sort)

# Tee through to stdout (bazel captures it) AND to a file we rescan after exit.
"${args[@]}" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

# cvm::log(cvm::ERROR, ...) prints "Error: ..."; DPI direct prints use
# "ERROR:"; Verilator $fatal prints "Fatal" / "FATAL". `grep -n` so failures
# include the line number in the captured log.
matches=$(grep -nE '\bError\b|ERROR:|\bFatal\b|FATAL' "$LOG" || true)
failed=0
[ "$rc" -ne 0 ] && failed=1
[ -n "$matches" ] && failed=1

# Archive on failure or on explicit request.
if [ -n "$OUT" ] && { [ "$failed" -eq 1 ] || [ "$save_all" -eq 1 ]; }; then
    after=$(ls -1A 2>/dev/null | sort)
    comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | while IFS= read -r f; do
        [ -n "$f" ] && cp -r -- "$f" "$OUT/" 2>/dev/null || true
    done
    cp -- "$LOG" "$OUT/sim_stdout.log" 2>/dev/null || true
fi

if [ "$rc" -ne 0 ]; then
    echo "sim.sh: simulator exited with code $rc" >&2
    exit "$rc"
fi

if [ -n "$matches" ]; then
    echo "sim.sh: detected error pattern(s) in simulator output:" >&2
    echo "$matches" >&2
    exit 1
fi
