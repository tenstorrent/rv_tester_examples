# OpenC910 debug/pad ports vs RVFI taps — feasibility analysis

## Question
The C910 top level (`openC910`) exposes a set of unconnected `*_pad_*` / debug
ports in the harness (`openc910/dv/openc910/openc910_test_harness.sv`):

```
.core0_pad_jdb_pm    () .core0_pad_lpmd_b   () .core0_pad_mstatus  ()
.core0_pad_retire0   () .core0_pad_retire0_pc () .core0_pad_retire1 () .core0_pad_retire1_pc ()
.core0_pad_retire2   () .core0_pad_retire2_pc ()
.core1_pad_*         ()  (second core, unused here)
.cpu_debug_port      () .cpu_pad_l2cache_flush_done () .cpu_pad_no_op ()
.had_pad_jtg_tdo     () .had_pad_jtg_tdo_en ()
```

Suggestion from a colleague: maybe these are debug ports we can use **instead of
tapping deep RTL** for the RVFI signals, i.e. build a bridge
`debug ports -> rvfi_*` rather than adding `` `ifdef RVFI `` taps via
`bazel/apply_rvfi.py`.

## Short answer
**Partially possible, but not a replacement.** The pad/debug interface exposes only
~3 of the ~12 fields RVFI needs (retire valid, packet base PC, and mstatus/mode).
Everything else that makes the reconstruction work — physical-register writeback
data, ROB packet count, per-sub instruction length, rd address/we, ROB_SPLIT, mem,
trap/cause, instruction word — is **not** brought to the pad boundary and still
requires the internal taps. So a bridge can, at most, be a cosmetic refactor of
three signals; it cannot remove the need for RTL tapping.

## What the pad ports actually are (from C910 RTL)
These are internal signals promoted to the `openC910` top level. Port widths
(`C910_RTL_FACTORY/gen_rtl/cpu/rtl/openC910.v`):

| Top-level port            | Width  | Internal source            | Meaning                        |
|---------------------------|--------|----------------------------|--------------------------------|
| `core0_pad_retire0/1/2`   | 1 each | `rtu_pad_retire0/1/2`       | retire **valid** per lane      |
| `core0_pad_retire0/1/2_pc`| 40     | `rtu_pad_retire0/1/2_pc`    | packet **base PC** per lane    |
| `core0_pad_mstatus`       | 64     | `cp0_pad_mstatus`           | mstatus (→ privilege **mode**) |
| `core0_pad_jdb_pm`        | 2      | debug power-mode            | not architectural              |
| `core0_pad_lpmd_b`        | 2      | low-power mode              | not architectural              |
| `cpu_debug_port`          | 1      | debug status                | not architectural              |
| `cpu_pad_l2cache_flush_done` | 1   | L2 flush status            | not architectural              |
| `cpu_pad_no_op`           | 1      | status                     | not architectural              |
| `had_pad_jtg_tdo(_en)`    | 1      | JTAG TDO                   | not architectural              |

Propagation chain (confirmed in RTL):
`ct_rtu_top.rtu_pad_retire*(_pc)` -> `ct_core` -> `ct_top` -> `openC910.core0_pad_retire*(_pc)`
and `cp0 ... cp0_pad_mstatus` -> ... -> `openC910.core0_pad_mstatus`.

### Key fact
`core0_pad_retire*` and `core0_pad_retire*_pc` are the **exact same nets** the RVFI
generator already taps today for `retire_vld` and `retire_base_pc` (via
`rtu_pad_retire0/1/2` and `rtu_pad_retire0/1/2_pc` in `apply_rvfi.py`). They are not
a new/richer information source — they are those two signals exposed one level up.

## What RVFI needs, and where each field can come from
The generator (`rvfi/rtl/ct_rvfi_gen.v`) needs the following per retired
instruction. "Pad?" = available on the top-level debug ports.

| RVFI field           | Source used today (internal tap)                         | Pad? |
|----------------------|-----------------------------------------------------------|------|
| retire valid         | `rtu_pad_retire0/1/2`                                      | YES (`core0_pad_retire*`) |
| pc_rdata (base PC)   | `rtu_pad_retire0/1/2_pc`                                   | YES (`core0_pad_retire*_pc`) |
| mode / ixl           | (mode) mstatus                                            | YES (`core0_pad_mstatus`) |
| retire **iid**       | `rtu_yy_xx_commit0/1/2_iid`                                | NO |
| packet **num** (1–3) | `idu_rtu_rob_create*_data[18:17]` (dispatch)              | NO |
| per-sub **length**   | `is_dis_inst*_pc_offset` (IDU)                            | NO |
| rd_addr / rd_we / rd_fpr | `idu_rtu_pst_dis_inst*_dst_reg/preg_vld/freg_vld`    | NO |
| rd_wdata             | `iu_idu_ex2_pipe0/1_wb_*`, `lsu_idu_wb_pipe3_wb_*`        | NO |
| **ROB_SPLIT** (last_uop) | `rob_retire_inst0/1/2_split` (exported as `rvfi_split*`) | NO |
| mem addr/mask/data   | LSU DA taps (`ld_da_*`, `st_da_*`, `sd_ex1_*`)           | NO |
| trap / cause / intr  | `rob_retire_inst0_expt_*` / `_int_*`                     | NO (mstatus gives mode only) |
| insn (opcode)        | `ir_inst0..3_opcode` (IDU, 1-cycle aligned)              | NO |

Only the first three rows are on the pad interface. The remaining nine — including
everything that carries **result values** and **packet structure** — are not.

## Why the missing fields matter (can't be derived from pad ports)
- **iid**: the ROB is packet-based (1 entry = up to 3 instructions). Without the
  retire iid you cannot index the per-packet metadata (num, lengths, dst pregs,
  insns) captured at dispatch. Base PC alone can't be unpacked into per-instruction
  records.
- **num + per-sub length**: needed to expand a packet's base PC into each
  instruction's PC (`pc = base + Σ 2*len`). Not observable from a single base PC.
- **rd_wdata**: RVFI must report the architectural register result; the pad
  interface has no register-writeback data at all. This is the bulk of the value.
- **ROB_SPLIT**: C910 cracks jal/jalr (and others) into 2 ROB entries; without the
  split flag the cosim can't coalesce them (`last_uop`).
- **load latency**: missed loads retire before their writeback lands; the retire
  FIFO's readiness gate keys on the writeback (`t_preg_ready`) — again, writeback
  data that the pad interface does not expose.
- **mem / trap / cause**: no memory-access or exception detail on the pads.

Conclusion: the pad interface is a lightweight *trace* interface (retire PC stream
+ mstatus), suitable for coarse PC tracing, not for full architectural lockstep.

## Is a bridge possible? (what you could actually do)
1. **Cosmetic 3-signal refactor (possible, low value).** Connect
   `core0_pad_retire0/1/2`, `core0_pad_retire0/1/2_pc`, and `core0_pad_mstatus`
   in the harness and feed them to the generator's `retire_vld`, `retire_base_pc`,
   and mode inputs — replacing the internal `rtu_pad_*` / `cp0_pad_mstatus` taps.
   Values are identical; the only benefit is using already-exposed top-level ports
   for those three fields instead of `` `ifdef RVFI `` promotions. It does **not**
   reduce the other taps.
2. **Full replacement (not possible).** rd_wdata, iid, num, lengths, split, mem,
   trap, and insn cannot be sourced from the pad interface, so the deep taps added
   by `apply_rvfi.py` remain mandatory.

### Sketch of the optional bridge (harness side)
```systemverilog
// openc910_test_harness.sv — feed top-level debug ports into the RVFI generator
// inputs instead of the internal rtu_pad_*/cp0_pad_mstatus taps (identical values).
.core0_pad_retire0     (rvfi_retire_vld[0]),
.core0_pad_retire0_pc  (rvfi_retire_pc0),
.core0_pad_retire1     (rvfi_retire_vld[1]),
.core0_pad_retire1_pc  (rvfi_retire_pc1),
.core0_pad_retire2     (rvfi_retire_vld[2]),
.core0_pad_retire2_pc  (rvfi_retire_pc2),
.core0_pad_mstatus     (rvfi_mstatus),   // mode = mstatus MPP/derive
// ... all other rvfi_* still come from apply_rvfi.py internal taps ...
```
Note: this is only worthwhile if the goal is to minimize `` `ifdef RVFI `` edits to
`ct_rtu_top`/`cp0` for those three signals. Functionally it is a no-op — the current
tap-based path already passes hello_world in full lockstep.

## Recommendation
Keep the current tap-based generator (it passes hello_world, 370 instructions in
Whisper lockstep, zero arch mismatches). The pad/debug ports are the same
valid+PC signals plus mstatus and cannot supply result/packet/mem/trap/insn data,
so they are a minor tidy-up at best, not a way to avoid RTL tapping. If desired, the
3-signal bridge above can be prototyped as a follow-up, but it changes nothing
functionally and still needs all the deeper taps.

## References
- `openc910/rvfi/rtl/ct_rvfi_gen.v` — the RVFI generator (tables, retire FIFO).
- `openc910/bazel/apply_rvfi.py` — all `` `ifdef RVFI `` taps + generator instance.
- `openc910/HANDOFF.md` — overall project state and bug history.
- C910 RTL: `C910_RTL_FACTORY/gen_rtl/cpu/rtl/{openC910,ct_top,ct_core}.v`,
  `.../rtu/rtl/ct_rtu_top.v`, `.../idu/rtl/ct_idu_*`, `.../lsu/rtl/ct_lsu_*`.
