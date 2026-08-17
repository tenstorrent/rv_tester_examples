#!/usr/bin/env bash
# Wrapper: runs Verilator testbench, applies stdout error-pattern check, archives on failure.
set -u
set -o pipefail

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

# Extract control flags (consumed, not forwarded):
#   +save_all_files     archive on clean pass
#   +dbg[=start:end]    enable VCD dump; optional cycle window
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

# Default opcode column to 32-bit (C910 exports 32-bit, not internal 36-bit uop).
case " ${args[*]} " in
    *" +rvfi_log_36b_uop="*) ;;
    *) args+=("+rvfi_log_36b_uop=false") ;;
esac

# Register C910's jal/jalr crack micro-op as known custom op.
case " ${args[*]} " in
    *" +rvfi_custom_uop_opcodes="*) ;;
    *) args+=("+rvfi_custom_uop_opcodes=0x0040009f:CUSTOM_MICRO_OP") ;;
esac

# C910 cracks several instructions into micro-ops that do not carry the
# architectural opcode -- jal/jalr (link + redirect), sfence.vma (fence +
# sfence.vma + custom-0 0x01b0000b), fcvt.s.w (fmv.w.x + fcvt with dyn resolved
# to a concrete rm). The ISS emits one instruction-byte record per instruction,
# so the byte-level comparison is not meaningful here. Everything else -- PC,
# privilege, register and CSR results -- is still checked. Pass +insn_check to
# re-enable.
case " ${args[*]} " in
    *" +insn_check"*|*" +noinsn_check"*) ;;
    *) args+=("+noinsn_check") ;;
esac

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
