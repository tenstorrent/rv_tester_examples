# rv_tester Examples

Bazel-based integration examples: connect Tenstorrent's `rv_tester` testbench to open-source RISC-V cores for **lockstep instruction-by-instruction verification against Whisper ISS**.

Each example is a self-contained Bazel workspace; the core and `rv_tester` are dependencies. Only the integration glue (harness, Bazel wiring, config) lives here.

## Examples

| Example | Core | Details |
|---|---|---|
| [`cva6/`](cva6/) | [CVA6](https://github.com/openhwgroup/cva6) `cv64a6_imafdc_sv39` | See [`cva6/docs/README.md`](cva6/docs/README.md) |
| [`openc910/`](openc910/) | [OpenC910](https://github.com/XUANTIE-RV/openc910) RV64GC | See [`openc910/docs/README.md`](openc910/docs/README.md) |

## Repository Layout

Shared assets in [`common/`](common/) (`rv_tester_common`): testbins, `dv/memmap.json`, `dv/whisper.json`, `bazelrc/common.bazelrc`.

Each example skeleton:
```
<example>/
├── MODULE.bazel              # dependencies
├── .bazelrc                  # → ../common/bazelrc/common.bazelrc
├── bazel/                    # fetch extensions + patches
├── rtl/                      # RTL modifications
├── dv/<core>/
│   ├── BUILD.bazel           # codegen targets
│   ├── harness/              # top.sv, test_harness.sv, defines
│   ├── config/               # *.yml (topology, hart, platform, AXI)
│   ├── verilator/            # Verilator build
│   └── testlists/            # smoke tests
├── infra/                    # run-bazel.sh wrapper
└── docs/                     # README
```

## Adding a New Example

1. Copy an existing example as `newcore/`.
2. Write `bazel/newcore_ext.bzl` to fetch the upstream core.
3. Add RTL patches in `bazel/` and `rtl/`.
4. Fill `dv/newcore/{harness,config}/` with harness and YAML config.
5. Reuse shared assets via `@rv_tester_common//...` and symlink `.bazelrc`.
6. Add CI jobs mirroring `cva6`/`openc910`.

> Note: Each example keeps its own copy of `bazel/rules_verilator_propagate_exit.patch` (bzlmod constraint).

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
