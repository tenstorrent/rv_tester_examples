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
| [`cva6/`](cva6/) | [CVA6](https://github.com/openhwgroup/cva6) (`cv64a6_imafdc_sv39`) | Runs CVA6 under `rv_tester` on Verilator, in lockstep against Whisper. See [`cva6/README.md`](cva6/README.md). |

More examples will be added as siblings of `cva6/`.

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
