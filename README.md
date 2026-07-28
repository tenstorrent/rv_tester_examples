# rv_tester_examples

Examples showing how to connect Tenstorrent's `rv_tester` testbench to various
open-source RISC-V cores — checking each core **instruction-by-instruction
against the Whisper ISS in lockstep**.

Each example is a **self-contained Bazel workspace** in its own top-level
directory. The core and `rv_tester` are pulled in as Bazel dependencies; only the
integration *glue* (the SystemVerilog harness, Bazel wiring, and configuration)
lives here.

## Examples

| Example | Core | Description |
|---|---|---|
| [`cva6/`](cva6/) | [CVA6](https://github.com/openhwgroup/cva6) (`cv64a6_imafdc_sv39`) | Runs CVA6 under `rv_tester` on Verilator, in lockstep against Whisper. See [`cva6/docs/README.md`](cva6/docs/README.md). |
| [`openc910/`](openc910/) | [OpenC910](https://github.com/XUANTIE-RV/openc910) (XuanTie C910, RV64GC) | Runs OpenC910 under `rv_tester` on Verilator, in lockstep against Whisper. See [`openc910/docs/README.md`](openc910/docs/README.md). |

More examples are added as siblings of `cva6/` following the standard layout below.

## Repository layout

Shared, core-agnostic assets live once in the [`common/`](common/) module
(`rv_tester_common`): generic test binaries (`testbins/`), shared testbench
config (`dv/memmap.json`, `dv/whisper.json`), and the shared Bazel flags
(`bazelrc/common.bazelrc`, symlinked as each example's `.bazelrc`).

Every example is an **independent Bazel workspace** that follows the same fixed
skeleton so a new core drops in mechanically:

```
<example>/
├── MODULE.bazel        # bzlmod root: deps + overrides + the core fetch extension
├── .bazelrc            # symlink -> ../common/bazelrc/common.bazelrc
├── bazel/              # example-specific external fetch/overlay (<core>_ext.bzl, <core>.BUILD, patch)
├── rtl/                # example-specific hand-written RTL + RTL-modifying inputs (apply scripts, patches)
├── dv/
│   ├── verilator_opts.bzl
│   └── <core>/
│       ├── BUILD.bazel # topology_gen + rv_tester_gen + dpi_glue
│       ├── harness/    # top.sv, <core>_test_harness.sv, defines/undefines
│       ├── config/     # *.yml topology/hart/platform/axi + *.vlt lint config
│       ├── verilator/  # verilog_library -> verilator_cc_library -> cc_binary
│       └── testlists/  # smoke sh_test + sim.sh
├── infra/              # run-bazel.sh (podman wrapper)
└── docs/               # README + analysis notes
```

## Adding a new example

1. Copy an existing example directory (e.g. `cva6/`) as `newcore/` and keep the
   skeleton above.
2. In `bazel/`, write `newcore_ext.bzl` (+ `newcore.BUILD` overlay) to fetch the
   upstream core; put any RTL-modifying patches/scripts under `rtl/`.
3. Fill `dv/newcore/harness/` and `dv/newcore/config/` with the core-specific
   harness and topology/hart/platform YAML.
4. Reuse the shared assets via `@rv_tester_common//...` (testbins, `dv/memmap.json`,
   `dv/whisper.json`); symlink `.bazelrc -> ../common/bazelrc/common.bazelrc`.
5. Add a CI job mirroring the `cva6`/`openc910` build + smoke jobs.

> Note: bzlmod `single_version_override(patches=...)` only accepts patches from
> the root module, so each example keeps its own copy of
> `bazel/rules_verilator_propagate_exit.patch`.

## Getting Started

Pick an example directory and follow its `README.md`. For CVA6:

```bash
cd cva6
# build the Verilator model
./infra/run-bazel.sh build --config=bzlmod //dv/cva6/verilator:cva6_tb_verilator
# run the smoke (build + lockstep run vs Whisper)
./infra/run-bazel.sh test  --config=bzlmod //dv/cva6/testlists:all_smoke --test_output=errors
```

## Contributing

Bug reports are welcome via [GitHub Issues](https://github.com/tenstorrent/rv_tester_examples/issues).
Bug fixes and new functionality can be submitted as
[Pull Requests](https://github.com/tenstorrent/rv_tester_examples/pulls);
PRs are reviewed on a weekly cadence.

See [CONTRIBUTING.md](CONTRIBUTING.md) for full details and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community guidelines.

## License

This project is licensed under the **Apache License, Version 2.0** — see
[LICENSE](LICENSE) for the overall license for this project, except where
specified.

Additional license information:

- [NOTICE](NOTICE) — copyright attribution and third-party notices
- [LICENSE_understanding](LICENSE_understanding) — clarification of how the
  Apache 2.0 license applies to this project
