# Contributing to rv_tester_examples

Thanks for your interest in contributing. This repo collects self-contained
examples that run open-source RISC-V cores under the `rv_tester` testbench. Each
example lives in its own top-level directory (currently just
[`cva6/`](cva6/)) and is a complete Bazel workspace — see that example's
`README.md` for its architecture, dependencies, and build/run instructions.

## Getting set up

Examples build with **Bazel 7** inside the **cvm** podman image; the system
`bazel` (6.5) will not work. Work from within the example directory. For CVA6:

```bash
cd cva6

# build the Verilator model
./infra/run-bazel.sh build --config=bzlmod //dv/cva6/verilator:cva6_tb_verilator

# run the smoke (build + lockstep run vs Whisper)
./infra/run-bazel.sh test  --config=bzlmod //dv/cva6/testlists:all_smoke --test_output=errors
```

See the example's README §3 for the full requirements (Bazel 7, cvm image,
network access).

## Before you open a pull request

1. **Build and run the smoke** for the example you touched — e.g.
   `//dv/cva6/testlists:all_smoke` must pass.
2. **Keep CI green** — any test you add that is known-failing or slow should be
   tagged `manual` and kept out of the example's smoke suite (as
   `hello_world_cva6_verilator` is).
3. **Match the surrounding style** — mirror the existing SystemVerilog, Starlark
   (BUILD/`.bzl`), and comment conventions in the files you touch. Keep comments
   focused on *why*, not *what*.
4. **Prefer stock dependencies** — the cores, rv_tester, whisper, etc. are
   fetched by Bazel at pinned commits. Avoid vendoring their source into this
   repo; if you must adjust a dependency, do it via a pin bump or a fetch-rule
   patch rather than a committed copy.

## Adding a new example

Add it as a new top-level directory (a sibling of `cva6/`), self-contained with
its own `MODULE.bazel`, `bazel/`, `infra/`, and `dv/`. Add a row to the table in
the top-level [README.md](README.md) linking to it.

## Commit messages

- Write a concise imperative subject line and a body explaining the *why*.
- Sign off your commits (`git commit -s`) to certify the
  [Developer Certificate of Origin](https://developercertificate.org/).

## Licensing

Contributions are accepted under the **Apache License, Version 2.0** (see
[LICENSE](LICENSE) and [NOTICE](NOTICE)). By submitting a change you agree that
your contribution is licensed under those terms. Note also the scope statement in
[LICENSE_understanding](LICENSE_understanding).
