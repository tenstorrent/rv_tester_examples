#!/usr/bin/env bash
# Wrapper: runs Verilator testbench, applies stdout error-pattern check, archives on failure.
set -u
set -o pipefail

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

# Extract +save_all_files flag (consumed, not forwarded).
save_all=0
args=()
for a in "$@"; do
    if [ "$a" = "+save_all_files" ]; then
        save_all=1
    else
        args+=("$a")
    fi
done

OUT="${TEST_UNDECLARED_OUTPUTS_DIR:-}"
before=$(ls -1A 2>/dev/null | sort)

"${args[@]}" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

# Match cvm "Error:", DPI "ERROR:", Verilator $fatal "Fatal/FATAL"; -n for line numbers.
matches=$(grep -nE '\bError\b|ERROR:|\bFatal\b|FATAL' "$LOG" || true)
failed=0
[ "$rc" -ne 0 ] && failed=1
[ -n "$matches" ] && failed=1

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
