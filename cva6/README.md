# cva6

Run the open-source [CVA6](https://github.com/openhwgroup/cva6) RISC-V core under
Tenstorrent's [`rv_tester`](https://aus-gitlab.local.tenstorrent.com/riscv/dv/rv_tester)
testbench, checking it **instruction-by-instruction against the Whisper ISS in
lockstep**. Target simulator: **Verilator**.

Both CVA6 and rv_tester are pulled in as **Bazel dependencies** — there are no git
submodules in this repo. Everything below (RTL, the ISS, the checkers, the
toolchain) is fetched by Bazel.

---

## 1. What this repo contains

Only the *glue* between CVA6 and rv_tester lives here; the two projects themselves
are dependencies.

```
MODULE.bazel                 bzlmod deps: rv_tester (git), CVA6 (github), cvm/whisper/…
.bazelrc                     toolchain + sandbox/test flags (from rv_tester)
.gitlab-ci.yml               CI: build + smoke jobs
infra/run-bazel.sh           runs bazel-7 (bzlmod) inside the cvm podman image
bazel/
  cva6_ext.bzl               module extension: fetch stock CVA6 + its submodules
  cva6.BUILD                 BUILD overlay for CVA6 (upstream ships no Bazel)
  rules_verilator_propagate_exit.patch
dv/
  verilator_opts.bzl         CVA6_VOPTS (Verilator flags + rv_tester defines)
  cva6/
    cva6_test_harness.sv     THE CONNECTION: CVA6 <-> rv_tester
    cva6_defines.sv / _undefines.sv
    cva6_rv_tester_platform.yml / _hart.yml / rv_tester_axi.yml / cva6_topology.yml
    memmap.json / whisper.json
    top.sv                   rv_tester + harness, wired by name (.*)
    gflags.cpp               plusarg definitions
    BUILD.bazel              topology_gen + rv_tester_gen codegen
    verilator/BUILD.bazel    verilog_library -> verilator_cc_library -> cc_binary
    testlists/               smoke sh_test + sim.sh + infinite.elf
```

CVA6 is built for the **`cv64a6_imafdc_sv39`** config (RV64IMAFDC, sv39 MMU,
write-through cache).

---

## 2. How the connection works

`dv/cva6/top.sv` instantiates the `rv_tester` module and the `cva6_test_harness`
side-by-side and wires them by name (`.*`) through the nets that rv_tester's
`` `RV_TESTER_VARS `` macro declares. The harness (`dv/cva6/cva6_test_harness.sv`)
is the shim between CVA6's native ports and rv_tester's port bundle:

```
                          cva6_test_harness.sv
 CVA6 `ariane` wrapper ──► rvfi_probes_o ──► [cva6_rvfi] ──► rvfi_instr ──┐
        │  noc_req/noc_resp (ariane_axi)                                  │ (bridge)
        ▼                                                                 ▼
   rv_tester axi_req[0]/axi_rsp[0]                          rv_tester rvfi[]  ──► Whisper lockstep
```

- **RVFI**: CVA6's core emits raw `rvfi_probes_o`; a `cva6_rvfi` instance expands
  them into a retired-instruction stream, which the harness remaps onto
  rv_tester's `rvfi[]` struct.
- **AXI**: CVA6's `ariane_axi` NoC master is bridged onto rv_tester's
  `axi_req[0]`/`axi_rsp[0]`.
- **Clock / reset / interrupts / termination** glue.

### Note on the retire `order` tag
CVA6's `cva6_rvfi.sv` does **not** populate the RVFI `order` field (upstream CVA6
targets Spike-tandem, where the reference model tracks retirement order). rv_tester's
memory-consistency checker needs a unique tag per retirement, so the harness
generates a monotonic `order` counter (`retire_tag_q`) — the same thing rv_tester's
own software testbench does. Without it, an infinite-loop program retiring the same
PC repeatedly would tag every retirement `0` and the checker would flag
"instruction retired multiple times".

---

## 3. Requirements

| Requirement | Detail |
|---|---|
| **Bazel 7** | The bzlmod dependency graph (boost 1.89 BCR, lockfile v13) needs Bazel ≥7. The `bazel-7` binary lives in the cvm image. The system `bazel` (6.5) will **not** work. |
| **Podman + cvm image** | `aus-gitlab.local.tenstorrent.com:5005/riscv/dv/cvm:0.1.3` (public mirror `ghcr.io/tenstorrent/cvm:0.1.3`). Provides bazel-7, clang, Python 3.9, verilator deps. |
| **Network access** | aus-gitlab (rv_tester, cvm, CoreArchChecker, mem_manager), github.com (CVA6 + its submodules, tenstorrent/whisper, pulp-platform axi/nlohmann-json), and the Bazel Central Registry (bcr.bazel.build) for boost/lz4/zlib/etc. |
| **Disk** | Bazel output root is placed on the regression area (see `infra/run-bazel.sh`); the first build fetches + compiles a lot (whisper ISS, Verilated CVA6). |
| No SSH needed | All git deps use HTTPS (the cvm image has no ssh client). |

### Dependencies pulled by Bazel (you don't clone these)
- **rv_tester** — `git_override`, HTTPS, pinned commit (see `MODULE.bazel`).
- **CVA6** — stock `openhwgroup/cva6` from GitHub via `bazel/cva6_ext.bzl`
  (pinned commit + submodules `core/cvfpu` and its nested `fpu_div_sqrt_mvp`),
  with the BUILD overlay `bazel/cva6.BUILD`.
- **whisper** (RISC-V ISS) — `git_override` to `github.com/tenstorrent/whisper`
  (pinned commit in `MODULE.bazel`).
- Via rv_tester's extension: **cvm**, **CoreArchChecker**, **mem_manager**,
  **opensrc-axi**, **opensrc-nlohmann-json**, **rules_hdl**.
- From BCR: **rules_verilator** (patched) + **verilator 5.046**, rules_verilog,
  boost.\*, lz4, zlib, fmt, googletest, gflags, rules_python.

---

## 4. Build and run

All commands go through the helper, which runs `bazel-7 --config=bzlmod` inside the
cvm podman image with the output root on the regr area:

```bash
cd rv_tester_examples/cva6

# Build the Verilator model (compile + link only)
./infra/run-bazel.sh build --config=bzlmod //dv/cva6/verilator:cva6_tb_verilator

# Run the smoke (builds the model too, then runs it in Whisper lockstep)
./infra/run-bazel.sh test  --config=bzlmod //dv/cva6/testlists:all_smoke --test_output=errors
```

Equivalent raw invocation (what CI runs):
```bash
bazel-7 --output_user_root=<root> test //dv/cva6/testlists:all_smoke --config=bzlmod \
        --build_tests_only --test_output=errors
```

### Key Bazel settings (`.bazelrc`)
- `--config=bzlmod` — required (this is a bzlmod build).
- `--sandbox_base=/tmp` — keep the exec sandbox on container-local disk; the output
  root lives on a network FS where the sandbox copy step otherwise fails.
- `test --zip_undeclared_test_outputs=false` — the cvm image has no `zip`, so test
  artifacts are left as loose files instead of `outputs.zip`.

---

## 5. Tests

All tests run `cva6_tb_verilator` under `dv/cva6/testlists/sim.sh`, which checks
each retired instruction against Whisper in lockstep and fails on any
`Error`/`Fatal` pattern in the sim output.

- **`//dv/cva6/testlists:all_smoke`** — the CI smoke suite; it passes. Contains:
  - `infinite_cva6_verilator` — loads `infinite.elf` (an infinite `j .` at the
    reset vector) and runs a few instructions (`+eot=max_instr +max_instr=8`).
  - `hello_world_cva6_verilator` — loads `hello_world.elf` and runs to completion
    via an HTIF store to `tohost` (`+eot=tohost`); console output (HTIF putchar)
    appears on stdout. **Passes** in lockstep against Whisper. The ELF is built
    `rv64ima_zicsr` (no F) so it avoids the unmapped-FP-write limitation below.

### Artifacts
`sim.sh` archives the run's files (into `$TEST_UNDECLARED_OUTPUTS_DIR` →
`bazel-testlogs/.../<test>/test.outputs/`) **only when the run fails, or when
`+save_all_files` is passed** (e.g. `--test_arg=+save_all_files`). A clean pass
leaves `test.outputs/` empty. Archived files:

```
h0_dut_rvfi.log      DUT RVFI trace          iss_cmd.log        Whisper command log
h0_bridge.log        cosim bridge log        iss_cosim.log      Whisper cosim log
trace_hart_0.dasm    disassembly trace       whisper_cosim.json
sim_stdout.log       full sim stdout
```

`test.log` (the bazel test log) always has the full stdout plus the pass/fail verdict.

> For archived files to actually materialize, Bazel must not try to zip them (the
> cvm image has no `zip`): keep `test --zip_undeclared_test_outputs=false` in
> `.bazelrc`, or install `zip` in the image.

---

## 6. CI (`../.gitlab-ci.yml`, `../.github/workflows/ci.yml`)

CI config lives at the **repo root** (a level above this example), since both
GitLab and GitHub only read their pipeline files from the root; the jobs `cd`
into `cva6/` before invoking Bazel.

The GitLab pipeline mirrors rv_tester's (cvm image, `bazel-7 --config=bzlmod`,
LSF scheduler params, `chmod +w` output cleanup). Two jobs in the `test` stage:

- **`build`** — `bazel-7 build //dv/cva6/verilator:cva6_tb_verilator` (compile/link signal).
- **`smoke`** — `bazel-7 test //dv/cva6/testlists:all_smoke` (builds + runs the lockstep test).

> The cross-project `include` (`riscv/dv/gitlab-definitions`) supplies the shared
> runner/LSF config. The repo must have access to that project for the pipeline to
> resolve it; otherwise drop the `include:` and add explicit runner `tags:`.

---

## 7. Known limitations

- **FP register writes are not mapped.** The harness ties off rv_tester's
  `frd_valid`/`frd_addr`/`frd_wdata`. CVA6's `cva6_rvfi` folds FP-destination
  results into its single `rd_wdata` with no flag marking the write as FP, so any
  program that writes an FP register (e.g. an `fmv.w.x`) trips the Core Arch
  Checker (`DUT: none` vs the ISS's F-reg value). `hello_world` sidesteps this by
  building `rv64imac` (no F), so its CRT emits no FP register init. Fixing it
  properly means decoding FP-destination opcodes in the harness (or exposing
  CVA6's `is_rd_fpr`) and routing the result to the `frd_*` fields. `FP_ENABLE`
  is on in `cva6_rv_tester_hart.yml`, so FP-writing programs still fail until this
  is done.
- **RVFI `order`/`pc_wdata` come from the testbench, not the DUT** — CVA6's RVFI
  leaves them unpopulated (built for Spike-tandem), so the harness supplies a
  monotonic `order` (see §2).

## 8. Housekeeping

- **Cleaning the output root**: Bazel outputs are created by container-root and are
  read-only (and the regr FS is root-squashed), so clean them from inside the
  container: `chmod +w -R <output_root>` then `rm -rf <output_root>`.
- **`bazel-*` symlinks** in the repo point into the output root; they are not tracked.
