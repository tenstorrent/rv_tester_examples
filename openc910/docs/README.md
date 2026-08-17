# OpenC910

Run open-source [OpenC910](https://github.com/XUANTIE-RV/openc910) (XuanTie C910) RISC-V core under `rv_tester` on Verilator, **lockstep instruction-by-instruction against Whisper ISS**. Both core and `rv_tester` are Bazel dependencies; RVFI additions applied to the upstream RTL by `rtl/apply_rvfi.py` at fetch time.

## What This Contains

Integration glue; C910 and `rv_tester` are fetched by Bazel.

```
bazel/
  openc910_ext.bzl           fetch C910, overlay RVFI srcs, run apply_rvfi.py
  openc910.BUILD             BUILD overlay (upstream has no Bazel)
rtl/
  apply_rvfi.py              RVFI plumbing edits to upstream RTL (`ifdef RVFI)
  rvfi/ct_rvfi_gen.v         RVFI reconstruction (iid-keyed retire record)
dv/openc910/
  openc910_test_harness.sv   C910 ↔ rv_tester shim
  *.yml                      topology/hart/platform/AXI config
  top.sv                     rv_tester + harness, wired by name (.*)
  verilator/                 Verilator build
  testlists/                 smoke tests + sim.sh
MODULE.bazel                 dependencies (rv_tester, OpenC910, whisper, …)
.bazelrc                      → ../common/bazelrc/common.bazelrc
```

C910 config: **single-hart RV64GC**. (C910 module is dual-core; core1 held in reset; only core0 checked.)

## Connection

`top.sv` instantiates `rv_tester` and `openc910_test_harness` side-by-side, wired by name (`.*`):

```
                     openc910_test_harness.sv
 OpenC910 core0 ────► core0_rvfi_* export ──► rv_tester rvfi[] ──┐
        │  biu plain-AXI4 (40-bit addr, 128-bit data)           │
        ▼                                                       ▼
   rv_tester axi_req[0]/axi_rsp[0]            Whisper lockstep check
```

- **RVFI**: C910 exposes retire-valid + retire-PC only; `ct_rvfi_gen.v` + `apply_rvfi.py` edits reconstruct full per-instruction record (iid-keyed table: dispatch captures metadata, writeback fills result, retire reads out). Flattened `core0_rvfi_*` bus packed into `rvfi[]`.
- **AXI**: `biu` master (40-bit addr, 128-bit data, 8-bit id) → `axi_req[0]`/`axi_rsp[0]`.
- **Order tag**: Harness generates monotonic counter (C910 exports no retire order).

## RVFI Stages

C910 is 3-wide OoO with register renaming; RVFI reconstructed in `ct_rvfi_gen.v` (instantiated in `ct_core`, patched in via `ifdef RVFI`, non-RVFI builds byte-identical to upstream):

- **Stage A**: `valid`, `pc_rdata`, `pc_wdata`, `iid`, `mode`, `trap`, `cause`, `intr` from retirement signals + ROB retire exports.
- **Stage B**: `rd_addr`, `rd_we`, `rd_wdata` from dispatch (captures by ROB iid) and writeback (IU/LSU
  pipes). The result is snapshotted into the retire record when it writes back, not read from the
  register file at drain: a preg can be freed, reallocated and rewritten while a record waits behind
  an older non-blocking load. Instruction word checked in lockstep.
- **Stage C**: NOT WIRED. `rvfi_mem_*` are tied to 0 in `ct_rvfi_gen.v`; the LSU taps exist in
  `apply_rvfi.py` but are not consumed. Cosim therefore cannot check load/store addresses or data.
- **Stage D**: FP `frd_*` from the fregfile write ports -- `lsu_idu_wb_pipe3_wb_vreg_fr_*` (FP loads)
  and `vfpu_idu_ex5_pipe6/7_wb_vreg_fr_*` (FP arithmetic). The FP architectural destination comes
  from `dstv_reg`; `dst_reg` is the integer dest and reads 0 for an FP op.

## Build & Run

```bash
cd rv_tester_examples/openc910

# Build Verilator model
./infra/run-bazel.sh build --config=bzlmod //dv/openc910/verilator:openc910_tb_verilator

# Run smoke
./infra/run-bazel.sh test  --config=bzlmod //dv/openc910/testlists:all_smoke --test_output=errors
```

Requirements: Bazel 7, cvm podman image, network access. See cva6 README for dependency list.

## Tests

**`//dv/openc910/testlists:all_smoke`**:
- `infinite_openc910_verilator`: infinite loop, 8 instructions (`+max_instr=8`).
- `hello_world_openc910_verilator`: runs to HTIF `tohost` completion (~1.3M retirements in lockstep). **Passes** with RVFI Stages A–D wired and `insn_check` enabled; store `mem_wdata` approximate only.

## Status & Known Limitations

- **Smoke tests PASS** in Whisper lockstep. Stages A, B and D wired; `insn_check` enabled.
  Stage C (memory) is not wired, so load/store addresses and data are unchecked.
- **Cold-boot edits** (both in `rtl/apply_rvfi.py`):
  - `mmu/rtl/sysmap.h`: remap PMA so `0x8000_0000` is cacheable-executable (fetch lookup on `PA[39:12]`; `BASE0=0x02000` boot, `BASE1=0x80000` MMIO, `BASE2=0x100000` DRAM+).
  - `cp0/rtl/ct_cp0_regs.v`: reset `mhcr.IE/DE` to 1 (I/D cache enabled at reset); C910 cannot fetch cacheable memory with icache off.
- **Interrupts** (PLIC/CLINT): tied off for smoke bring-up. C910 has internal CLINT fed by harness `sys_cnt`.
- **Runtime**: Verilated C910 slow (~40 min for `hello_world`); smoke tests default to `timeout = "eternal"`. Waveform dump opt-in via `+dbg` (or `+dbg=<on>:<off>` for window); full-run VCD is multi-GB.

## Other C910 Behaviours Handled

- **Compressed instructions**: `rvfi.comp` is driven from `insn[1:0] != 2'b11`. rv_tester suppresses the
  ISS-side instruction-byte record for compressed ops but emits the DUT side unless `comp` is set, so
  leaving it at 0 reports every C instruction as `DUT: <insn> ISS: none`.
- **Privilege mode**: sampled at dispatch, not at retire. `cp0_yy_priv_mode` is live, so an `mret` observed
  retiring already reads its post-state; RVFI wants the mode the instruction executed in. `mret`/`sret`/traps
  are serializing on C910, so the dispatch-time mode is the execution mode.
- **Sub-word AXI writes**: the harness zeroes byte lanes that `strb` does not enable. AXI leaves them
  don't-care and `sysmod_mem` honours `strb`, but rv_tester's htif model (`src/sysmod/htif/htif.cpp`)
  deserializes the whole 64-bit dword without consulting `strb`. C910 issues sub-word stores to `tohost`,
  so the stale bytes it drives in the unwritten lanes were decoded as the HTIF command/payload -- turning a
  passing test into a reported failure.
- **Cracked `sfence.vma`**: C910 splits it into `fence` + `sfence.vma` + a custom-0 word (`0x01b0000b`),
  all at the same PC. See the micro-op note below; the tail word is registered the same way.

## Cracked `jal`/`jalr` Micro-ops

C910 cracks `jal`/`jalr` into two ROB entries at the same PC (two consecutive records in `h0_dut_rvfi.log`):

```
#69 ... 0x80001750 0040009f r ...1 ...80001754 CUSTOM_MICRO_OP  (link, last_uop=0)
#69 ... 0x80001750 efdff0ef r ...0 ...0        jal x1, .-0x104  (redirect, last_uop=1)
```

- **Link micro-op** (`0x0040009f`): computes `ra = pc + 4`. Word is C910-internal encoding (not decodable RISC-V; `inst[6:0]=0x1f` is reserved column, `inst[11:7]=x1`); not a bug.
- **Redirect micro-op**: carries real jump word, performs control transfer.

rv_tester coalesces on `last_uop`: link supplies `ra` write, redirect supplies opcode/jump. Registered as known custom op via `sim.sh` `+rvfi_custom_uop_opcodes=0x0040009f:CUSTOM_MICRO_OP`; skips `insn` byte-check for coalesced op; all other instructions checked normally.
