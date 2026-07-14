# rv_tester_examples

Examples showing how to connect Tenstorrent's
[`rv_tester`](https://aus-gitlab.local.tenstorrent.com/riscv/dv/rv_tester)
testbench to various open-source RISC-V cores — checking each core
**instruction-by-instruction against the Whisper ISS in lockstep**.

Each example is a **self-contained Bazel workspace** in its own top-level
directory. The core and `rv_tester` are pulled in as Bazel dependencies; only the
integration *glue* (the SystemVerilog harness, Bazel wiring, and configuration)
lives here.

## Examples

| Example | Core | Description |
|---|---|---|
| [`cva6/`](cva6/) | [CVA6](https://github.com/openhwgroup/cva6) (`cv64a6_imafdc_sv39`) | Runs CVA6 under `rv_tester` on Verilator, in lockstep against Whisper. See [`cva6/README.md`](cva6/README.md). |

More examples will be added as siblings of `cva6/`.

## Getting started

Pick an example directory and follow its `README.md`. For CVA6:

```bash
cd cva6
# build the Verilator model
./infra/run-bazel.sh build --config=bzlmod //dv/cva6/verilator:cva6_tb_verilator
# run the smoke (build + lockstep run vs Whisper)
./infra/run-bazel.sh test  --config=bzlmod //dv/cva6/testlists:all_smoke --test_output=errors
```

## License

Apache-2.0 — see [LICENSE](LICENSE), [NOTICE](NOTICE), and the scope note in
[LICENSE_understanding](LICENSE_understanding). Contributions are welcome; see
[CONTRIBUTING.md](CONTRIBUTING.md).
