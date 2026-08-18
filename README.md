# rv_tester Examples

Bazel-based integration examples: connect Tenstorrent's `rv_tester` testbench to open-source RISC-V cores for **lockstep instruction-by-instruction verification against Whisper ISS**.

Each example is a self-contained Bazel workspace; the core and `rv_tester` are dependencies. Only the integration glue (harness, Bazel wiring, config) lives here.

## Examples

| Example | Core | Details |
|---|---|---|
| [`cva6/`](cva6/) | [CVA6](https://github.com/openhwgroup/cva6) `cv64a6_imafdc_sv39` | See [`cva6/docs/README.md`](cva6/docs/README.md) |
| [`openc910/`](openc910/) | [OpenC910](https://github.com/XUANTIE-RV/openc910) RV64GC | See [`openc910/docs/README.md`](openc910/docs/README.md) |

## Repository Layout

Everything not specific to one core lives in [`common/`](common/) (`rv_tester_common`) and is shared by label or symlink, so each example carries only its own glue:

```
common/
├── bazel/deps.MODULE.bazel   # non-design deps, include()d by each example
├── bazel/*.patch             # dependency patches
├── bazelrc/common.bazelrc    # Bazel flags
├── dv/sim.sh                 # test runner: error scan, artifact archiving, +dbg
├── dv/gflags.cpp             # DPI plusarg definitions
├── dv/verilator_opts.bzl     # COMMON_VOPTS / SW_TESTBENCH_VOPTS
├── dv/{memmap,whisper}.json  # memory map + Whisper config
├── infra/bazel.sh            # bazel invocation (no container)
├── infra/in-container.sh     # podman wrapper (no bazel)
├── infra/run-bazel.sh        # the two composed, for local dev
└── testbins/                 # prebuilt test ELFs
```

Each example skeleton:
```
<example>/
├── MODULE.bazel              # include() shared deps + the core fetch extension
├── .bazelrc                  # → ../common/bazelrc/common.bazelrc
├── bazel/                    # fetch extension + BUILD overlay
│   ├── deps.MODULE.bazel     # → ../../common/bazel/deps.MODULE.bazel
│   └── *.patch               # → ../../common/bazel/*.patch
├── rtl/                      # RTL modifications
├── dv/
│   ├── verilator_opts.bzl    # core waivers on top of SW_TESTBENCH_VOPTS
│   └── <core>/
│       ├── BUILD.bazel       # codegen targets
│       ├── harness/          # top.sv, test_harness.sv, defines
│       ├── config/           # *.yml (topology, hart, platform, AXI)
│       ├── verilator/        # Verilator build
│       └── testlists/        # smoke tests (run under common's sim.sh)
├── infra/run-bazel.sh        # → ../../common/infra/run-bazel.sh
└── docs/                     # README
```

## Running Bazel

`common/infra/` splits the two concerns that used to sit in one per-example script:

| Script | Does | Use when |
|---|---|---|
| `bazel.sh` | Resolves the example workspace containing `$PWD`, manages the output root, execs `bazel-7` | You already have `bazel-7` — notably CI, which runs in the cvm image |
| `in-container.sh` | Runs any command in the cvm image; knows nothing about Bazel | You need the image for something other than Bazel |
| `run-bazel.sh` | `bazel.sh` under `in-container.sh` | Local dev (symlinked as `<example>/infra/run-bazel.sh`) |

Output root defaults to `build/<example>_bazel_root` at the repo root; override with `BAZEL_OUTPUT_ROOT` or `--run-path <dir>`. `CVM_IMAGE` overrides the image, `CVM_MOUNTS` adds bind mounts.

## Adding a New Example

1. Copy an existing example as `newcore/`.
2. Write `bazel/newcore_ext.bzl` to fetch the upstream core.
3. Add RTL patches in `bazel/` and `rtl/`.
4. Fill `dv/newcore/{harness,config}/` with harness and YAML config.
5. Reuse shared assets via `@rv_tester_common//...` (`dv:sim.sh`, `dv:gflags.cpp`, `dv:verilator_opts.bzl`, testbins, JSON); symlink `.bazelrc`, `bazel/deps.MODULE.bazel`, `bazel/*.patch`, and `infra/run-bazel.sh`.
6. Add CI jobs mirroring `cva6`/`openc910`.

> Note: `deps.MODULE.bazel` is `include()`d, not a `bazel_dep`, because `*_override` is root-only.
> Its labels resolve per-example, so each keeps its own `bazel/rules_verilator_propagate_exit.patch`.

## Quick Start

```bash
cd cva6
./infra/run-bazel.sh build --config=bzlmod //dv/cva6/verilator:cva6_tb_verilator
./infra/run-bazel.sh test  --config=bzlmod //dv/cva6/testlists:all_smoke --test_output=errors
```

See the example's `docs/README.md` for full details.

## Contributing

[GitHub Issues](https://github.com/tenstorrent/rv_tester_examples/issues) for bugs; [PRs](https://github.com/tenstorrent/rv_tester_examples/pulls) reviewed weekly.  
See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

Apache License, Version 2.0 — see [LICENSE](LICENSE), [NOTICE](NOTICE), [LICENSE_understanding](LICENSE_understanding).
