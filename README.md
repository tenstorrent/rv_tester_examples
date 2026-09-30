# rv_tester Examples

Bazel-based integration examples: connect Tenstorrent's `rv_tester` testbench to open-source RISC-V cores for **lockstep instruction-by-instruction verification against Whisper ISS**.

The repo is one Bazel module (`rv_tester_examples`); each example is a self-contained package tree, with the core and `rv_tester` as dependencies. Only the integration glue (harness, Bazel wiring, config) lives here.

## Examples

| Example | Core | Details |
|---|---|---|
| [`cva6/`](cva6/) | [CVA6](https://github.com/openhwgroup/cva6) `cv64a6_imafdc_sv39` | See [`cva6/docs/README.md`](cva6/docs/README.md) |
| [`openc910/`](openc910/) | [OpenC910](https://github.com/XUANTIE-RV/openc910) RV64GC | See [`openc910/docs/README.md`](openc910/docs/README.md) |

Test stimulus beyond the prebuilt testbins comes from
[`riescue_test_gen/`](riescue_test_gen/): [RiescueD](https://github.com/tenstorrent/riescue)
generates test ELFs at build time that run on either core — see
[`riescue_test_gen/docs/README.md`](riescue_test_gen/docs/README.md).

## Repository Layout

All dependencies (rv_tester, whisper, verilator, toolchains) are declared once
in the repo-root `MODULE.bazel`. Everything shared lives in
[`common/`](common/), referenced as `//common/...`: the test runner
(`dv/sim.sh`), the (elf, tb)-parameterized test/run wrappers
(`dv/sim_test.bzl`, `dv/sim_run.sh`), `dv/gflags.cpp`, the base Verilator options
(`dv/verilator_opts.bzl`), testbins, `dv/memmap.json`, `dv/whisper.json`,
the rules_verilator patch, and the container/bazel wrappers (`infra/`).

```
MODULE.bazel                  # ONE module for the whole repo; all deps declared here
.bazelrc                      # shared Bazel settings
common/                       # shared code & assets: sim.sh, gflags, verilator opts, testbins, configs, patch, infra
infra/run-bazel.sh            # -> common/infra/run-bazel.sh (cvm-container wrapper)
riescue_test_gen/             # RiescueD-generated test ELFs + run targets for both cores
<example>/
├── bazel/                    # core fetch extension + BUILD overlay
├── rtl/                      # RTL modifications
├── dv/
│   ├── BUILD.bazel           # codegen targets
│   ├── harness/              # top.sv, test_harness.sv, defines
│   ├── config/               # *.yml (topology, hart, platform, AXI)
│   ├── verilator/            # Verilator build
│   └── testlists/            # smoke tests
└── docs/                     # README
```

## Adding a New Example

1. Copy an existing example as `newcore/`.
2. Write `newcore/bazel/newcore_ext.bzl` to fetch the upstream core, and
   register it in the root `MODULE.bazel`.
3. Add RTL patches in `newcore/bazel/` and `newcore/rtl/`.
4. Fill `newcore/dv/newcore/{harness,config}/` with harness and YAML config.
5. Reuse shared assets via `//common/...`.
6. Add CI jobs mirroring `cva6`/`openc910`.

> Note: all deps sit directly in the root `MODULE.bazel` (not in an `include()`d
> file): this repo is also consumed as a `bazel_dep` by rv_tester's integration
> smoke, and Bazel allows `include()` only in the repo you run it from. The
> `*_override` pins only apply when this repo is the root.

## Quick Start

```bash
./infra/run-bazel.sh build --config=bzlmod //cva6/dv/verilator:cva6_tb_verilator
./infra/run-bazel.sh test  --config=bzlmod //cva6/dv/testlists:all_smoke --test_output=errors

# Run any ELF on a core ad hoc (see "Running an arbitrary ELF" below):
./infra/run-bazel.sh run   --config=bzlmod run_cva6 -- path/to/any.elf
```

### Running an arbitrary ELF

The root `BUILD.bazel` declares one ad-hoc runner per core, `//:run_cva6` and
`//:run_openc910`. Three rules:

1. **The ELF** goes after `--` (or `--run-args`) `+load=path/to/any.elf`.
2. **The target** goes before `--run-path`/`--run-args`/`--`. From the repo
   root the short name `run_cva6` works; from any subdirectory spell it as a
   full label, `//:run_cva6`.
3. **The target can be omitted** when you are inside a core's directory
   (`cva6/`, `openc910/`, or anything beneath them): the wrapper picks
   `//:run_<core>` from the first path component and prints which one it
   chose.

```bash
./infra/run-bazel.sh run --config=bzlmod run_cva6 -- +load=path/to/any.elf +max_instr=50000
./infra/run-bazel.sh run --config=bzlmod //:run_openc910 -- +load=path/to/any.elf +nometrics

# from openc910/, target inferred (//:run_openc910):
../infra/run-bazel.sh run --config=bzlmod --run-path abcd -- +nometrics +load=path/to/any.elf
```

### Extra simulator arguments

Pass `+plusargs` to a test or run target 

```bash
./infra/run-bazel.sh test --config=bzlmod //cva6/dv/testlists:hello_world_cva6_verilator -- +dbg=1000:5000 +save_all_files
```


### Where the output goes

By default the simulator writes its logs (`h0_dut_rvfi.log`, `iss_cosim.log`,
...), dumps, and `run.log`  into its working directory (bazel-testlogs)
To collect them elsewhere, pass `--run-path`,

```bash
./infra/run-bazel.sh run  --config=bzlmod //riescue_test_gen:openc910_issue_69_openc910_verilator --run-path results/issue_69 -- +nometrics
./infra/run-bazel.sh run  --config=bzlmod run_cva6 --run-path results/foo --run-args +load=path/to/foo.elf +dbg
./infra/run-bazel.sh test --config=bzlmod //cva6/dv/testlists:hello_world_cva6_verilator --run-path results/hello
```

See the example's `docs/README.md` for full details.

## Contributing

[GitHub Issues](https://github.com/tenstorrent/rv_tester_examples/issues) for bugs; [PRs](https://github.com/tenstorrent/rv_tester_examples/pulls) reviewed weekly.  
See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

Apache License, Version 2.0 — see [LICENSE](LICENSE), [NOTICE](NOTICE), [LICENSE_understanding](LICENSE_understanding).
