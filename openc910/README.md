# openc910

Run the open-source [OpenC910](https://github.com/XUANTIE-RV/openc910) (XuanTie
C910) RISC-V core under Tenstorrent's `rv_tester` testbench, checking it
**instruction-by-instruction against the Whisper ISS in lockstep**. Target
simulator: **Verilator**.

This example mirrors the sibling `cva6/` example. Both C910 and rv_tester are
pulled in as **Bazel dependencies** — there are no git submodules and nothing is
vendored. The stock C910 RTL is fetched from GitHub and the RVFI additions are
applied **on top** as a patch at fetch time.

---

## 1. What this repo contains

Only the *glue* between C910 and rv_tester lives here; the core itself and
rv_tester are dependencies fetched by Bazel.

```
MODULE.bazel                 bzlmod deps: rv_tester (git), openc910 (github), cvm/whisper/…
.bazelrc                     toolchain + sandbox/test flags (copied from cva6)
infra/run-bazel.sh           runs bazel-7 (bzlmod) inside the cvm podman image
bazel/
  openc910_ext.bzl           module extension: fetch stock openc910, overlay RVFI srcs, apply RVFI patch
  openc910.BUILD             BUILD overlay for C910 (upstream ships no Bazel); srcs from the upstream filelist
  openc910_rvfi.patch        RVFI export plumbing added on top of the fetched RTL (`ifdef RVFI)
  rules_verilator_propagate_exit.patch / rv_tester_public_deps.patch
rvfi/rtl/
  ct_rvfi_gen.v              RVFI generation block (iid-keyed retire record reconstruction)
dv/
  verilator_opts.bzl         OPENC910_VOPTS (Verilator flags + rv_tester/RVFI defines + C910 lint waivers)
  openc910/
    openc910_test_harness.sv THE CONNECTION: C910 <-> rv_tester
    top.sv                   rv_tester + harness, wired by name (.*)
    openc910_defines.sv / _undefines.sv
    openc910_rv_tester_platform.yml / _hart.yml / rv_tester_axi.yml / openc910_topology.yml
    memmap.json / whisper.json / gflags.cpp
    BUILD.bazel              topology_gen + rv_tester_gen codegen
    verilator/BUILD.bazel    verilog_library -> verilator_cc_library -> cc_binary
    testlists/               smoke sh_test + sim.sh + ELFs
```

C910 is built **single-hart, RV64GC**: the `openC910` module is the dual-core MP
top, so core1 is held in reset and only core0 is checked in lockstep.

---

## 2. How the connection works

`dv/openc910/top.sv` instantiates `rv_tester` and `openc910_test_harness`
side-by-side and wires them by name (`.*`). The harness
(`dv/openc910/openc910_test_harness.sv`) is the shim between C910's native flat
ports and rv_tester's port bundle:

```
                     openc910_test_harness.sv
 openC910 (core0) ──► core0_rvfi_* export ──► rv_tester rvfi[]  ──► Whisper lockstep
        │  biu_pad_* / pad_biu_* (plain AXI4)                 │
        ▼                                                     ▼
   rv_tester axi_req[0]/axi_rsp[0]
```

- **RVFI**: C910 only exposes retire-valid + retire-PC at its top. The RVFI
  additions (`rvfi/rtl/ct_rvfi_gen.v` + `bazel/openc910_rvfi.patch`) reconstruct
  the full per-retired-instruction record: metadata is captured into an
  `iid`-keyed table at dispatch, filled with the result at register writeback and
  the memory access at LSU commit, and read out in program order at retire. The
  block emits a flattened `core0_rvfi_*` bus that the harness packs into
  rv_tester's `rvfi[]` struct.
- **AXI**: C910's `biu` plain-AXI4 master (40-bit addr, 128-bit data, 8-bit id)
  is bridged onto rv_tester's `axi_req[0]`/`axi_rsp[0]`.
- **Clock / reset / boot vector / termination** glue. The retire `order` tag is
  generated in the harness (C910 exports no architectural retire order), same as
  the cva6 harness.

---

## 3. The RVFI addition (staged)

C910 is a 3-wide, out-of-order, register-renamed core; RVFI cannot be tapped
from one pipeline stage. `ct_rvfi_gen.v` implements the reconstruction; the patch
plumbs a flattened RVFI export up the hierarchy
(`ct_core` → `ct_top` → `openC910`) under `` `ifdef RVFI `` and instantiates the
block in `ct_core`, so a normal (non-RVFI) build is byte-identical to upstream.

Bring-up is staged (each stage validated by the same `sim.sh` + Whisper lockstep
gate the cva6 tests use):

- **Stage A (wired)** — `valid` / `pc_rdata` / `pc_wdata` / `iid` / `mode` /
  `trap` / `cause` / `intr`, from signals available at `ct_core`
  (`rtu_pad_retireN(_pc)`, `rtu_yy_xx_commitN_iid`, `cp0_yy_priv_mode`) plus the
  ROB retire export added by the patch: `rob_retire_instN_next_pc` (→ `pc_wdata`,
  word-address `<<1`) and, for slot 0 (the only slot that can trap before a
  flush), `rob_retire_inst0_{expt_vld,expt_vec,int_vld,int_vec}` combined into
  RVFI `trap`/`intr`/`cause` (mcause interrupt bit set for interrupts). These are
  forwarded `ct_rtu_rob`→`ct_rtu_top`→`ct_core`.
- **Stage B (wired)** — `rd_addr` / `rd_we` / `rd_wdata`:
  - *dispatch tap*: every dispatched instruction is captured by its universal
    ROB id. `preg_iid` is masked by `preg_vld` in the IDU, so it cannot serve as
    the per-instruction key; instead the patch exports the ROB's own
    `rob_createN_iid` (added as `rvfi_rob_createN_iid` outputs through
    `ct_rtu_rob` → `ct_rtu_top` → `ct_core`) and uses `idu_rtu_rob_createN_dp_en`
    as the dispatch pulse. This resets each entry on (re)dispatch, eliminating the
    iid-reuse hazard. `rd_we`/`rd_addr` come from
    `idu_rtu_pst_dis_instN_{preg_vld,dst_reg}`.
  - *writeback tap*: GPR results are captured by iid from IU pipe0/pipe1
    (`iu_rtu_ex2_pipeK_wb_preg_vld` + `iu_rtu_pipeK_iid` + `iu_idu_ex2_pipeK_wb_preg_data`)
    and LSU pipe3 (load results). Mul/div fold onto the IU pipe0/1 writeback ports;
    the IU pipe2 slot is branch/complete only (no GPR data).
- **Stage B — `insn`** (remaining): the 32-bit instruction word is still tied off
  (`disp_insn`), since the ROB stores only the PC, not the encoding. Whisper
  refetches the encoding from memory, so `rd`/`pc` lockstep does not need it;
  populating `disp_insn` requires threading the decoded insn from the IDU by iid.
- **Stage C (wired)** — `mem_addr` / `mem_rmask` / `mem_wmask` / `mem_rdata`:
  the load/store data-access taps are exported from `ct_lsu_top`
  (`ld_da_{addr,bytes_vld,data_ori,iid,inst_vld}` for loads,
  `st_da_{addr,sf_bytes_vld,iid,inst_vld}` for stores) and fed to the block's
  `ls_*` ports (port0 = load, port1 = store). The 16-bit C910 line byte-valid is
  narrowed to the 8-byte RVFI mask via `addr[3]` (correct for naturally-aligned
  accesses ≤ 8 bytes).
- **Stage C — store `mem_wdata` (wired)**: captured from `sd_ex1_data`
  (store-data ex1 stage, exported from `ct_lsu_top`) via a dedicated `sd_*` port
  on `ct_rvfi_gen`, keyed by the pipe4 store iid delayed one cycle
  (`idu_lsu_rf_pipe4_iid` registered to align with the ex1 store data). Because
  the table is iid-keyed, this fills `mem_wdata[iid]` independently of the
  address/mask write from `st_da`. **Assumption:** no stall between the store's
  `rf` and `ex1` stages (otherwise the delayed-iid pairing skews); this tap
  should be confirmed in simulation.
- **Stage D (wired)** — FP `frd_*`:
  - *dispatch*: `disp_rd_fpr` = `idu_rtu_pst_dis_instN_freg_vld`; `disp_rd_we`
    now also asserts for FP writers (`preg_vld | freg_vld`); `disp_rd_areg`
    selects the GPR `dst_reg` or the FP `ereg` areg.
  - *writeback*: FP results captured by iid from VFPU pipe6/pipe7
    (`vfpu_rtu_ex5_pipeK_wb_vreg_fr_vld` + `vfpu_rtu_pipeK_iid` +
    `vfpu_idu_ex5_pipeK_wb_vreg_fr_data`), so `NWB=5`.
  - The harness routes `rd_fpr` retirements to rv_tester's `frd_*` fields.
  - Note: the smoke ELFs are built no-F, so FP is not exercised by the smoke
    suite; Stage D matters for FP-writing programs.

---

## 4. Build and run

All commands go through the helper, which runs `bazel-7 --config=bzlmod` inside
the cvm podman image:

```bash
cd rv_tester_examples/openc910

# Build the Verilator model (compile + link only)
./infra/run-bazel.sh build --config=bzlmod //dv/openc910/verilator:openc910_tb_verilator

# Run the smoke (builds the model too, then runs it in Whisper lockstep)
./infra/run-bazel.sh test  --config=bzlmod //dv/openc910/testlists:all_smoke --test_output=errors
```

Requirements are identical to the cva6 example (Bazel 7, the cvm podman image,
network access to github.com + the Bazel Central Registry). See `cva6/README.md`
§3 for the full dependency list.

---

## 5. Tests

- **`//dv/openc910/testlists:all_smoke`** — `infinite_openc910_verilator`
  (infinite loop at the reset vector, `+eot=max_instr +max_instr=8`) and
  `hello_world_openc910_verilator` (runs to completion via an HTIF store to
  `tohost`). Both ELFs are the generic rv64 images from the cva6 example, linked
  at reset vector `0x80000000`; the harness drives `pad_core0_rvba` to match.

---

## 6. Status / known limitations

- **Both smoke tests PASS** in Whisper lockstep (`//dv/openc910/testlists:all_smoke`):
  `infinite` and `hello_world` (the latter runs the full program to the HTIF
  `tohost` store — "Hello world!" on stdout, ~1.3M retirements checked in
  lockstep). RVFI Stages A–D are wired (see §3); only store `mem_wdata` and the
  `insn` word remain approximate/tied off, which the current smokes don't require.
- **Cold-boot bring-up (required to fetch the reset vector):** two C910-specific
  edits in `openc910_rvfi.patch`, both found via waveform debug:
  - `mmu/rtl/sysmap.h` PMA remap so `0x8000_0000` is normal cacheable-executable
    memory. The sysmap compares `PA[39:12]` (4 KB units): a `0x8000_0000` fetch
    looks up `0x80000`, so the region bases are `BASE0=0x02000` (boot, exec),
    `BASE1=0x80000` (MMIO `0x0200_0000`–`0x8000_0000`, device),
    `BASE2=0x100000` (DRAM `0x8000_0000`+, exec).
  - `cp0/rtl/ct_cp0_regs.v`: `mhcr.IE/DE` reset to 1 (I/D cache enabled at reset),
    since C910 cannot fetch cacheable memory with the icache off and there is no
    cold-executable uncached region.
- **Interrupts** (PLIC/CLINT external lines) are tied off for smoke bring-up;
  C910 has an internal CLINT fed by the harness `sys_cnt` counter.
- **Runtime**: the Verilated C910 cosim is slow — `hello_world` takes ~40 min, so
  the smoke tests default to `timeout = "eternal"`. Waveform dumping is opt-in via
  `+dbg` (see `sim.sh`); a whole-run VCD is multi-GB, so prefer `+dbg=<on>:<off>`
  over a narrow cycle window.
