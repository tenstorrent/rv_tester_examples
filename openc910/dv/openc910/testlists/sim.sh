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

# Pull out control flags consumed here and NOT forwarded to the sim (it would
# reject unknown plusargs):
#   +save_all_files  archive run artifacts even on a clean pass.
#   +dbg[=on:off]    enable the VCD waveform dump (dump.vcd). The model is built
#                    trace-capable (trace_mode="vcd"); dumping itself is gated at
#                    runtime by +vcd_cycle_on=, so we only pass it when +dbg is
#                    given. Optional on:off cycle window, e.g. +dbg=2000:2300
#                    (default: dump the whole run from cycle 0).
save_all=0
args=()
for a in "$@"; do
    case "$a" in
        +save_all_files)
            save_all=1
            ;;
        +dbg)
            args+=("+vcd_cycle_on=0")
            save_all=1
            ;;
        +dbg=*)
            win="${a#+dbg=}"
            args+=("+vcd_cycle_on=${win%%:*}")
            [ "$win" != "${win#*:}" ] && args+=("+vcd_cycle_off=${win#*:}")
            save_all=1
            ;;
        *)
            args+=("$a")
            ;;
    esac
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
